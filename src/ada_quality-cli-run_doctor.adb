with Ada_Quality.Policy;
with Ada_Quality.Storage.Registry;
with Project_Tools.Processes;

separate (Ada_Quality.CLI)
function Run_Doctor (DB_Path, Policy_Path : String) return Natural is
   Output : Ada.Strings.Unbounded.Unbounded_String;
   Items  : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
   Reports : Ada_Quality.Command_Models.Diagnostic_Report_Vectors.Vector;
   Failures : Natural := 0;
   Profile : constant String := Option ("--profile", "");
   Selected_Policy : constant String := Ada_Quality.Policy.Profile_Path (Policy_Path, Profile);
   Batch : constant Boolean := Has_Flag ("--all") or else Option ("--tag", "") /= "";
   Maximum_Failures : Natural := 0;
   Format : constant String :=
     Selected_Output_Format
       ("text", "text|json", "doctor format requires text or json");

   procedure Result (Name : String; Passed : Boolean; Detail : String) is
   begin
      Append
        (Output, (if Passed then "ok " else "error ") & Name & ": " & Detail & ASCII.LF);
      Items.Append
        (Ada_Quality.Command_Models.Diagnostic_Item'
           (Name => To_Unbounded_String (Name), Passed => Passed,
          Detail => To_Unbounded_String (Detail)));
      if not Passed then Failures := Failures + 1; end if;
   end Result;

   procedure Validate_Request is
   begin
      if Profile /= "" and then
        not Ada_Quality.Policy.Is_Profile_Name (Profile)
      then
         raise Usage_Error with
           "--profile requires letters, digits, underscores, or hyphens";
      elsif Option ("--tag", "") /= "" and then
        not Ada_Quality.Storage.Registry.Is_Tag_Name (Option ("--tag", ""))
      then
         raise Usage_Error with
           "--tag requires lowercase letters, digits, hyphens, or underscores";
      end if;
      if Option ("--project", "") /= "" then
         declare
            Ignored : constant Positive :=
              Positive_Option ("--project", "project");
         pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end if;
      if Option ("--max-failures", "") /= "" then
         begin
            Maximum_Failures := Natural'Value
              (Option ("--max-failures", ""));
         exception
            when Constraint_Error =>
               raise Usage_Error with
                 "--max-failures requires a nonnegative count";
         end;
      end if;
   end Validate_Request;

   procedure Check_Policy is
   begin
      declare
         Loaded : constant Ada_Quality.Policy.Load_Result :=
           Ada_Quality.Policy.Load (Selected_Policy);
      begin
         Result
           ("policy", Loaded.Success,
            (if Loaded.Success then
               Selected_Policy & " " &
               Ada_Quality.Policy.Fingerprint (Loaded.Value)
             else To_String (Loaded.Error)));
      end;
   end Check_Policy;

   procedure Select_Projects
     (Session  : Ada_Quality.Reporting.Session;
      Selected : in out Ada_Quality.Reporting.Project_Vectors.Vector)
   is
      Tag : constant String := Option ("--tag", "");
   begin
      if Option ("--project", "") /= "" then
         declare
            Project_Id : constant Positive := Positive_Option ("--project", "project");
         begin
            begin
               Selected.Append (Ada_Quality.Reporting.Project (Session, Project_Id));
            exception
               when Ada_Quality.Reporting.Reporting_Error =>
                  raise Usage_Error with "project not found:" & Positive'Image (Project_Id);
            end;
         end;
      elsif Has_Flag ("--all") or else Tag /= "" then
         for Project of Ada_Quality.Reporting.Projects (Session) loop
            if Tag = "" or else Has_Tag (To_String (Project.Tags), Tag) then
               Selected.Append (Project);
            end if;
         end loop;
      end if;
   end Select_Projects;

   procedure Append_Project_Report (Project : Ada_Quality.Reporting.Project_Record) is
      Checks : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Root : constant String := To_String (Project.Path);
      Passed : constant Boolean := Project_Tools.Files.File_Exists (Root & "/alire.toml");
      Project_Check : constant Ada_Quality.Command_Models.Diagnostic_Item :=
        (Name => To_Unbounded_String ("project"), Passed => Passed,
         Detail => To_Unbounded_String
           (Root & (if Length (Project.Tags) = 0 then ""
            else " tags=" & To_String (Project.Tags))));
   begin
      Checks.Append (Project_Check);
      if not Batch then
         Items.Append (Project_Check);
      end if;
      if not Passed then
         Failures := Failures + 1;
      end if;
      Reports.Append
        (Ada_Quality.Command_Models.Diagnostic_Report'
           (Project.Id, Project.Path, Checks));
      Append
        (Output, (if Passed then "ok " else "error ") &
         "project" & Positive'Image (Project.Id) & ": " & Root & ASCII.LF);
   end Append_Project_Report;

   procedure Check_Projects (Session : Ada_Quality.Reporting.Session) is
      Selected : Ada_Quality.Reporting.Project_Vectors.Vector;
   begin
      Select_Projects (Session, Selected);
      if Selected.Is_Empty then
         Reports.Append
           (Ada_Quality.Command_Models.Diagnostic_Report'
              (Project_Id => 0, Path => Null_Unbounded_String, Checks => <>));
      else
         for Project of Selected loop
            Append_Project_Report (Project);
         end loop;
      end if;
   end Check_Projects;

   procedure Check_Database_And_Projects is
      Session : Ada_Quality.Reporting.Session;
   begin
      begin
         Ada_Quality.Reporting.Open (Session, DB_Path);
         declare
            Stats : constant Ada_Quality.Reporting.Snapshot_Statistics :=
              Ada_Quality.Reporting.Statistics (Session);
         begin
            Result
              ("database", True,
               DB_Path & " schema" & Positive'Image
                 (Ada_Quality.Reporting.Supported_Schema_Version (Session)) &
                " projects" & Natural'Image (Stats.Projects) &
                " assessments" & Natural'Image (Stats.Assessments));
         end;
      exception
         when E : Ada_Quality.Reporting.Reporting_Error | Ada_Quality.Reporting.Schema_Error |
           Ada_Quality.Reporting.Integrity_Error | Ada_Quality.Reporting.Busy_Error |
           Ada_Quality.Reporting.Limit_Error =>
            Result ("database", False, Ada.Exceptions.Exception_Message (E));
      end;
      if Ada_Quality.Reporting.Is_Open (Session) then
         Check_Projects (Session);
      end if;
   end Check_Database_And_Projects;

   procedure Check_Tools is
   begin
      for Tool of Text_Vectors.Vector'
        [To_Unbounded_String ("alr"), To_Unbounded_String ("gprbuild"),
         To_Unbounded_String ("gnatdoc"), To_Unbounded_String ("gnatprove"),
         To_Unbounded_String ("git")]
      loop
         declare
            Name : constant String := To_String (Tool);
            Path : constant String :=
              Project_Tools.Processes.Locate_Command (Name);
         begin
            Result
              ("tool " & Name, Path /= "",
               (if Path = "" then "not found" else Path));
         end;
      end loop;
   end Check_Tools;

   procedure Emit_Result is
   begin
      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         if Batch then
            Emit_Document
              (Ada_Quality.JSON_Administration.Render_Doctor_Batch
                 (Reports, Global_Checks => Items,
                  Maximum_Failures => Maximum_Failures, Pretty => True));
         else
            Emit_Document
              (Ada_Quality.JSON_Administration.Render_Doctor
                 (Items, Maximum_Failures => Maximum_Failures,
                  Failure_Count => Failures, Pretty => True));
         end if;
      else
         Emit_Document (To_String (Output));
      end if;
   end Emit_Result;
begin
   Validate_Request;
   Check_Policy;
   Check_Database_And_Projects;
   Check_Tools;
   Emit_Result;
   return (if Failures > Maximum_Failures then 3 else 0);
end Run_Doctor;
