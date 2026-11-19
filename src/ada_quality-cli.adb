with Ada.Command_Line;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.Unbounded.Text_IO;
with Ada.Text_IO;
with Terminal_Styles;
with Ada_Quality.CI_Formats;
with Ada_Quality.Checks;
with Ada_Quality.History;
with Ada_Quality.History_Data;
with Ada_Quality.HTML;
with Ada_Quality.Indicators;
with Ada_Quality.JSON;
with Ada_Quality.Policy;
with Ada_Quality.Presentation;
with Ada_Quality.Project_Inventory;
with Ada_Quality.Reporting;
with Ada_Quality.Resource_Limits;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Project_Tools.Files;
with Project_Tools.Links;
with Project_Tools.Processes;

--  AQ-WAIVER: SRC-03 target=id_argument justification=command parsing and dispatch share one bounded pass
package body Ada_Quality.CLI is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.History.Comparison_Status;
   use type Ada_Quality.Indicators.Indicator_Category;
   use type Ada_Quality.Indicators.Metric_Direction;
   use type Ada.Directories.File_Kind;

   package Text_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

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

   function Has_Flag (Name : String) return Boolean is
     (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = Name);

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
              "--current" | "--baseline" | "--indicator" | "--changed-file" | "--status" |
              "--files-from" | "--category" | "--limit" | "--since" | "--until" |
              "--from-run" | "--to-run" | "--only" | "--jobs" | "--profile" |
              "--severity" | "--path" | "--git-diff" | "--output"
            then
               Skip_Value := True;
            elsif Value in "--no-color" | "--all" | "--json" | "--add" | "--fail-on-regression" |
              "--reuse-unchanged" | "--project-policy" | "--remove-missing"
            then
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
           "--current" | "--baseline" | "--indicator" | "--changed-file" | "--status" |
           "--files-from" | "--category" | "--limit" | "--since" | "--until" |
           "--from-run" | "--to-run" | "--only" | "--jobs" | "--profile" |
           "--severity" | "--path" | "--git-diff" | "--output");

      function Allowed (Name : String) return Boolean is
        (Takes_Value (Name) or else
         Name in "--no-color" | "--all" | "--json" | "--add" | "--fail-on-regression" |
           "--reuse-unchanged" | "--project-policy" | "--remove-missing");
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
      if Positional (1) = "check" and then Option ("--project", "") /= "" and then
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
      Ada.Text_IO.Put_Line
        ("  project add PATH | discover ROOT [--add] | sync ROOT [--remove-missing] | list | show ID |");
      Ada.Text_IO.Put_Line ("          relocate ID PATH | remove ID");
      Ada.Text_IO.Put_Line
        ("  check --all | --project ID [--jobs N] [--reuse-unchanged] [--profile NAME]" &
         " [--project-policy] [--json]");
      Ada.Text_IO.Put_Line
        ("  scan --project ID (--changed-file PATH ... | --files-from FILE|- | --git-diff BASE)" &
         " [--format text|json|sarif]");
      Ada.Text_IO.Put_Line
        ("  assessment show RUN_REF [--format text|json|sarif|junit|html] [--output FILE]");
      Ada.Text_IO.Put_Line ("  assessment diff BASELINE_REF CURRENT_REF [--format text|json]");
      Ada.Text_IO.Put_Line ("  assessment alias NAME RUN_ID | aliases [RUN_REF]");
      Ada.Text_IO.Put_Line
        ("  history [--project ID] [--status STATE] [--limit N] [--since TIME] [--until TIME] [--json]");
      Ada.Text_IO.Put_Line ("  status [--only unhealthy|stale|regressed] [--since TIME] [--json]");
      Ada.Text_IO.Put_Line
        ("  findings [--project ID] [--indicator ID] [--severity LEVEL] [--path TEXT]" &
         " [--format text|json|sarif]");
      Ada.Text_IO.Put_Line
        ("  regressions [--project ID] [--current RUN_REF] [--baseline RUN_REF] [--fail-on-regression]");
      Ada.Text_IO.Put_Line
        ("  trend --project ID (--indicator ID | --all) [--from-run ID] [--to-run ID]" &
         " [--since TIME] [--until TIME] [--format text|json|csv]");
      Ada.Text_IO.Put_Line ("  explain INDICATOR_ID");
      Ada.Text_IO.Put_Line ("  indicator list [--category CATEGORY] [--format text|json]");
      Ada.Text_IO.Put_Line
        ("  report --format json|html [--project ID] [--since TIME] [--until TIME] [--output FILE]");
      Ada.Text_IO.Put_Line ("  completion bash | zsh | fish");
      Ada.Text_IO.Put_Line ("  policy validate | show");
      Ada.Text_IO.Put_Line
        ("  database init | check | recover | compact | stats | backup PATH | export PATH | import PATH |" &
         " restore PATH");
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

   procedure Emit_Document (Text : String) is
   begin
      if Option ("--output", "") = "" then
         Ada.Text_IO.Put (Text);
         if Text'Length = 0 or else Text (Text'Last) /= ASCII.LF then
            Ada.Text_IO.New_Line;
         end if;
      else
         Project_Tools.Files.Write_Text_File (Option ("--output", ""), Text);
      end if;
   end Emit_Document;

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

   function Positive_Option (Name, Kind : String) return Positive;
   function Timestamp_Option (Name : String) return Ada_Quality.Reporting.Optional_Timestamp;
   function In_Time_Range
     (Value, Since_Time, Until_Time : Ada_Quality.Reporting.Optional_Timestamp) return Boolean;

   procedure Print_Findings (DB_Path : String) is separate;

   function Run_Check
     (Store : in out Ada_Quality.Storage.Store;
      Policy_Path : String) return Natural is separate;

   function Changed_Files return Text_Vectors.Vector is
      Result : Text_Vectors.Vector;

      procedure Append (Value : String) is
      begin
         if Value'Length = 0 then
            raise Usage_Error with "changed-file lists must not contain empty paths";
         elsif Result.Length >= Ada.Containers.Count_Type (Ada_Quality.Resource_Limits.Maximum_Project_Files) then
            raise Usage_Error with "changed-file list exceeds the project entry limit";
         end if;
         Result.Append (To_Unbounded_String (Value));
      end Append;

      procedure Read_List (Name : String) is
         File : Ada.Text_IO.File_Type;

         procedure Read_From (Input : in out Ada.Text_IO.File_Type) is
         begin
            while not Ada.Text_IO.End_Of_File (Input) loop
               declare
                  Line : constant Ada.Strings.Unbounded.Unbounded_String :=
                    Ada.Strings.Unbounded.Text_IO.Get_Line (Input);
               begin
                  if Length (Line) > 0 then Append (To_String (Line)); end if;
               end;
            end loop;
         end Read_From;
      begin
         if Name = "-" then
            while not Ada.Text_IO.End_Of_File loop
               declare
                  Line : constant Ada.Strings.Unbounded.Unbounded_String :=
                    Ada.Strings.Unbounded.Text_IO.Get_Line;
               begin
                  if Length (Line) > 0 then Append (To_String (Line)); end if;
               end;
            end loop;
         else
            Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Name);
            Read_From (File);
            Ada.Text_IO.Close (File);
         end if;
      exception
         when others =>
            if Ada.Text_IO.Is_Open (File) then Ada.Text_IO.Close (File); end if;
            raise;
      end Read_List;
   begin
      for J in 1 .. Ada.Command_Line.Argument_Count - 1 loop
         if Argument (J) = "--changed-file" then Append (Argument (J + 1)); end if;
      end loop;
      if Option ("--files-from", "") /= "" then
         Read_List (Option ("--files-from", ""));
      end if;
      return Result;
   exception
      when E : Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error | Ada.Text_IO.Device_Error |
        Ada.Text_IO.Data_Error | Ada.Text_IO.End_Error =>
         raise Usage_Error with "cannot read changed-file list: " & Ada.Exceptions.Exception_Message (E);
   end Changed_Files;

   function Run_Database (DB_Path, Operation : String) return Natural is
      Store : Ada_Quality.Storage.Store;

      procedure Open_Store (Create : Boolean := True) is
      begin
         Ada_Quality.Storage.Open (Store, DB_Path, Create);
      end Open_Store;
   begin
      if Operation = "" then raise Usage_Error with "database operation is required";
      elsif Operation = "init" then
         Open_Store;
         Ada_Quality.Storage.Check (Store);
         Ada.Text_IO.Put_Line ("initialized " & DB_Path);
      elsif Operation = "check" then
         Open_Store (False);
         Ada_Quality.Storage.Check (Store);
         Ada.Text_IO.Put_Line ("database integrity check passed");
      elsif Operation = "recover" then
         Open_Store (False);
         declare
            Count : Natural;
         begin
            Ada_Quality.Storage.Recover (Store, Count);
            Ada.Text_IO.Put_Line ("recovered" & Natural'Image (Count) & " assessment(s)");
         end;
      elsif Operation = "compact" then
         Open_Store (False);
         Ada_Quality.Storage.Check (Store);
         Ada_Quality.Storage.Compact (Store);
         Ada_Quality.Storage.Check (Store);
         Ada.Text_IO.Put_Line ("database compacted");
      elsif Operation = "stats" then
         declare
            Session : Ada_Quality.Reporting.Session;
         begin
            Ada_Quality.Reporting.Open (Session, DB_Path);
            declare
               Stats : constant Ada_Quality.Reporting.Snapshot_Statistics :=
                 Ada_Quality.Reporting.Statistics (Session);
            begin
               if Has_Flag ("--json") or else Option ("--format", "") = "json" then
                  Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
                  Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render_Statistics (Stats, Pretty => True));
               elsif Option ("--format", "") not in "" | "text" then
                  raise Usage_Error with "database stats format requires text or json";
               else
                  Ada.Text_IO.Put_Line ("projects" & Natural'Image (Stats.Projects));
                  Ada.Text_IO.Put_Line ("assessments" & Natural'Image (Stats.Assessments));
                  Ada.Text_IO.Put_Line ("results" & Natural'Image (Stats.Results));
                  Ada.Text_IO.Put_Line ("measurements" & Natural'Image (Stats.Measurements));
                  Ada.Text_IO.Put_Line ("findings" & Natural'Image (Stats.Findings));
                  Ada.Text_IO.Put_Line ("executions" & Natural'Image (Stats.Executions));
                  Ada.Text_IO.Put_Line ("events" & Natural'Image (Stats.Events));
                  Ada.Text_IO.Put_Line
                    ("total rows" & Natural'Image (Stats.Total_Rows) & " /" & Positive'Image (Stats.Row_Limit));
                  Ada.Text_IO.Put_Line
                    ("text bytes" & Long_Long_Integer'Image (Stats.Text_Bytes) &
                     " /" & Positive'Image (Stats.Text_Limit));
               end if;
            end;
         end;
      elsif Operation in "backup" | "export" then
         if Positional (3) = "" then
            raise Usage_Error with "database " & Operation & " requires a destination path";
         end if;
         Open_Store (False);
         Ada_Quality.Storage.Check (Store);
         if Operation = "backup" then
            Ada_Quality.Storage.Backup (Store, Positional (3));
         else
            Ada_Quality.Storage.Export (Store, Positional (3));
         end if;
         Ada.Text_IO.Put_Line (Operation & " created at " & Positional (3));
      elsif Operation = "restore" then
         if Positional (3) = "" then raise Usage_Error with "database restore requires a source path"; end if;
         Ada_Quality.Storage.Restore (Positional (3), DB_Path);
         Open_Store (False);
         Ada_Quality.Storage.Check (Store);
         Ada.Text_IO.Put_Line ("restored " & DB_Path);
      elsif Operation = "import" then
         if Positional (3) = "" then raise Usage_Error with "database import requires a source path"; end if;
         Ada_Quality.Storage.Import (Positional (3), DB_Path);
         Open_Store (False);
         Ada_Quality.Storage.Check (Store);
         Ada.Text_IO.Put_Line ("imported " & DB_Path);
      else
         raise Usage_Error with
           "database requires init, check, recover, compact, stats, backup, export, import, or restore";
      end if;
      return 0;
   end Run_Database;

   function Run_Scan (DB_Path, Policy_Path : String) return Natural is
      Files      : Text_Vectors.Vector := Changed_Files;
      Session    : Ada_Quality.Reporting.Session;
      Project_Id : Positive;
      Loaded     : constant Ada_Quality.Policy.Load_Result := Ada_Quality.Policy.Load (Policy_Path);
      JSON_Mode  : constant Boolean := Has_Flag ("--json");
      Requested  : constant String := Option ("--format", "");
      Format     : constant String :=
        (if JSON_Mode then "json" elsif Requested = "" then "text" else Requested);

      function Is_Ada_Source (Path : String) return Boolean is
        (Path'Length >= 4 and then
         Path (Path'Last - 3 .. Path'Last) in ".adb" | ".ads");
   begin
      begin
         Project_Id := Positive'Value (Option ("--project", ""));
      exception
         when Constraint_Error => raise Usage_Error with "a positive project ID is required";
      end;
      if not Loaded.Success then
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, To_String (Loaded.Error));
         return 2;
      end if;
      if JSON_Mode and then Requested not in "" | "json" then
         raise Usage_Error with "--json conflicts with non-JSON --format";
      elsif Format not in "text" | "json" | "sarif" then
         raise Usage_Error with "scan format requires text, json, or sarif";
      end if;
      Ada_Quality.Reporting.Open (Session, DB_Path);
      declare
         Project : constant Ada_Quality.Reporting.Project_Record :=
           Ada_Quality.Reporting.Project (Session, Project_Id);
         Git_Base : constant String := Option ("--git-diff", "");
      begin
         if Git_Base'Length > 0 then
            declare
               Git : constant String := Project_Tools.Processes.Locate_Command ("git");
            begin
               if Git'Length = 0 then raise Usage_Error with "git is not available"; end if;
               declare
                  Run : constant Project_Tools.Processes.Captured_Process :=
                    Project_Tools.Processes.Capture
                      ("changed files", To_String (Project.Path), Git,
                       Project_Tools.Processes.Arguments
                         ([Project_Tools.Processes.Argument ("diff"),
                           Project_Tools.Processes.Argument ("--name-only"),
                           Project_Tools.Processes.Argument ("--diff-filter=ACMR"),
                           Project_Tools.Processes.Argument (Git_Base),
                           Project_Tools.Processes.Argument ("--")]), Quiet => True);
                  Output : constant String := To_String (Run.Output);
                  Start : Positive := 1;
               begin
                  if Run.Status /= 0 then
                     raise Usage_Error with "git diff failed for base " & Git_Base;
                  end if;
                  for Index in Output'Range loop
                     if Output (Index) = ASCII.LF then
                        if Index > Start and then Is_Ada_Source (Output (Start .. Index - 1)) then
                           Files.Append (To_Unbounded_String (Output (Start .. Index - 1)));
                        end if;
                        Start := Index + 1;
                     end if;
                  end loop;
                  if Output'Length > 0 and then Start <= Output'Last and then
                    Is_Ada_Source (Output (Start .. Output'Last))
                  then
                     Files.Append (To_Unbounded_String (Output (Start .. Output'Last)));
                  end if;
               end;
            end;
         end if;
         if Files.Is_Empty then
            raise Usage_Error with
              "scan requires --changed-file, --files-from, or --git-diff";
         end if;
         declare
            Changed : Project_Tools.Files.Path_List (1 .. Natural (Files.Length));
            Next : Positive := Changed'First;
         begin
            for File of Files loop
               Changed (Next) := File;
               Next := Next + 1;
            end loop;
            declare
            Metrics : constant Ada_Quality.Checks.Source_Analysis :=
              Ada_Quality.Checks.Analyze_Changed_Sources (To_String (Project.Path), Changed, Loaded.Value);
            Violations : constant Natural :=
              Metrics.Long_Lines + Metrics.Hygiene_Errors + Metrics.Naming_Errors +
              Metrics.Oversized_Files + Metrics.Undocumented_Specs + Metrics.Broad_Handlers +
              Metrics.Complexity_Violations + Metrics.Secret_Matches + Metrics.Unsafe_Processes;
         begin
            if Format = "json" then
               Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
               Ada.Text_IO.Put_Line
                 (Ada_Quality.JSON.Render_Scan (Project_Id, Metrics, Pretty => True));
            elsif Format = "sarif" then
               Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
               Ada.Text_IO.Put_Line
                 (Ada_Quality.CI_Formats.Render_SARIF (Metrics.Findings, Pretty => True));
            else
               Ada.Text_IO.Put_Line
                 ("scanned" & Natural'Image (Metrics.File_Count) & " changed source(s)," &
                  Natural'Image (Violations) & " violation(s)");
               for Finding of Metrics.Findings loop
                  Ada.Text_IO.Put_Line
                    (Image (Finding.Indicator) & " " & To_String (Finding.Rule) & " " &
                     To_String (Finding.Relative_Path) &
                     (if Finding.Line = 0 then "" else ":" & Natural'Image (Finding.Line)) &
                     ": " & To_String (Finding.Message));
               end loop;
            end if;
            return (if Violations = 0 then 0 else 1);
            end;
         end;
      end;
   exception
      when E : Constraint_Error =>
         raise Usage_Error with "invalid changed source: " & Ada.Exceptions.Exception_Message (E);
   end Run_Scan;

   function Run_Explain (Name : String) return Natural is
      Indicator : Indicator_Id;
   begin
      if not Ada_Quality.Indicators.Parse_Canonical (Name, Indicator) then
         raise Usage_Error with "explain requires a canonical indicator ID";
      end if;
      declare
         Registry   : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
         Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Registry (Indicator);
         Has_Prerequisite : Boolean := False;
      begin
         Ada.Text_IO.Put_Line (Image (Indicator) & " - " & Descriptor.Name.all);
         Ada.Text_IO.Put_Line
           ("category: " & Ada_Quality.Indicators.Indicator_Category'Image (Descriptor.Category));
         Ada.Text_IO.Put_Line
           ("version:" & Positive'Image (Descriptor.Version) & ", measurement version:" &
            Positive'Image (Descriptor.Measurement_Version));
         Ada.Text_IO.Put_Line
           ("unit: " & Descriptor.Unit_Name.all & ", gate: " & Boolean'Image (Descriptor.Gate) &
            ", trend: " & Ada_Quality.Indicators.Metric_Direction'Image (Descriptor.Trend));
         Ada.Text_IO.Put ("prerequisites:");
         for Dependency in Indicator_Id loop
            if Descriptor.Prerequisites (Dependency) then
               Ada.Text_IO.Put (" " & Image (Dependency));
               Has_Prerequisite := True;
            end if;
         end loop;
         if not Has_Prerequisite then Ada.Text_IO.Put (" none"); end if;
         Ada.Text_IO.New_Line;
         Ada.Text_IO.Put_Line ("remediation: " & Ada_Quality.Indicators.Remediation (Indicator));
      end;
      return 0;
   end Run_Explain;

   function Run_Status (DB_Path : String) return Natural is
      Session   : Ada_Quality.Reporting.Session;
      JSON_Flag : constant Boolean := Has_Flag ("--json");
      Requested : constant String := Option ("--format", "");
      Format    : constant String :=
        (if JSON_Flag then "json" elsif Requested = "" then "text" else Requested);
      Filter    : constant String := Option ("--only", "all");
      Stale_Before : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--since");
      Selected  : Ada_Quality.Reporting.Project_Vectors.Vector;
      use type Ada.Calendar.Time;

      function Is_Unhealthy
        (Runs : Ada_Quality.Reporting.Run_Vectors.Vector) return Boolean is
      begin
         if Runs.Is_Empty or else Runs.Last_Element.State /= Assessment_Completed then
            return True;
         end if;
         declare
            Value : constant Ada_Quality.Reporting.Assessment_Record :=
              Ada_Quality.Reporting.Read_Assessment (Session, Runs.Last_Element.Id);
         begin
            for Result of Value.Results loop
               if Result.Compliance = Violation or else
                 Result.Execution in Blocked | Failed | Errored
               then
                  return True;
               end if;
            end loop;
         end;
         return False;
      end Is_Unhealthy;
   begin
      if JSON_Flag and then Requested not in "" | "json" then
         raise Usage_Error with "--json conflicts with non-JSON --format";
      elsif Format not in "text" | "json" then
         raise Usage_Error with "status format requires text or json";
      elsif Filter not in "all" | "unhealthy" | "stale" | "regressed" then
         raise Usage_Error with "--only requires unhealthy, stale, or regressed";
      elsif Filter = "stale" and then not Stale_Before.Present then
         raise Usage_Error with "status --only stale requires --since TIME";
      end if;
      Ada_Quality.Reporting.Open (Session, DB_Path);
      for Project of Ada_Quality.Reporting.Projects (Session) loop
         declare
            Runs : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
              Ada_Quality.Reporting.Runs (Session, Project.Id);
            Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
              Ada_Quality.Reporting.Compare_Project (Session, Project.Id);
            Include : constant Boolean :=
              Filter = "all" or else
              (Filter = "unhealthy" and then Is_Unhealthy (Runs)) or else
              (Filter = "regressed" and then not Comparison.Changes.Is_Empty) or else
              (Filter = "stale" and then
               (Runs.Is_Empty or else
                not Runs.Last_Element.Started_At.Present or else
                Runs.Last_Element.Started_At.Value < Stale_Before.Value));
         begin
            if Include then Selected.Append (Project); end if;
         end;
      end loop;
      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Ada.Text_IO.Put_Line
           (Ada_Quality.JSON.Render_Status (Session, Selected, Pretty => True));
      else
         for Project of Selected loop
            declare
               Runs       : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
                 Ada_Quality.Reporting.Runs (Session, Project.Id);
               Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
                 Ada_Quality.Reporting.Compare_Project (Session, Project.Id);
               Prefix     : constant String :=
                 "project" & Positive'Image (Project.Id) & " " &
                 (if Project.Enabled then "enabled" else "disabled") & " " & To_String (Project.Path);
            begin
               if Runs.Is_Empty then
                  Ada.Text_IO.Put_Line (Prefix & ": never assessed");
               else
                  declare
                     Run : constant Ada_Quality.Reporting.Run_Record := Runs.Last_Element;
                     State : constant String :=
                       (case Run.State is
                           when Assessment_Running => "running",
                           when Assessment_Completed => "completed",
                           when Assessment_Invalid => "invalid",
                           when Assessment_Interrupted => "interrupted");
                  begin
                     Ada.Text_IO.Put_Line
                       (Prefix & ": run" & Positive'Image (Run.Id) & " " & State & ", " &
                        (if Comparison.Selection.Status = Ada_Quality.History.Comparison_Available then
                           Natural'Image (Natural (Comparison.Changes.Length)) & " regression(s)"
                         else "comparison " & Ada_Quality.History.Image (Comparison.Selection.Status)));
                  end;
               end if;
            end;
         end loop;
      end if;
      return 0;
   end Run_Status;

   function Run_Indicator_List return Natural is
      Filtered  : constant Boolean := Option ("--category", "") /= "";
      Category  : Ada_Quality.Indicators.Indicator_Category := Ada_Quality.Indicators.Structure;
      JSON_Flag : constant Boolean := Has_Flag ("--json");
      Requested : constant String := Option ("--format", "");
      Format    : constant String :=
        (if JSON_Flag then "json" elsif Requested = "" then "text" else Requested);
      Registry  : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
   begin
      if Filtered then
         begin
            Category := Ada_Quality.Indicators.Indicator_Category'Value (Option ("--category", ""));
         exception
            when Constraint_Error =>
               raise Usage_Error with
                 "--category requires structure, build, test, source, documentation, dependency," &
                 " security, release, or proof";
         end;
      end if;
      if JSON_Flag and then Requested not in "" | "json" then
         raise Usage_Error with "--json conflicts with non-JSON --format";
      elsif Format not in "text" | "json" then
         raise Usage_Error with "indicator list format requires text or json";
      elsif Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Ada.Text_IO.Put_Line
           (Ada_Quality.JSON.Render_Indicators (Filtered, Category, Pretty => True));
      else
         for Id in Indicator_Id loop
            declare
               Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Registry (Id);
            begin
               if not Filtered or else Descriptor.Category = Category then
                  Ada.Text_IO.Put_Line
                    (Image (Id) & " " &
                     Ada_Quality.Indicators.Indicator_Category'Image (Descriptor.Category) & " " &
                     Descriptor.Name.all);
               end if;
            end;
         end loop;
      end if;
      return 0;
   end Run_Indicator_List;

   function Run_Project_Discover
     (Store : in out Ada_Quality.Storage.Store;
      Root : String;
      Add, Remove_Missing : Boolean) return Natural
   is
      Found : Text_Vectors.Vector;
      Seen_Entries : Natural := 0;
      Results : Ada_Quality.JSON.Discovery_Vectors.Vector;
      JSON_Mode : constant Boolean := Has_Flag ("--json") or else Option ("--format", "") = "json";

      function Less
        (Left, Right : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
        (To_String (Left) < To_String (Right));
      package Sorting is new Text_Vectors.Generic_Sorting ("<" => Less);

      procedure Walk (Directory : String; Depth : Positive) is
         Search : Ada.Directories.Search_Type;
         Item   : Ada.Directories.Directory_Entry_Type;
         Opened : Boolean := False;
      begin
         if Depth > Ada_Quality.Resource_Limits.Maximum_Tree_Depth then
            raise Usage_Error with "project discovery exceeds the directory-depth limit";
         end if;
         if Ada.Directories.Exists (Directory & "/alire.toml") and then
           Ada.Directories.Kind (Directory & "/alire.toml") = Ada.Directories.Ordinary_File
         then
            Found.Append (To_Unbounded_String (Ada.Directories.Full_Name (Directory)));
         end if;
         Ada.Directories.Start_Search (Search, Directory, "");
         Opened := True;
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            declare
               Name : constant String := Ada.Directories.Simple_Name (Item);
               Path : constant String := Ada.Directories.Full_Name (Item);
            begin
               if Name not in "." | ".." then
                  if Seen_Entries = Ada_Quality.Resource_Limits.Maximum_Project_Files then
                     raise Usage_Error with "project discovery exceeds the entry limit";
                  end if;
                  Seen_Entries := Seen_Entries + 1;
                  if not Project_Tools.Links.Is_Link (Path) and then
                    Ada.Directories.Kind (Item) = Ada.Directories.Directory and then
                    not Ada_Quality.Project_Inventory.Is_Excluded_Source_Directory (Name)
                  then
                     Walk (Path, Depth + 1);
                  end if;
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         Opened := False;
      exception
         when others =>
            if Opened then Ada.Directories.End_Search (Search); end if;
            raise;
      end Walk;

      Registered : constant Ada_Quality.Storage.Project_Vectors.Vector :=
        Ada_Quality.Storage.Projects (Store);
   begin
      if Root'Length = 0 or else not Ada.Directories.Exists (Root) or else
        Ada.Directories.Kind (Root) /= Ada.Directories.Directory or else Project_Tools.Links.Is_Link (Root)
      then
         raise Usage_Error with "project discover requires an existing nonsymlink directory";
      end if;
      Walk (Ada.Directories.Full_Name (Root), 1);
      Sorting.Sort (Found);
      for Path of Found loop
         declare
            Name : constant String := To_String (Path);
            Existing : Natural := 0;
         begin
            for Project of Registered loop
               if To_String (Project.Path) = Name and then not Project.Removed then
                  Existing := Project.Id;
               end if;
            end loop;
            if Existing > 0 then
               Results.Append
                 (Ada_Quality.JSON.Discovery_Item'
                    (Path => Path, Project_Id => Existing,
                     Status => Ada_Quality.JSON.Already_Registered));
            elsif Add then
               declare
                  Id : constant Positive := Ada_Quality.Storage.Add_Project (Store, Name);
               begin
                  Results.Append
                    (Ada_Quality.JSON.Discovery_Item'
                       (Path => Path, Project_Id => Id, Status => Ada_Quality.JSON.Added));
               end;
            else
               Results.Append
                 (Ada_Quality.JSON.Discovery_Item'
                    (Path => Path, Project_Id => 0, Status => Ada_Quality.JSON.Discovered));
            end if;
         end;
      end loop;
      declare
         Canonical_Root : constant String := Ada.Directories.Full_Name (Root);
      begin
         for Project of Registered loop
            declare
               Name : constant String := To_String (Project.Path);
               Under_Root : constant Boolean :=
                 Name = Canonical_Root or else
                 (Name'Length > Canonical_Root'Length and then
                  Name (Name'First .. Name'First + Canonical_Root'Length - 1) = Canonical_Root and then
                  Name (Name'First + Canonical_Root'Length) = '/');
               Present : Boolean := False;
            begin
               for Path of Found loop
                  Present := Present or else To_String (Path) = Name;
               end loop;
               if Under_Root and then not Project.Removed and then not Present then
                  if Remove_Missing then
                     Ada_Quality.Storage.Remove_Project (Store, Project.Id);
                  end if;
                  Results.Append
                    (Ada_Quality.JSON.Discovery_Item'
                       (Path => Project.Path, Project_Id => Project.Id,
                        Status => (if Remove_Missing then Ada_Quality.JSON.Removed
                                   else Ada_Quality.JSON.Missing)));
               end if;
            end;
         end loop;
      end;
      if JSON_Mode then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render_Discovery (Results, Pretty => True));
      elsif Option ("--format", "") not in "" | "text" then
         raise Usage_Error with "project discover format requires text or json";
      else
         for Item of Results loop
            Ada.Text_IO.Put_Line
              ((case Item.Status is
                  when Ada_Quality.JSON.Already_Registered =>
                    "registered" & Natural'Image (Item.Project_Id),
                  when Ada_Quality.JSON.Added => "added" & Natural'Image (Item.Project_Id),
                  when Ada_Quality.JSON.Discovered => "found",
                  when Ada_Quality.JSON.Missing => "missing" & Natural'Image (Item.Project_Id),
                  when Ada_Quality.JSON.Removed => "removed" & Natural'Image (Item.Project_Id)) &
               " " & To_String (Item.Path));
         end loop;
      end if;
      return 0;
   end Run_Project_Discover;

   function Positive_Option (Name, Kind : String) return Positive is
   begin
      return Positive'Value (Option (Name, ""));
   exception
      when Constraint_Error =>
         raise Usage_Error with "a positive " & Kind & " ID is required";
   end Positive_Option;

   function Timestamp_Option (Name : String) return Ada_Quality.Reporting.Optional_Timestamp is
      Text : constant String := Option (Name, "");

      function Number_At (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then raise Constraint_Error; end if;
            Result := Result * 10 + Character'Pos (Text (Index)) - Character'Pos ('0');
         end loop;
         return Result;
      end Number_At;
   begin
      if Text'Length = 0 then return (Present => False); end if;
      if Text'Length /= 20 or else Text (Text'First + 4) /= '-' or else
        Text (Text'First + 7) /= '-' or else Text (Text'First + 10) /= 'T' or else
        Text (Text'First + 13) /= ':' or else Text (Text'First + 16) /= ':' or else
        Text (Text'Last) /= 'Z'
      then
         raise Constraint_Error;
      end if;
      declare
         First : constant Positive := Text'First;
      begin
         return
           (Present => True,
            Value => Ada.Calendar.Formatting.Time_Of
              (Year => Ada.Calendar.Year_Number (Number_At (First, First + 3)),
               Month => Ada.Calendar.Month_Number (Number_At (First + 5, First + 6)),
               Day => Ada.Calendar.Day_Number (Number_At (First + 8, First + 9)),
               Hour => Ada.Calendar.Formatting.Hour_Number (Number_At (First + 11, First + 12)),
               Minute => Ada.Calendar.Formatting.Minute_Number (Number_At (First + 14, First + 15)),
               Second => Ada.Calendar.Formatting.Second_Number (Number_At (First + 17, First + 18)),
               Time_Zone => 0));
      end;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         raise Usage_Error with Name & " requires YYYY-MM-DDTHH:MM:SSZ";
   end Timestamp_Option;

   function In_Time_Range
     (Value, Since_Time, Until_Time : Ada_Quality.Reporting.Optional_Timestamp) return Boolean
   is
      use type Ada.Calendar.Time;
   begin
      if not Since_Time.Present and then not Until_Time.Present then return True; end if;
      return Value.Present and then
        (not Since_Time.Present or else Value.Value >= Since_Time.Value) and then
        (not Until_Time.Present or else Value.Value <= Until_Time.Value);
   end In_Time_Range;

   function Run_History (DB_Path : String) return Natural is
      Session    : Ada_Quality.Reporting.Session;
      Project_Id : Natural := 0;
      Status     : constant String := Option ("--status", "all");
      Limit      : Natural := 0;
      Since_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--since");
      Until_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--until");
      JSON_Mode  : constant Boolean := Has_Flag ("--json");
      Format     : constant String :=
        (if JSON_Mode then "json" elsif Option ("--format", "") = "" then "text" else Option ("--format", ""));
      Filtered   : Ada_Quality.Reporting.Run_Vectors.Vector;
      use type Ada.Calendar.Time;
   begin
      if Option ("--project", "") /= "" then
         Project_Id := Positive_Option ("--project", "project");
      end if;
      if Option ("--limit", "") /= "" then
         begin
            Limit := Positive'Value (Option ("--limit", ""));
         exception
            when Constraint_Error => raise Usage_Error with "--limit requires a positive count";
         end;
      end if;
      if Status not in "all" | "running" | "completed" | "invalid" | "interrupted" then
         raise Usage_Error with "--status requires running, completed, invalid, interrupted, or all";
      elsif JSON_Mode and then Option ("--format", "") not in "" | "json" then
         raise Usage_Error with "--json conflicts with non-JSON --format";
      elsif Format not in "text" | "json" then
         raise Usage_Error with "history format requires text or json";
      elsif Since_Time.Present and then Until_Time.Present and then Since_Time.Value > Until_Time.Value then
         raise Usage_Error with "--since must not be later than --until";
      end if;

      Ada_Quality.Reporting.Open (Session, DB_Path);
      if Project_Id > 0 then
         declare
            P : constant Ada_Quality.Reporting.Project_Record :=
              Ada_Quality.Reporting.Project (Session, Positive (Project_Id));
            pragma Unreferenced (P);
         begin null; end;
      end if;
      for Run of Ada_Quality.Reporting.Runs (Session, Project_Id) loop
         declare
            State : constant String :=
              (case Run.State is
                  when Assessment_Running => "running",
                  when Assessment_Completed => "completed",
                  when Assessment_Invalid => "invalid",
                  when Assessment_Interrupted => "interrupted");
         begin
            if (Status = "all" or else Status = State) and then
              In_Time_Range (Run.Started_At, Since_Time, Until_Time)
            then
               Filtered.Append (Run);
            end if;
         end;
      end loop;
      if Limit > 0 and then Filtered.Length > Ada.Containers.Count_Type (Limit) then
         Filtered.Delete_First (Filtered.Length - Ada.Containers.Count_Type (Limit));
      end if;
      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render_History (Filtered, Pretty => True));
      else
         for Run of Filtered loop
            Ada.Text_IO.Put_Line
              (Positive'Image (Run.Id) & " project" & Positive'Image (Run.Project_Id) & " " &
               (case Run.State is
                  when Assessment_Running => "running",
                  when Assessment_Completed => "completed",
                  when Assessment_Invalid => "invalid",
                  when Assessment_Interrupted => "interrupted") &
               (if Run.Started_At.Present then " " & Ada_Quality.Reporting.Image (Run.Started_At) else ""));
         end loop;
      end if;
      return 0;
   end Run_History;

   function Run_Trend (DB_Path : String) return Natural is
      Session      : Ada_Quality.Reporting.Session;
      Project_Id   : constant Positive := Positive_Option ("--project", "project");
      All_Metrics  : constant Boolean := Has_Flag ("--all");
      JSON_Mode    : constant Boolean := Has_Flag ("--json");
      Format       : constant String :=
        (if JSON_Mode then "json" elsif Option ("--format", "") = "" then "text" else Option ("--format", ""));
      From_Run     : Natural := 0;
      To_Run       : Natural := 0;
      Since_Time   : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--since");
      Until_Time   : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--until");
      Series       : Ada_Quality.JSON.Metric_Series_Vectors.Vector;
      Runs         : Ada_Quality.Reporting.Run_Vectors.Vector;
      Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      use type Ada.Calendar.Time;

      function Include_Point (Point : Ada_Quality.History.Trend_Point) return Boolean is
      begin
         if (From_Run > 0 and then Point.Run_Id < From_Run) or else
           (To_Run > 0 and then Point.Run_Id > To_Run)
         then
            return False;
         end if;
         for Run of Runs loop
            if Run.Id = Point.Run_Id then
               return In_Time_Range (Run.Finished_At, Since_Time, Until_Time);
            end if;
         end loop;
         return False;
      end Include_Point;

      procedure Add_Series (Indicator : Indicator_Id) is
         All_Points : constant Ada_Quality.History.Trend_Vectors.Vector :=
           Ada_Quality.History.Metric_Trend
             (Ada_Quality.Reporting.History_Items (Session, Project_Id), Measurements, Indicator);
         Points : Ada_Quality.History.Trend_Vectors.Vector;
      begin
         for Point of All_Points loop
            if Include_Point (Point) then Points.Append (Point); end if;
         end loop;
         Series.Append
           (Ada_Quality.JSON.Metric_Series'
              (Indicator => Indicator,
               Unit_Name => To_Unbounded_String (Ada_Quality.Indicators.Measurement_Unit (Indicator)),
               Points => Points));
      end Add_Series;
   begin
      if All_Metrics = (Option ("--indicator", "") /= "") then
         raise Usage_Error with "trend requires exactly one of --indicator ID or --all";
      elsif JSON_Mode and then Option ("--format", "") not in "" | "json" then
         raise Usage_Error with "--json conflicts with non-JSON --format";
      elsif Format not in "text" | "json" | "csv" then
         raise Usage_Error with "trend format requires text, json, or csv";
      elsif Since_Time.Present and then Until_Time.Present and then Since_Time.Value > Until_Time.Value then
         raise Usage_Error with "--since must not be later than --until";
      end if;

      Ada_Quality.Reporting.Open (Session, DB_Path);
      if Option ("--from-run", "") /= "" then
         From_Run := Ada_Quality.Reporting.Resolve_Assessment
           (Session, Option ("--from-run", ""));
      end if;
      if Option ("--to-run", "") /= "" then
         To_Run := Ada_Quality.Reporting.Resolve_Assessment
           (Session, Option ("--to-run", ""));
      end if;
      if From_Run > 0 and then To_Run > 0 and then From_Run > To_Run then
         raise Usage_Error with "--from-run must not exceed --to-run";
      end if;
      declare
         P : constant Ada_Quality.Reporting.Project_Record := Ada_Quality.Reporting.Project (Session, Project_Id);
         pragma Unreferenced (P);
      begin null; end;
      Runs := Ada_Quality.Reporting.Runs (Session, Project_Id);
      Measurements := Ada_Quality.Reporting.All_Measurements (Session, Project_Id);
      if All_Metrics then
         for Indicator in Indicator_Id loop
            if Ada_Quality.Indicators.Direction_Of (Indicator) /= Ada_Quality.Indicators.No_Trend then
               Add_Series (Indicator);
            end if;
         end loop;
      else
         declare
            Indicator : Indicator_Id;
         begin
            if not Ada_Quality.Indicators.Parse_Canonical (Option ("--indicator", ""), Indicator) then
               raise Usage_Error with "--indicator requires a canonical indicator ID";
            end if;
            Add_Series (Indicator);
         end;
      end if;

      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         if All_Metrics then
            Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render_Trends (Project_Id, Series, Pretty => True));
         else
            declare
               Series_Item : constant Ada_Quality.JSON.Metric_Series := Series.First_Element;
            begin
               Ada.Text_IO.Put_Line
                 (Ada_Quality.JSON.Render_Trend
                    (Project_Id, Series_Item.Indicator, To_String (Series_Item.Unit_Name),
                     Series_Item.Points, Pretty => True));
            end;
         end if;
      elsif Format = "csv" then
         Ada.Text_IO.Put_Line ("project_id,indicator,unit,run_id,value");
         for Series_Item of Series loop
            for Point of Series_Item.Points loop
               Ada.Text_IO.Put_Line
                 (Ada.Strings.Fixed.Trim (Positive'Image (Project_Id), Ada.Strings.Both) & "," &
                  Image (Series_Item.Indicator) & "," & To_String (Series_Item.Unit_Name) & "," &
                  Ada.Strings.Fixed.Trim (Positive'Image (Point.Run_Id), Ada.Strings.Both) & "," &
                  Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Point.Value), Ada.Strings.Both));
            end loop;
         end loop;
      else
         for Series_Item of Series loop
            if Series_Item.Points.Is_Empty then
               Ada.Text_IO.Put_Line
                 ("project" & Positive'Image (Project_Id) & " " & Image (Series_Item.Indicator) &
                  ": no compatible numeric trend");
            else
               for Point of Series_Item.Points loop
                  Ada.Text_IO.Put_Line
                    ("run" & Positive'Image (Point.Run_Id) & " " & Image (Series_Item.Indicator) & "=" &
                     Long_Long_Integer'Image (Point.Value) & " " & To_String (Series_Item.Unit_Name));
               end loop;
            end if;
         end loop;
      end if;
      return 0;
   end Run_Trend;

   function Run_Completion (Shell : String) return Natural is
      Commands : constant String :=
        "help version project check scan assessment history status findings regressions trend explain " &
        "indicator report policy database completion";
   begin
      if Shell = "bash" then
         Ada.Text_IO.Put_Line ("_ada_quality_complete() {");
         Ada.Text_IO.Put_Line ("  local cur=${COMP_WORDS[COMP_CWORD]} words");
         Ada.Text_IO.Put_Line ("  case ""${COMP_WORDS[1]}"" in");
         Ada.Text_IO.Put_Line
           ("    project) words='add discover sync list show enable disable relocate remove " &
            "--add --remove-missing --json' ;;");
         Ada.Text_IO.Put_Line
           ("    assessment) words='show diff alias aliases --format --output --json' ;;");
         Ada.Text_IO.Put_Line
           ("    database) words='init check recover compact stats backup export import restore --format --json' ;;");
         Ada.Text_IO.Put_Line
           ("    check) words='--all --project --jobs --reuse-unchanged --profile --project-policy --json' ;;");
         Ada.Text_IO.Put_Line
           ("    scan) words='--project --changed-file --files-from --git-diff --format --json' ;;");
         Ada.Text_IO.Put_Line
           ("    findings) words='--project --indicator --severity --path --since --until --format --json' ;;");
         Ada.Text_IO.Put_Line
           ("    *) words='" & Commands & " --database --policy --format --json --no-color' ;;");
         Ada.Text_IO.Put_Line ("  esac");
         Ada.Text_IO.Put_Line ("  COMPREPLY=($(compgen -W ""$words"" -- ""$cur""))");
         Ada.Text_IO.Put_Line ("}");
         Ada.Text_IO.Put_Line ("complete -F _ada_quality_complete ada-quality");
      elsif Shell = "zsh" then
         Ada.Text_IO.Put_Line ("#compdef ada-quality");
         Ada.Text_IO.Put_Line
           ("_arguments '--database[database path]:file:_files' '--policy[policy path]:file:_files' " &
            "'--format[output format]:(text json sarif junit csv html)' " &
            "'1:command:(" & Commands & ")' '*:argument:_files'");
      elsif Shell = "fish" then
         Ada.Text_IO.Put_Line
           ("complete -c ada-quality -f -n '__fish_use_subcommand' -a '" & Commands & "'");
         Ada.Text_IO.Put_Line
           ("complete -c ada-quality -l database -r -d 'Database path'; " &
            "complete -c ada-quality -l policy -r -d 'Policy path'");
         Ada.Text_IO.Put_Line
           ("complete -c ada-quality -n '__fish_seen_subcommand_from check' -l jobs -r; " &
            "complete -c ada-quality -n '__fish_seen_subcommand_from scan' -l git-diff -r");
      else
         raise Usage_Error with "completion requires bash, zsh, or fish";
      end if;
      return 0;
   end Run_Completion;

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
         return Run_Database (DB_Path, Subcommand);
      elsif Command = "completion" then
         return Run_Completion (Subcommand);
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
        (Command = "project" and then
         Subcommand in "add" | "discover" | "sync" | "enable" | "disable" | "relocate" | "remove") or else
        (Command = "assessment" and then Subcommand = "alias")
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
         elsif Subcommand = "discover" then
            return Run_Project_Discover
              (Store, Positional (3), Has_Flag ("--add"), Remove_Missing => False);
         elsif Subcommand = "sync" then
            return Run_Project_Discover
              (Store, Positional (3), Add => True,
               Remove_Missing => Has_Flag ("--remove-missing"));
         elsif Subcommand = "list" then
            declare
               Session : Ada_Quality.Reporting.Session;
            begin
               Ada_Quality.Reporting.Open (Session, DB_Path);
               declare
                  Projects : constant Ada_Quality.Reporting.Project_Vectors.Vector :=
                    Ada_Quality.Reporting.Projects (Session);
               begin
                  if Has_Flag ("--json") or else Option ("--format", "") = "json" then
                     Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
                     Ada.Text_IO.Put_Line
                       (Ada_Quality.JSON.Render_Projects (Projects, Pretty => True));
                  elsif Option ("--format", "") not in "" | "text" then
                     raise Usage_Error with "project list format requires text or json";
                  else
                     for P of Projects loop Put_Project (P); end loop;
                  end if;
               end;
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
         elsif Subcommand = "relocate" then
            if Positional (4) = "" then
               raise Usage_Error with "project relocate requires an ID and path";
            end if;
            Ada_Quality.Storage.Relocate_Project (Store, Id_Argument (3), Positional (4));
            Ada.Text_IO.Put_Line ("relocated project" & Positive'Image (Id_Argument (3)));
         elsif Subcommand = "remove" then
            Ada_Quality.Storage.Remove_Project (Store, Id_Argument (3));
         else
            raise Usage_Error with "unknown project subcommand";
         end if;
         return 0;
      elsif Command = "assessment" then
         if Subcommand = "diff" then
            declare
               Session     : Ada_Quality.Reporting.Session;
               Baseline_Id : Positive;
               Current_Id  : Positive;
               JSON_Flag   : constant Boolean := Has_Flag ("--json");
               Requested   : constant String := Option ("--format", "");
               Format      : constant String :=
                 (if JSON_Flag then "json" elsif Requested = "" then "text" else Requested);
               Comparison  : Ada_Quality.Reporting.Project_Comparison;
            begin
               if Positional (3) = "" or else Positional (4) = "" then
                  raise Usage_Error with "assessment diff requires baseline and current references";
               elsif JSON_Flag and then Requested not in "" | "json" then
                  raise Usage_Error with "--json conflicts with non-JSON --format";
               elsif Format not in "text" | "json" then
                  raise Usage_Error with "assessment diff format requires text or json";
               end if;
               Ada_Quality.Reporting.Open (Session, DB_Path);
               Baseline_Id := Ada_Quality.Reporting.Resolve_Assessment (Session, Positional (3));
               Current_Id := Ada_Quality.Reporting.Resolve_Assessment (Session, Positional (4));
               if Baseline_Id >= Current_Id then
                  raise Usage_Error with "baseline assessment must precede current assessment";
               end if;
               Comparison := Ada_Quality.Reporting.Compare_Assessments
                 (Session, Baseline_Id, Current_Id);
               if Format = "json" then
                  Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
                  Ada.Text_IO.Put_Line
                    (Ada_Quality.JSON.Render_Comparison (Comparison, Pretty => True));
               else
                  Print_Comparison (Comparison);
               end if;
            end;
         elsif Subcommand = "show" then
            declare
               Session : Ada_Quality.Reporting.Session;
               Value   : Assessment;
               Run_Id  : Positive;
               JSON_Flag : constant Boolean := Has_Flag ("--json");
               Requested_Format : constant String := Option ("--format", "");
               Format  : constant String :=
                 (if JSON_Flag then "json"
                  elsif Requested_Format'Length > 0 then Requested_Format else "text");
            begin
               if JSON_Flag and then Requested_Format'Length > 0 and then Requested_Format /= "json" then
                  raise Usage_Error with "--json conflicts with non-JSON --format";
               elsif Format not in "text" | "json" | "sarif" | "junit" | "html" then
                  raise Usage_Error with "assessment format requires text, json, sarif, junit, or html";
               end if;
               if Format /= "text" then
                  Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
               end if;
               Ada_Quality.Reporting.Open (Session, DB_Path);
               if Positional (3) = "" then
                  raise Usage_Error with "assessment show requires an assessment reference";
               end if;
               Run_Id := Ada_Quality.Reporting.Resolve_Assessment (Session, Positional (3));
               Value := Stored_Assessment (Session, Run_Id);
               if Format = "json" then
                  Emit_Document (Ada_Quality.JSON.Render (Value, Pretty => True));
               elsif Format = "sarif" then
                  Emit_Document (Ada_Quality.CI_Formats.Render_SARIF (Value, Pretty => True));
               elsif Format = "junit" then
                  Emit_Document (Ada_Quality.CI_Formats.Render_JUnit (Value));
               elsif Format = "html" then
                  Emit_Document (Ada_Quality.HTML.Render_Assessment (Value));
               else
                  Print_Assessment (Value);
               end if;
            end;
         elsif Subcommand = "alias" then
            if Positional (3) = "" or else Positional (4) = "" then
               raise Usage_Error with "assessment alias requires a name and numeric assessment ID";
            end if;
            declare
               Run_Id : Positive;
            begin
               begin
                  Run_Id := Positive'Value (Positional (4));
               exception
                  when Constraint_Error =>
                     raise Usage_Error with "assessment alias requires a numeric assessment ID";
               end;
               Ada_Quality.Storage.Add_Assessment_Alias (Store, Run_Id, Positional (3));
               Ada.Text_IO.Put_Line ("aliased " & Positional (3) & " to assessment" & Positive'Image (Run_Id));
            end;
         elsif Subcommand = "aliases" then
            declare
               Session : Ada_Quality.Reporting.Session;
               Run_Id  : Natural := 0;
            begin
               Ada_Quality.Reporting.Open (Session, DB_Path);
               if Positional (3) /= "" then
                  Run_Id := Ada_Quality.Reporting.Resolve_Assessment (Session, Positional (3));
               end if;
               declare
                  Aliases : constant Ada_Quality.Reporting.Alias_Vectors.Vector :=
                    Ada_Quality.Reporting.Aliases (Session, Run_Id);
               begin
                  if Has_Flag ("--json") or else Option ("--format", "") = "json" then
                     Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
                     Ada.Text_IO.Put_Line
                       (Ada_Quality.JSON.Render_Aliases (Aliases, Pretty => True));
                  elsif Option ("--format", "") not in "" | "text" then
                     raise Usage_Error with "assessment aliases format requires text or json";
                  else
                     for Item of Aliases loop
                        Ada.Text_IO.Put_Line
                          (To_String (Item.Name) & " assessment" & Positive'Image (Item.Run_Id));
                     end loop;
                  end if;
               end;
            end;
         else
            raise Usage_Error with "assessment requires show, diff, alias, or aliases";
         end if;
         return 0;
      elsif Command = "check" then
         return Run_Check (Store, Policy_Path);
      elsif Command = "scan" then
         return Run_Scan (DB_Path, Policy_Path);
      elsif Command = "history" then
         return Run_History (DB_Path);
      elsif Command = "status" then
         return Run_Status (DB_Path);
      elsif Command = "findings" then
         Print_Findings (DB_Path);
         return 0;
      elsif Command = "regressions" then
         declare
            Projects_Seen : Natural := 0;
            Session : Ada_Quality.Reporting.Session;
            Gate_Exit : Natural := 0;

            procedure Handle (Comparison : Ada_Quality.Reporting.Project_Comparison) is
            begin
               Print_Comparison (Comparison);
               if Comparison.Selection.Status /= Ada_Quality.History.Comparison_Available then
                  Gate_Exit := 3;
               elsif not Comparison.Changes.Is_Empty and then Gate_Exit < 3 then
                  Gate_Exit := 1;
               end if;
            end Handle;
         begin
            Ada_Quality.Reporting.Open (Session, DB_Path);
            if Option ("--baseline", "") /= "" then
               if Option ("--current", "") = "" then
                  raise Usage_Error with "--baseline requires --current";
               end if;
               declare
                  Baseline_Id : constant Positive :=
                    Ada_Quality.Reporting.Resolve_Assessment (Session, Option ("--baseline", ""));
                  Current_Id : constant Positive :=
                    Ada_Quality.Reporting.Resolve_Assessment (Session, Option ("--current", ""));
               begin
                  if Baseline_Id >= Current_Id then
                     raise Usage_Error with "baseline assessment must precede current assessment";
                  end if;
                  Handle
                    (Ada_Quality.Reporting.Compare_Assessments (Session, Baseline_Id, Current_Id));
               end;
               Projects_Seen := 1;
            elsif Option ("--current", "") /= "" then
               declare
                  Current_Id : constant Positive :=
                    Ada_Quality.Reporting.Resolve_Assessment (Session, Option ("--current", ""));
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
                  Handle
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
                  Handle (Ada_Quality.Reporting.Compare_Project (Session, Project_Id));
                  Projects_Seen := 1;
               end;
            else
               for P of Ada_Quality.Reporting.Projects (Session) loop
                  Projects_Seen := Projects_Seen + 1;
                  Handle (Ada_Quality.Reporting.Compare_Project (Session, P.Id));
               end loop;
            end if;
            if Projects_Seen = 0 then
               Ada.Text_IO.Put_Line ("comparison unavailable: no projects are registered");
               Gate_Exit := 3;
            end if;
            return (if Has_Flag ("--fail-on-regression") then Gate_Exit else 0);
         end;
      elsif Command = "trend" then
         return Run_Trend (DB_Path);
      elsif Command = "explain" then
         return Run_Explain (Subcommand);
      elsif Command = "indicator" and then Subcommand = "list" then
         return Run_Indicator_List;
      elsif Command = "report" then
         if Option ("--format", "") not in "json" | "html" then
            raise Usage_Error with "report requires --format json or html";
         end if;
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         declare
            Session : Ada_Quality.Reporting.Session;
            Project_Id : Natural := 0;
            Since_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--since");
            Until_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--until");
            use type Ada.Calendar.Time;
         begin
            if Since_Time.Present and then Until_Time.Present and then
              Since_Time.Value > Until_Time.Value
            then
               raise Usage_Error with "--since must not be later than --until";
            end if;
            if Option ("--project", "") /= "" then
               Project_Id := Positive_Option ("--project", "project");
            end if;
            Ada_Quality.Reporting.Open (Session, DB_Path);
            if Project_Id > 0 then
               declare
                  P : constant Ada_Quality.Reporting.Project_Record :=
                    Ada_Quality.Reporting.Project (Session, Positive (Project_Id));
                  pragma Unreferenced (P);
               begin null; end;
            end if;
            if Option ("--format", "") = "json" then
               Emit_Document
                 (Ada_Quality.JSON.Render_Archive
                    (Session, Pretty => True, Project_Id => Project_Id,
                     Since_Time => Since_Time, Until_Time => Until_Time));
            else
               declare
                  Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
               begin
                  for P of Ada_Quality.Reporting.Projects (Session) loop
                     if Project_Id = 0 or else P.Id = Project_Id then
                        if not Since_Time.Present and then not Until_Time.Present then
                           Projects.Append (P);
                        else
                           for Run of Ada_Quality.Reporting.Runs (Session, P.Id) loop
                              if In_Time_Range (Run.Started_At, Since_Time, Until_Time) then
                                 Projects.Append (P);
                                 exit;
                              end if;
                           end loop;
                        end if;
                     end if;
                  end loop;
                  Emit_Document (Ada_Quality.HTML.Render_Portfolio (Session, Projects));
               end;
            end if;
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
