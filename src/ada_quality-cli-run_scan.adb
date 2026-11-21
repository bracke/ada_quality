with Ada_Quality.CI_Formats;
with Ada_Quality.Checks;
with Ada_Quality.JSON_Reports;
with Ada_Quality.Policy;
with Project_Tools.Processes;

separate (Ada_Quality.CLI)
function Run_Scan (DB_Path, Policy_Path : String) return Natural is
   Files      : Text_Vectors.Vector := Changed_Files;
   Session    : Ada_Quality.Reporting.Session;
   Project_Id : Positive;
   Loaded     : constant Ada_Quality.Policy.Load_Result := Ada_Quality.Policy.Load (Policy_Path);
   Format     : constant String :=
     Selected_Output_Format
       ("text", "text|json|sarif", "scan format requires text, json, or sarif");
   Git_Base   : constant String := Option ("--git-diff", "");
   Git_Mode   : constant Boolean :=
     Git_Base'Length > 0 or else Has_Flag ("--staged") or else
     Has_Flag ("--unstaged") or else Has_Flag ("--untracked");

   function Is_Ada_Source (Path : String) return Boolean is
     (Path'Length >= 4 and then
      Path (Path'Last - 3 .. Path'Last) in ".adb" | ".ads");

   procedure Append_Git_Path (Root, Path : String) is
   begin
      if not Is_Ada_Source (Path) or else
        not Project_Tools.Files.File_Exists
          (Project_Tools.Files.Join (Root, Path))
      then
         return;
      end if;
      for Existing of Files loop
         if To_String (Existing) = Path then
            return;
         end if;
      end loop;
      Files.Append (To_Unbounded_String (Path));
   end Append_Git_Path;

   function Violation_Count
     (Metrics : Ada_Quality.Checks.Source_Analysis) return Natural is
     (Metrics.Long_Lines + Metrics.Hygiene_Errors + Metrics.Naming_Errors +
      Metrics.Oversized_Files + Metrics.Undocumented_Specs + Metrics.Broad_Handlers +
      Metrics.Complexity_Violations + Metrics.Secret_Matches + Metrics.Unsafe_Processes);

   procedure Emit (Metrics : Ada_Quality.Checks.Source_Analysis) is
      Violations : constant Natural := Violation_Count (Metrics);
      Text : Ada.Strings.Unbounded.Unbounded_String;
   begin
      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Emit_Document
           (Ada_Quality.JSON_Reports.Render_Scan
              (Project_Id, Metrics, Pretty => True));
      elsif Format = "sarif" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Emit_Document (Ada_Quality.CI_Formats.Render_SARIF (Metrics.Findings, Pretty => True));
      else
         Append
           (Text, "scanned" & Natural'Image (Metrics.File_Count) & " changed source(s)," &
            Natural'Image (Violations) & " violation(s)" & ASCII.LF);
         for Finding of Metrics.Findings loop
            Append
              (Text, Image (Finding.Indicator) & " " & To_String (Finding.Rule) & " " &
               To_String (Finding.Relative_Path) &
               (if Finding.Line = 0 then "" else ":" & Natural'Image (Finding.Line)) &
               ": " & To_String (Finding.Message) & ASCII.LF);
         end loop;
         Emit_Document (To_String (Text));
      end if;
   end Emit;

   procedure Validate_Request is
   begin
      begin
         Project_Id := Positive'Value (Option ("--project", ""));
      exception
         when Constraint_Error =>
            raise Usage_Error with "a positive project ID is required";
      end;
      if not Loaded.Success then
         raise Usage_Error with To_String (Loaded.Error);
      end if;
   end Validate_Request;

   procedure Add_Git_Files
     (Root, Label : String; Args : Project_Tools.Processes.Argument_Vectors.Vector)
   is
      Git : constant String := Project_Tools.Processes.Locate_Command ("git");
   begin
      if Git'Length = 0 then
         raise Usage_Error with "git is not available";
      end if;
      declare
         Run : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture (Label, Root, Git, Args, Quiet => True);
         Output : constant String := To_String (Run.Output);
         Start : Positive := 1;
      begin
         if Run.Status /= 0 then
            raise Usage_Error with Label & " failed";
         end if;
         for Index in Output'Range loop
            if Output (Index) = ASCII.LF then
               if Index > Start then
                  Append_Git_Path (Root, Output (Start .. Index - 1));
               end if;
               Start := Index + 1;
            end if;
         end loop;
         if Output'Length > 0 and then Start <= Output'Last then
            Append_Git_Path (Root, Output (Start .. Output'Last));
         end if;
      end;
   end Add_Git_Files;

   procedure Collect_Git_Files (Root : String) is
   begin
      if Git_Base'Length > 0 then
         Add_Git_Files
           (Root, "git diff " & Git_Base,
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("diff"),
                Project_Tools.Processes.Argument ("--name-only"),
                Project_Tools.Processes.Argument ("--diff-filter=ACMR"),
                Project_Tools.Processes.Argument (Git_Base),
                Project_Tools.Processes.Argument ("--")]));
      end if;
      if Has_Flag ("--staged") then
         Add_Git_Files
           (Root, "git staged diff",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("diff"),
                Project_Tools.Processes.Argument ("--cached"),
                Project_Tools.Processes.Argument ("--name-only"),
                Project_Tools.Processes.Argument ("--diff-filter=ACMR"),
                Project_Tools.Processes.Argument ("--")]));
      end if;
      if Has_Flag ("--unstaged") then
         Add_Git_Files
           (Root, "git unstaged diff",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("diff"),
                Project_Tools.Processes.Argument ("--name-only"),
                Project_Tools.Processes.Argument ("--diff-filter=ACMR"),
                Project_Tools.Processes.Argument ("--")]));
      end if;
      if Has_Flag ("--untracked") then
         Add_Git_Files
           (Root, "git untracked files",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("ls-files"),
                Project_Tools.Processes.Argument ("--others"),
                Project_Tools.Processes.Argument ("--exclude-standard")]));
      end if;
   end Collect_Git_Files;

   function Analyze (Root : String) return Natural is
   begin
      Collect_Git_Files (Root);
      if Files.Is_Empty then
         if not Git_Mode then
            raise Usage_Error with
              "scan requires --changed-file, --files-from, --git-diff, --staged, --unstaged, or --untracked";
         end if;
         Emit ((others => <>));
         return 0;
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
              Ada_Quality.Checks.Analyze_Changed_Sources (Root, Changed, Loaded.Value);
         begin
            Emit (Metrics);
            return (if Violation_Count (Metrics) = 0 then 0 else 1);
         end;
      end;
   end Analyze;
begin
   Validate_Request;
   Ada_Quality.Reporting.Open (Session, DB_Path);
   return Analyze
     (To_String (Ada_Quality.Reporting.Project (Session, Project_Id).Path));
exception
   when E : Constraint_Error =>
      raise Usage_Error with "invalid changed source: " & Ada.Exceptions.Exception_Message (E);
end Run_Scan;
