with Ada.Command_Line;
with Ada.Containers;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Terminal_Styles;
with Ada_Quality.Checks;
with Ada_Quality.History;
with Ada_Quality.JSON;
with Ada_Quality.Policy;
with Ada_Quality.Presentation;
with Ada_Quality.Storage;
with Ada_Quality.Types;

--  AQ: complexity-reviewed -- the centralized dispatcher preserves one strict command grammar and exit contract.
package body Ada_Quality.CLI is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;

   function Argument (Index : Positive) return String is
     (if Index <= Ada.Command_Line.Argument_Count then Ada.Command_Line.Argument (Index) else "");

   function Option (Name, Default : String) return String is
   begin
      for J in 1 .. Ada.Command_Line.Argument_Count - 1 loop
         if Argument (J) = Name then return Argument (J + 1); end if;
      end loop;
      return Default;
   end Option;

   function Starts_With (Text, Prefix : String) return Boolean is
     (Text'Length >= Prefix'Length and then
      Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix);

   function Positional (Index : Positive) return String is
      Count      : Natural := 0;
      Skip_Value : Boolean := False;
   begin
      for J in 1 .. Ada.Command_Line.Argument_Count loop
         declare
            Value : constant String := Argument (J);
         begin
            if Skip_Value then
               Skip_Value := False;
            elsif Value in "--database" | "--policy" | "--color" | "--project" | "--format" then
               Skip_Value := True;
            elsif Value in "--no-color" | "--all" | "--json" then
               null;
            else
               Count := Count + 1;
               if Count = Index then return Value; end if;
            end if;
         end;
      end loop;
      return "";
   end Positional;

   procedure Validate_Options is
      Index : Positive := 1;

      function Takes_Value (Name : String) return Boolean is
        (Name in "--database" | "--policy" | "--color" | "--project" | "--format");

      function Allowed (Name : String) return Boolean is
        (Takes_Value (Name) or else Name in "--no-color" | "--all" | "--json");
   begin
      while Index <= Ada.Command_Line.Argument_Count loop
         declare
            Value : constant String := Argument (Index);
         begin
            if Starts_With (Value, "--") then
               if not Allowed (Value) then
                  raise Constraint_Error with "unknown option: " & Value;
               elsif Takes_Value (Value) then
                  if Index = Ada.Command_Line.Argument_Count or else Starts_With (Argument (Index + 1), "--") then
                     raise Constraint_Error with "option requires a value: " & Value;
                  end if;
                  Index := Index + 1;
               end if;
            end if;
         end;
         Index := Index + 1;
      end loop;
      if Option ("--color", "never") not in "never" | "auto" | "always" then
         raise Constraint_Error with "--color requires never, auto, or always";
      end if;
      if Option ("--project", "") /= "" and then
        (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--all")
      then
         raise Constraint_Error with "--all and --project are mutually exclusive";
      end if;
   end Validate_Options;

   function Default_Database return String is
   begin
      if Ada.Environment_Variables.Exists ("ADA_QUALITY_DATABASE") then
         return Ada.Environment_Variables.Value ("ADA_QUALITY_DATABASE");
      end if;
      return ".ada-quality.db";
   end Default_Database;

   function Default_Policy return String is
   begin
      if Ada.Environment_Variables.Exists ("ADA_QUALITY_POLICY") then
         return Ada.Environment_Variables.Value ("ADA_QUALITY_POLICY");
      end if;
      return "quality-policy.toml";
   end Default_Policy;

   procedure Help is
   begin
      Ada.Text_IO.Put_Line ("ada-quality " & Ada_Quality.Version);
      Ada.Text_IO.Put_Line ("Usage: ada-quality [global options] <command> [options]");
      Ada.Text_IO.Put_Line ("");
      Ada.Text_IO.Put_Line ("Commands:");
      Ada.Text_IO.Put_Line ("  project add PATH | list | show ID | enable ID | disable ID | remove ID");
      Ada.Text_IO.Put_Line ("  check --all | --project ID [--json]");
      Ada.Text_IO.Put_Line ("  status | findings | regressions | history");
      Ada.Text_IO.Put_Line ("  report --format json");
      Ada.Text_IO.Put_Line ("  policy validate | show");
      Ada.Text_IO.Put_Line ("  database init | check | recover");
      Ada.Text_IO.Put_Line ("");
      Ada.Text_IO.Put_Line ("Global options: --database PATH --policy PATH --no-color");
   end Help;

   procedure Put_Project (P : Ada_Quality.Storage.Project_Info) is
   begin
      Ada.Text_IO.Put_Line
        (Positive'Image (P.Id) & "  " & To_String (P.Path) & "  " &
         (if P.Removed then "removed" elsif P.Enabled then "enabled" else "disabled"));
   end Put_Project;

   function Result_Exit (Value : Assessment) return Natural is
      Has_Violation  : Boolean := False;
      Has_Incomplete : Boolean := False;
   begin
      for R of Value.Results loop
         Has_Violation := Has_Violation or else R.Compliance = Violation;
         Has_Incomplete := Has_Incomplete or else R.Execution in Blocked | Failed | Errored;
      end loop;
      if Value.Status /= Assessment_Completed or else Has_Incomplete then return 3;
      elsif Has_Violation then return 1;
      else return 0;
      end if;
   end Result_Exit;

   procedure Print_Assessment (Value : Assessment) is
      Role : Terminal_Styles.Style_Role;
   begin
      for R of Value.Results loop
         Role :=
           (if R.Compliance = Pass then Terminal_Styles.Role_Success
            elsif R.Compliance = Violation then Terminal_Styles.Role_Error
            elsif R.Execution = Not_Applicable then Terminal_Styles.Role_Muted
            else Terminal_Styles.Role_Warning);
         Ada.Text_IO.Put_Line
           (Terminal_Styles.Decorate
              (Ada_Quality.Presentation.Result_Line
                 (Terminal_Styles.Marker (Role), Image (R.Indicator), To_String (R.Summary)), Role));
      end loop;
   end Print_Assessment;

   function Run return Natural is
      Command     : constant String := Positional (1);
      Subcommand  : constant String := Positional (2);
      DB_Path     : constant String := Option ("--database", Default_Database);
      Policy_Path : constant String := Option ("--policy", Default_Policy);
      Store       : Ada_Quality.Storage.Store;

      procedure Open_Store (Create : Boolean := True) is
      begin
         Ada_Quality.Storage.Open (Store, DB_Path, Create);
      end Open_Store;

      function Id_Argument (Index : Positive) return Positive is
      begin
         return Positive'Value (Positional (Index));
      exception
         when Constraint_Error =>
            raise Constraint_Error with "a positive project ID is required";
      end Id_Argument;
   begin
      if Ada.Command_Line.Argument_Count = 0 or else Command in "help" | "--help" | "-h" then
         Help;
         return 0;
      elsif Command in "version" | "--version" then
         Ada.Text_IO.Put_Line (Ada_Quality.Version);
         return 0;
      end if;

      Validate_Options;

      if Option ("--color", "") = "never" or else
        (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--no-color")
      then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
      elsif Option ("--color", "") = "always" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Always);
      elsif Option ("--color", "") = "auto" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Auto);
      end if;

      if Command = "database" then
         if Subcommand = "" then raise Constraint_Error with "database operation is required"; end if;
         if Subcommand = "init" then
            Open_Store;
            Ada_Quality.Storage.Check (Store);
            Ada.Text_IO.Put_Line ("initialized " & DB_Path);
         elsif Subcommand = "check" then
            Open_Store (False);
            Ada_Quality.Storage.Check (Store);
            Ada.Text_IO.Put_Line ("database integrity check passed");
         elsif Subcommand = "recover" then
            Open_Store (False);
            declare
               Count : Natural;
            begin
               Ada_Quality.Storage.Recover (Store, Count);
               Ada.Text_IO.Put_Line ("recovered" & Natural'Image (Count) & " assessment(s)");
            end;
         else
            raise Constraint_Error with "database requires init, check, or recover";
         end if;
         return 0;
      elsif Command = "policy" then
         if Subcommand = "" then raise Constraint_Error with "policy operation is required"; end if;
         declare
            Loaded : constant Ada_Quality.Policy.Load_Result := Ada_Quality.Policy.Load (Policy_Path);
         begin
            if not Loaded.Success then
               Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, To_String (Loaded.Error));
               return 2;
            elsif Subcommand = "validate" then
               Ada.Text_IO.Put_Line ("valid policy " & Ada_Quality.Policy.Fingerprint (Loaded.Value));
            elsif Subcommand = "show" then
               Ada.Text_IO.Put_Line ("coverage_minimum_basis_points =" &
                 Natural'Image (Loaded.Value.Coverage_Minimum_Basis_Points));
               Ada.Text_IO.Put_Line ("maximum_source_lines =" & Positive'Image (Loaded.Value.Maximum_Source_Lines));
               Ada.Text_IO.Put_Line ("maximum_complexity =" & Positive'Image (Loaded.Value.Maximum_Complexity));
               Ada.Text_IO.Put_Line
                 ("process_timeout_seconds =" & Positive'Image (Loaded.Value.Process_Timeout_Seconds));
               Ada.Text_IO.Put_Line ("maximum_output_bytes =" & Positive'Image (Loaded.Value.Maximum_Output_Bytes));
               Ada.Text_IO.Put_Line
                 ("require_clean_worktree = " & Boolean'Image (Loaded.Value.Require_Clean_Worktree));
            else
               raise Constraint_Error with "policy requires validate or show";
            end if;
         end;
         return 0;
      end if;

      Open_Store;
      if Command = "project" then
         if Subcommand = "add" then
            if Positional (3) = "" or else Starts_With (Positional (3), "--") then
               raise Constraint_Error with "project add requires a path";
            end if;
            declare
               Id : constant Positive := Ada_Quality.Storage.Add_Project (Store, Positional (3));
            begin
               Ada.Text_IO.Put_Line ("registered project" & Positive'Image (Id));
            end;
         elsif Subcommand = "list" then
            for P of Ada_Quality.Storage.Projects (Store) loop Put_Project (P); end loop;
         elsif Subcommand = "show" then
            Put_Project (Ada_Quality.Storage.Project (Store, Id_Argument (3)));
         elsif Subcommand = "enable" then
            Ada_Quality.Storage.Set_Enabled (Store, Id_Argument (3), True);
         elsif Subcommand = "disable" then
            Ada_Quality.Storage.Set_Enabled (Store, Id_Argument (3), False);
         elsif Subcommand = "remove" then
            Ada_Quality.Storage.Remove_Project (Store, Id_Argument (3));
         else
            raise Constraint_Error with "unknown project subcommand";
         end if;
         return 0;
      elsif Command = "check" then
         declare
            Loaded : constant Ada_Quality.Policy.Load_Result := Ada_Quality.Policy.Load (Policy_Path);
            Exit_Code : Natural := 0;
            JSON_Mode : constant Boolean :=
              (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--json");

            procedure Check_Project (P : Ada_Quality.Storage.Project_Info) is
               Run_Id : constant Positive :=
                 Ada_Quality.Storage.Start_Assessment
                   (Store, P.Id, Ada_Quality.Checks.Source_Fingerprint (To_String (P.Path)),
                    Ada_Quality.Policy.Fingerprint (Loaded.Value));
               Value  : Assessment := Ada_Quality.Checks.Assess (P.Id, To_String (P.Path), Loaded.Value);
            begin
               Value.Id := Run_Id;
               if Ada_Quality.Storage.Publish (Store, Value) /= Run_Id then
                  raise Ada_Quality.Storage.Storage_Error with "assessment publication changed its identifier";
               end if;
               Exit_Code := Natural'Max (Exit_Code, Result_Exit (Value));
               if JSON_Mode then Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render (Value, Pretty => True));
               else Print_Assessment (Value); end if;
            exception
               when others =>  --  AQ: audited exception boundary
                  Ada_Quality.Storage.Interrupt_Assessment
                    (Store, Run_Id, "assessment aborted by an unexpected controller exception");
                  raise;
            end Check_Project;
         begin
            if not Loaded.Success then
               Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, To_String (Loaded.Error));
               return 2;
            elsif Option ("--project", "") /= "" then
               declare
                  P : constant Ada_Quality.Storage.Project_Info :=
                    Ada_Quality.Storage.Project (Store, Positive'Value (Option ("--project", "")));
               begin
                  if P.Removed or else not P.Enabled then raise Constraint_Error with "project is not enabled"; end if;
                  Check_Project (P);
               end;
            elsif (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--all") then
               for P of Ada_Quality.Storage.Projects (Store) loop
                  if P.Enabled and then not P.Removed then Check_Project (P); end if;
               end loop;
            else
               raise Constraint_Error with "check requires --all or --project ID";
            end if;
            return Exit_Code;
         end;
      elsif Command = "history" or else Command = "status" then
         for H of Ada_Quality.Storage.History (Store) loop
            Ada.Text_IO.Put_Line
              (Positive'Image (H.Id) & " project" & Positive'Image (H.Project_Id) & " " & To_String (H.Status));
         end loop;
         return 0;
      elsif Command = "findings" then
         for P of Ada_Quality.Storage.Projects (Store, Include_Removed => True) loop
            declare
               Runs : constant Ada_Quality.Storage.History_Vectors.Vector :=
                 Ada_Quality.Storage.History (Store, P.Id);
            begin
               if not Runs.Is_Empty then
                  declare
                     Latest   : constant Ada_Quality.Storage.History_Item := Runs.Last_Element;
                     Current  : constant Ada_Quality.Storage.Detail_Vectors.Vector :=
                       Ada_Quality.Storage.Findings (Store, Latest.Id);
                     Current_Results : constant Ada_Quality.Storage.Detail_Vectors.Vector :=
                       Ada_Quality.Storage.Results (Store, Latest.Id);
                     Previous : Ada_Quality.Storage.Detail_Vectors.Vector;
                     Older    : Ada_Quality.Storage.Detail_Vectors.Vector;
                     Baseline : constant Natural := Ada_Quality.History.Baseline_Id (Runs, Latest.Id);

                     function Has
                       (Items : Ada_Quality.Storage.Detail_Vectors.Vector;
                        Key   : Ada.Strings.Unbounded.Unbounded_String) return Boolean
                     is
                     begin
                        for F of Items loop
                           if F.Kind = Key then return True; end if;
                        end loop;
                        return False;
                     end Has;

                     function Successfully_Remeasured
                       (Finding_Key : Ada.Strings.Unbounded.Unbounded_String) return Boolean
                     is
                        Text  : constant String := To_String (Finding_Key);
                        Colon : constant Natural := Ada.Strings.Fixed.Index (Text, ":");
                     begin
                        if Colon <= Text'First then return False; end if;
                        for Item of Current_Results loop
                           if To_String (Item.Kind) = Text (Text'First .. Colon - 1) then
                              return Ada.Strings.Fixed.Index (To_String (Item.State), "succeeded/") = 1;
                           end if;
                        end loop;
                        return False;
                     end Successfully_Remeasured;
                  begin
                     if Baseline > 0 then
                        Previous := Ada_Quality.Storage.Findings (Store, Baseline);
                        for Run of Runs loop
                           exit when Run.Id = Baseline;
                           for Finding of Ada_Quality.Storage.Findings (Store, Run.Id) loop
                              Older.Append (Finding);
                           end loop;
                        end loop;
                     elsif To_String (Latest.Status) /= "completed" and then Runs.Length >= 2 then
                        Previous := Ada_Quality.Storage.Findings (Store, Runs (Runs.Last_Index - 1).Id);
                     end if;
                     for F of Current loop
                        declare
                           Lifecycle : constant Ada_Quality.History.Finding_Lifecycle :=
                             Ada_Quality.History.Classify_Finding
                               (F.Kind, Current, Previous, Older,
                                To_String (Latest.Status) = "completed");
                        begin
                           Ada.Text_IO.Put_Line
                             (Ada_Quality.History.Image (Lifecycle) & " " & To_String (F.State) & " " &
                              To_String (F.Summary));
                        end;
                     end loop;
                     for F of Previous loop
                        if not Has (Current, F.Kind) then
                           declare
                              Lifecycle : constant Ada_Quality.History.Finding_Lifecycle :=
                                Ada_Quality.History.Classify_Finding
                                  (F.Kind, Current, Previous, Older,
                                   To_String (Latest.Status) = "completed" and then
                                     Successfully_Remeasured (F.Kind));
                           begin
                              if Lifecycle in Ada_Quality.History.Resolved | Ada_Quality.History.Unconfirmed then
                                 Ada.Text_IO.Put_Line
                                   (Ada_Quality.History.Image (Lifecycle) & " " & To_String (F.State) & " " &
                                    To_String (F.Summary));
                              end if;
                           end;
                        end if;
                     end loop;
                  end;
               end if;
            end;
         end loop;
         return 0;
      elsif Command = "regressions" then
         declare
            Projects_Seen : Natural := 0;

            function Find_Run
              (Runs : Ada_Quality.Storage.History_Vectors.Vector;
               Id   : Positive) return Ada_Quality.Storage.History_Item is
            begin
               for Candidate of Runs loop
                  if Candidate.Id = Id then return Candidate; end if;
               end loop;
               raise Constraint_Error with "assessment baseline not found";
            end Find_Run;
         begin
            for P of Ada_Quality.Storage.Projects (Store) loop
               Projects_Seen := Projects_Seen + 1;
               declare
                  Runs : constant Ada_Quality.Storage.History_Vectors.Vector :=
                    Ada_Quality.Storage.History (Store, P.Id);
               begin
                  if Runs.Length >= 2 then
                     declare
                        Current_Run : constant Ada_Quality.Storage.History_Item := Runs.Last_Element;
                        Compatible_Id : constant Natural :=
                          Ada_Quality.History.Baseline_Id (Runs, Current_Run.Id);
                        Previous_Run : constant Ada_Quality.Storage.History_Item :=
                          Runs (Runs.Last_Index - 1);
                        Policy_Comparison : constant Boolean :=
                          Compatible_Id = 0 and then
                          Previous_Run.Policy_Fingerprint /= Current_Run.Policy_Fingerprint and then
                          Previous_Run.Toolchain_Fingerprint = Current_Run.Toolchain_Fingerprint;
                        Baseline_Run : constant Ada_Quality.Storage.History_Item :=
                          (if Compatible_Id > 0 then Find_Run (Runs, Compatible_Id)
                           else Previous_Run);
                     begin
                        if To_String (Current_Run.Status) /= "completed" then
                           Ada.Text_IO.Put_Line
                             ("project" & Positive'Image (P.Id) &
                              ": comparison unavailable: current assessment is not completed");
                        elsif Compatible_Id = 0 and then not Policy_Comparison then
                           Ada.Text_IO.Put_Line
                             ("project" & Positive'Image (P.Id) &
                              (if To_String (Previous_Run.Status) /= "completed" then
                                  ": comparison unavailable: no completed baseline exists"
                               elsif Previous_Run.Toolchain_Fingerprint /= Current_Run.Toolchain_Fingerprint then
                                  ": comparison unavailable: toolchain fingerprint changed"
                               else ": comparison unavailable: no compatible baseline exists"));
                        else
                           declare
                              Changes : constant Ada_Quality.History.Regression_Vectors.Vector :=
                                Ada_Quality.History.Compare
                                  (Baseline_Run, Current_Run,
                                   Ada_Quality.Storage.Results (Store, Baseline_Run.Id),
                                   Ada_Quality.Storage.Results (Store, Current_Run.Id),
                                   Ada_Quality.Storage.Measurements (Store, Baseline_Run.Id),
                                   Ada_Quality.Storage.Measurements (Store, Current_Run.Id),
                                   Ada_Quality.Storage.Findings (Store, Baseline_Run.Id),
                                   Ada_Quality.Storage.Findings (Store, Current_Run.Id));
                           begin
                              if Changes.Is_Empty then
                                 Ada.Text_IO.Put_Line
                                   ("project" & Positive'Image (P.Id) &
                                    ": no regressions in comparable assessments");
                              else
                                 for Change of Changes loop
                                    Ada.Text_IO.Put_Line
                                      ("project" & Positive'Image (P.Id) & " " & Image (Change.Indicator) & " " &
                                       Ada_Quality.History.Image (Change.Kind) & ": " &
                                       To_String (Change.Before) & " -> " & To_String (Change.After));
                                 end loop;
                              end if;
                           end;
                        end if;
                     end;
                  elsif Runs.Is_Empty then
                     Ada.Text_IO.Put_Line
                       ("project" & Positive'Image (P.Id) &
                        ": comparison unavailable: no assessments exist");
                  else
                     Ada.Text_IO.Put_Line
                       ("project" & Positive'Image (P.Id) &
                        ": comparison unavailable: no baseline assessment exists");
                  end if;
               end;
            end loop;
            if Projects_Seen = 0 then
               Ada.Text_IO.Put_Line ("comparison unavailable: no projects are registered");
            end if;
         end;
         return 0;
      elsif Command = "report" and then Option ("--format", "") = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render_Archive (Store, Pretty => True));
         return 0;
      else
         raise Constraint_Error with "unknown command: " & Command;
      end if;
   exception
      when E : Ada_Quality.Storage.Storage_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         return 4;
      when E : Constraint_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         return 2;
      when E : others =>  --  AQ: audited exception boundary
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Information (E));
         return 3;
   end Run;
end Ada_Quality.CLI;
