with Ada.Command_Line;
with Ada.Containers;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Terminal_Styles;
with Ada_Quality.CI_Formats;
with Ada_Quality.Checks;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.JSON;
with Ada_Quality.Policy;
with Ada_Quality.Presentation;
with Ada_Quality.Reporting;
with Ada_Quality.Storage;
with Ada_Quality.Types;

--  AQ-WAIVER: SRC-03 target=id_argument justification=command parsing and dispatch share one bounded pass
package body Ada_Quality.CLI is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.History.Comparison_Status;

   Usage_Error : exception;

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
            elsif Value in "--database" | "--policy" | "--color" | "--project" | "--format" |
              "--current" | "--indicator"
            then
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
        (Name in "--database" | "--policy" | "--color" | "--project" | "--format" |
           "--current" | "--indicator");

      function Allowed (Name : String) return Boolean is
        (Takes_Value (Name) or else Name in "--no-color" | "--all" | "--json");
   begin
      while Index <= Ada.Command_Line.Argument_Count loop
         declare
            Value : constant String := Argument (Index);
         begin
            if Starts_With (Value, "--") then
               if not Allowed (Value) then
                  raise Usage_Error with "unknown option: " & Value;
               elsif Takes_Value (Value) then
                  if Index = Ada.Command_Line.Argument_Count or else Starts_With (Argument (Index + 1), "--") then
                     raise Usage_Error with "option requires a value: " & Value;
                  end if;
                  Index := Index + 1;
               end if;
            end if;
         end;
         Index := Index + 1;
      end loop;
      if Option ("--color", "never") not in "never" | "auto" | "always" then
         raise Usage_Error with "--color requires never, auto, or always";
      end if;
      if Option ("--project", "") /= "" and then
        (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--all")
      then
         raise Usage_Error with "--all and --project are mutually exclusive";
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
      Ada.Text_IO.Put_Line ("  assessment show RUN_ID [--format text|json|sarif|junit]");
      Ada.Text_IO.Put_Line ("  status | findings | history");
      Ada.Text_IO.Put_Line ("  regressions [--project ID] [--current RUN_ID]");
      Ada.Text_IO.Put_Line ("  trend --project ID --indicator ID [--json]");
      Ada.Text_IO.Put_Line ("  report --format json");
      Ada.Text_IO.Put_Line ("  policy validate | show");
      Ada.Text_IO.Put_Line ("  database init | check | recover");
      Ada.Text_IO.Put_Line ("");
      Ada.Text_IO.Put_Line ("Global options: --database PATH --policy PATH --no-color");
   end Help;

   procedure Put_Project (P : Ada_Quality.Reporting.Project_Record) is
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

   function Stored_Assessment
     (Session : Ada_Quality.Reporting.Session;
      Run_Id  : Positive) return Assessment
   is
      Stored  : constant Ada_Quality.Reporting.Assessment_Record :=
        Ada_Quality.Reporting.Read_Assessment (Session, Run_Id);
      Project : constant Ada_Quality.Reporting.Project_Record :=
        Ada_Quality.Reporting.Project (Session, Stored.Run.Project_Id);
      Result  : Assessment;
   begin
      Result.Id := Stored.Run.Id;
      Result.Project_Id := Stored.Run.Project_Id;
      Result.Project_Path := Project.Path;
      Result.Source_Fingerprint := Stored.Run.Source_Id;
      Result.Policy_Fingerprint := Stored.Run.Policy_Id;
      Result.Toolchain_Fingerprint := Stored.Run.Toolchain_Id;
      Result.Status := Stored.Run.State;
      Result.Results := Stored.Results;
      for Execution of Stored.Executions loop
         Result.Executions.Append
           (Tool_Execution'
              (Tool => Execution.Tool, Command => Execution.Command,
               Status => Execution.Status, Exit_Code => Execution.Exit_Code,
               Output_Digest => Execution.Output_Digest,
               Output_Bytes => Execution.Output_Bytes, Truncated => Execution.Truncated));
      end loop;
      return Result;
   end Stored_Assessment;

   procedure Print_Comparison
     (Comparison : Ada_Quality.Reporting.Project_Comparison)
   is
   begin
      if Comparison.Selection.Status = Ada_Quality.History.Comparison_Available then
         if Comparison.Changes.Is_Empty then
            Ada.Text_IO.Put_Line
              ("project" & Positive'Image (Comparison.Project_Id) &
               ": no regressions in comparable assessments");
         else
            for Change of Comparison.Changes loop
               Ada.Text_IO.Put_Line
                 ("project" & Positive'Image (Comparison.Project_Id) & " " &
                  Image (Change.Indicator) & " " & Ada_Quality.History.Image (Change.Kind) & ": " &
                  To_String (Change.Before) & " -> " & To_String (Change.After));
            end loop;
         end if;
      else
         Ada.Text_IO.Put_Line
           ("project" & Positive'Image (Comparison.Project_Id) &
            ": comparison unavailable: " &
            (case Comparison.Selection.Status is
                when Ada_Quality.History.No_Assessments => "no assessments exist",
                when Ada_Quality.History.No_Baseline => "no baseline assessment exists",
                when Ada_Quality.History.Current_Incomplete => "current assessment is not completed",
                when Ada_Quality.History.No_Completed_Baseline => "no completed baseline exists",
                when Ada_Quality.History.Toolchain_Changed => "toolchain fingerprint changed",
                when Ada_Quality.History.No_Compatible_Baseline => "no compatible baseline exists",
                when Ada_Quality.History.Comparison_Available => "comparison is available"));
      end if;
   end Print_Comparison;

   procedure Print_Findings (DB_Path : String) is separate;

   function Run_Check
     (Store : in out Ada_Quality.Storage.Store;
      Policy_Path : String) return Natural is separate;

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

      function Positive_Option (Name, Kind : String) return Positive is
      begin
         return Positive'Value (Option (Name, ""));
      exception
         when Constraint_Error =>
            raise Usage_Error with "a positive " & Kind & " ID is required";
      end Positive_Option;

      function Assessment_Id_Argument (Index : Positive) return Positive is
      begin
         return Positive'Value (Positional (Index));
      exception
         when Constraint_Error =>
            raise Usage_Error with "a positive assessment ID is required";
      end Assessment_Id_Argument;

      function Id_Argument (Index : Positive) return Positive is
      begin
         return Positive'Value (Positional (Index));
      exception
         when Constraint_Error =>
            raise Usage_Error with "a positive project ID is required";
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
         if Subcommand = "" then raise Usage_Error with "database operation is required"; end if;
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
            raise Usage_Error with "database requires init, check, or recover";
         end if;
         return 0;
      elsif Command = "policy" then
         if Subcommand = "" then raise Usage_Error with "policy operation is required"; end if;
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
               raise Usage_Error with "policy requires validate or show";
            end if;
         end;
         return 0;
      end if;

      if Command = "check" or else
        (Command = "project" and then Subcommand in "add" | "enable" | "disable" | "remove")
      then
         Open_Store;
         Ada_Quality.Storage.Check (Store);
      end if;
      if Command = "project" then
         if Subcommand = "add" then
            if Positional (3) = "" or else Starts_With (Positional (3), "--") then
               raise Usage_Error with "project add requires a path";
            end if;
            declare
               Id : constant Positive := Ada_Quality.Storage.Add_Project (Store, Positional (3));
            begin
               Ada.Text_IO.Put_Line ("registered project" & Positive'Image (Id));
            end;
         elsif Subcommand = "list" then
            declare
               Session : Ada_Quality.Reporting.Session;
            begin
               Ada_Quality.Reporting.Open (Session, DB_Path);
               for P of Ada_Quality.Reporting.Projects (Session) loop Put_Project (P); end loop;
            end;
         elsif Subcommand = "show" then
            declare
               Session : Ada_Quality.Reporting.Session;
               Id      : constant Positive := Id_Argument (3);
            begin
               Ada_Quality.Reporting.Open (Session, DB_Path);
               Put_Project (Ada_Quality.Reporting.Project (Session, Id));
            end;
         elsif Subcommand = "enable" then
            Ada_Quality.Storage.Set_Enabled (Store, Id_Argument (3), True);
         elsif Subcommand = "disable" then
            Ada_Quality.Storage.Set_Enabled (Store, Id_Argument (3), False);
         elsif Subcommand = "remove" then
            Ada_Quality.Storage.Remove_Project (Store, Id_Argument (3));
         else
            raise Usage_Error with "unknown project subcommand";
         end if;
         return 0;
      elsif Command = "assessment" then
         if Subcommand /= "show" then
            raise Usage_Error with "assessment requires show RUN_ID";
         end if;
         declare
            Session : Ada_Quality.Reporting.Session;
            Value   : Assessment;
            Run_Id  : constant Positive := Assessment_Id_Argument (3);
            JSON_Flag : constant Boolean :=
              (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--json");
            Requested_Format : constant String := Option ("--format", "");
            Format  : constant String :=
              (if JSON_Flag then "json"
               elsif Requested_Format'Length > 0 then Requested_Format else "text");
         begin
            if JSON_Flag and then Requested_Format'Length > 0 and then Requested_Format /= "json" then
               raise Usage_Error with "--json conflicts with non-JSON --format";
            elsif Format not in "text" | "json" | "sarif" | "junit" then
               raise Usage_Error with "assessment format requires text, json, sarif, or junit";
            end if;
            if Format /= "text" then
               Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
            end if;
            Ada_Quality.Reporting.Open (Session, DB_Path);
            Value := Stored_Assessment (Session, Run_Id);
            if Format = "json" then
               Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render (Value, Pretty => True));
            elsif Format = "sarif" then
               Ada.Text_IO.Put_Line (Ada_Quality.CI_Formats.Render_SARIF (Value, Pretty => True));
            elsif Format = "junit" then
               Ada.Text_IO.Put (Ada_Quality.CI_Formats.Render_JUnit (Value));
            else
               Print_Assessment (Value);
            end if;
         end;
         return 0;
      elsif Command = "check" then
         return Run_Check (Store, Policy_Path);
      elsif Command = "history" or else Command = "status" then
         declare
            Session : Ada_Quality.Reporting.Session;
         begin
            Ada_Quality.Reporting.Open (Session, DB_Path);
            for H of Ada_Quality.Reporting.Runs (Session) loop
               Ada.Text_IO.Put_Line
                 (Positive'Image (H.Id) & " project" & Positive'Image (H.Project_Id) & " " &
                  (case H.State is
                     when Assessment_Running => "running",
                     when Assessment_Completed => "completed",
                     when Assessment_Invalid => "invalid",
                     when Assessment_Interrupted => "interrupted"));
            end loop;
         end;
         return 0;
      elsif Command = "findings" then
         Print_Findings (DB_Path);
         return 0;
      elsif Command = "regressions" then
         declare
            Projects_Seen : Natural := 0;
            Session : Ada_Quality.Reporting.Session;
         begin
            Ada_Quality.Reporting.Open (Session, DB_Path);
            if Option ("--current", "") /= "" then
               declare
                  Current_Id : constant Positive := Positive_Option ("--current", "assessment");
                  Selected   : Ada_Quality.Reporting.Run_Record;
                  Found      : Boolean := False;
               begin
                  for Run of Ada_Quality.Reporting.Runs (Session) loop
                     if Run.Id = Current_Id then
                        Selected := Run;
                        Found := True;
                     end if;
                  end loop;
                  if not Found then
                     raise Ada_Quality.Reporting.Reporting_Error with
                       "assessment not found:" & Positive'Image (Current_Id);
                  elsif Option ("--project", "") /= "" and then
                    Positive_Option ("--project", "project") /= Selected.Project_Id
                  then
                     raise Usage_Error with "--current assessment does not belong to --project";
                  end if;
                  Print_Comparison
                    (Ada_Quality.Reporting.Compare_Project
                       (Session, Selected.Project_Id, Current_Id));
                  Projects_Seen := 1;
               end;
            elsif Option ("--project", "") /= "" then
               declare
                  Project_Id : constant Positive := Positive_Option ("--project", "project");
                  Project    : constant Ada_Quality.Reporting.Project_Record :=
                    Ada_Quality.Reporting.Project (Session, Project_Id);
                  pragma Unreferenced (Project);
               begin
                  Print_Comparison (Ada_Quality.Reporting.Compare_Project (Session, Project_Id));
                  Projects_Seen := 1;
               end;
            else
               for P of Ada_Quality.Reporting.Projects (Session) loop
                  Projects_Seen := Projects_Seen + 1;
                  Print_Comparison (Ada_Quality.Reporting.Compare_Project (Session, P.Id));
               end loop;
            end if;
            if Projects_Seen = 0 then
               Ada.Text_IO.Put_Line ("comparison unavailable: no projects are registered");
            end if;
         end;
         return 0;
      elsif Command = "trend" then
         declare
            Session    : Ada_Quality.Reporting.Session;
            Project_Id : constant Positive := Positive_Option ("--project", "project");
            Indicator  : Indicator_Id;
            JSON_Mode  : constant Boolean :=
              (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--json");
         begin
            if not Ada_Quality.Indicators.Parse_Canonical (Option ("--indicator", ""), Indicator) then
               raise Usage_Error with "--indicator requires a canonical indicator ID";
            end if;
            Ada_Quality.Reporting.Open (Session, DB_Path);
            declare
               Project : constant Ada_Quality.Reporting.Project_Record :=
                 Ada_Quality.Reporting.Project (Session, Project_Id);
               pragma Unreferenced (Project);
               Points : constant Ada_Quality.History.Trend_Vectors.Vector :=
                 Ada_Quality.History.Metric_Trend
                   (Ada_Quality.Reporting.History_Items (Session, Project_Id),
                    Ada_Quality.Reporting.All_Measurements (Session, Project_Id), Indicator);
               Unit_Name : constant String := Ada_Quality.Indicators.Measurement_Unit (Indicator);
            begin
               if JSON_Mode then
                  Ada.Text_IO.Put_Line
                    (Ada_Quality.JSON.Render_Trend
                       (Project_Id, Indicator, Unit_Name, Points, Pretty => True));
               elsif Points.Is_Empty then
                  Ada.Text_IO.Put_Line
                    ("project" & Positive'Image (Project_Id) & " " & Image (Indicator) &
                     ": no compatible numeric trend");
               else
                  for Point of Points loop
                     Ada.Text_IO.Put_Line
                       ("run" & Positive'Image (Point.Run_Id) & " " & Image (Indicator) & "=" &
                        Long_Long_Integer'Image (Point.Value) & " " & Unit_Name);
                  end loop;
               end if;
            end;
         end;
         return 0;
      elsif Command = "report" and then Option ("--format", "") = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         declare
            Session : Ada_Quality.Reporting.Session;
         begin
            Ada_Quality.Reporting.Open (Session, DB_Path);
            Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render_Archive (Session, Pretty => True));
         end;
         return 0;
      else
         raise Usage_Error with "unknown command: " & Command;
      end if;
   exception
      when E : Ada_Quality.Storage.Storage_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         return 4;
      when E : Ada_Quality.Reporting.Reporting_Error | Ada_Quality.Reporting.Schema_Error |
        Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Busy_Error |
        Ada_Quality.Reporting.Limit_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         return 4;
      when E : Usage_Error =>
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Message (E));
         return 2;
      when E : others =>  --  AQ: audited exception boundary
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, Ada.Exceptions.Exception_Information (E));
         return 3;
   end Run;
end Ada_Quality.CLI;
