with Ada.Containers.Ordered_Sets;
with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
function Run_History (DB_Path : String) return Natural is
   type History_Request is record
      Project_Id : Natural := 0;
      Status     : Ada.Strings.Unbounded.Unbounded_String;
      Since_Text : Ada.Strings.Unbounded.Unbounded_String;
      Until_Text : Ada.Strings.Unbounded.Unbounded_String;
      Since_Time : Ada_Quality.Reporting.Optional_Timestamp;
      Until_Time : Ada_Quality.Reporting.Optional_Timestamp;
      Format     : Ada.Strings.Unbounded.Unbounded_String;
      Tag_Filter : Ada.Strings.Unbounded.Unbounded_String;
      Page       : Ada_Quality.Pagination.Page_Request;
   end record;

   function Parse_Request return History_Request is
      Result : History_Request;
   begin
      if Option ("--project", "") /= "" then
         Result.Project_Id := Positive_Option ("--project", "project");
      end if;
      Result.Status := To_Unbounded_String (Option ("--status", "all"));
      Result.Since_Text := To_Unbounded_String (Option ("--since", ""));
      Result.Until_Text := To_Unbounded_String (Option ("--until", ""));
      Result.Since_Time := Timestamp_Option ("--since");
      Result.Until_Time := Timestamp_Option ("--until");
      Result.Format := To_Unbounded_String
        (Selected_Output_Format
           ("text", "text|json", "history format requires text or json"));
      Result.Tag_Filter := To_Unbounded_String (Option ("--tag", ""));
      Result.Page := Requested_Page;
      if To_String (Result.Status) not in
        "all" | "running" | "completed" | "invalid" | "interrupted"
      then
         raise Usage_Error with
           "--status requires running, completed, invalid, interrupted, or all";
      elsif Result.Since_Time.Present and then Result.Until_Time.Present and then
        Ada.Calendar.">" (Result.Since_Time.Value, Result.Until_Time.Value)
      then
         raise Usage_Error with "--since must not be later than --until";
      elsif Length (Result.Tag_Filter) > 0 and then
        not Ada_Quality.Storage.Registry.Is_Tag_Name
          (To_String (Result.Tag_Filter))
      then
         raise Usage_Error with
           "--tag requires lowercase letters, digits, hyphens, or underscores";
      end if;
      return Result;
   end Parse_Request;

   package Run_Pages is new Ada_Quality.Pagination.Stream_Pages
     (Ada_Quality.Reporting.Run_Vectors);

   Request    : constant History_Request := Parse_Request;
   Project_Id : constant Natural := Request.Project_Id;
   Status     : constant String := To_String (Request.Status);
   Since_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Request.Since_Time;
   Until_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Request.Until_Time;
   Format     : constant String := To_String (Request.Format);
   Tag_Filter : constant String := To_String (Request.Tag_Filter);
   Session    : Ada_Quality.Reporting.Session;
   Total      : Natural := 0;
   Filtered   : Ada_Quality.Reporting.Run_Vectors.Vector;
   Snapshot   : Natural := 0;
   Project_Boundary : Natural := 0;
   Project_Revision_Value : Natural := 0;
   Binding : Natural := 0;
   package Project_Id_Sets is new Ada.Containers.Ordered_Sets (Positive);
   Tagged_Projects : Project_Id_Sets.Set;
   procedure Prepare_Query is
   begin
      Ada_Quality.Reporting.Open (Session, DB_Path);
      Binding := Query_Binding
        ("history|project=" & Natural'Image (Project_Id) & "|tag=" & Tag_Filter &
         "|status=" & Status & "|since=" & To_String (Request.Since_Text) &
         "|until=" & To_String (Request.Until_Text));
      Require_Query_Binding (Binding);
      Snapshot := Cursor_Snapshot (Assessment_Snapshot (Session));
      Project_Boundary := Cursor_Secondary_Snapshot (Project_Snapshot (Session));
      Project_Revision_Value := Cursor_Tertiary_Snapshot
        (Project_Revision (Session, Project_Boundary));
      if Cursor_Version in 4 | 5 then
         Require_Project_Revision (Session, Project_Boundary, Project_Revision_Value);
      end if;
      if Tag_Filter /= "" then
         for Project of Ada_Quality.Reporting.Projects (Session) loop
            if Has_Tag (To_String (Project.Tags), Tag_Filter) then
               Tagged_Projects.Include (Project.Id);
            end if;
         end loop;
      end if;
   end Prepare_Query;

   procedure Require_Project is
   begin
      if Project_Id > 0 then
         declare
            P : constant Ada_Quality.Reporting.Project_Record :=
              Ada_Quality.Reporting.Project (Session, Positive (Project_Id));
            pragma Unreferenced (P);
         begin
            null;
         end;
      end if;
   end Require_Project;

   function Include_Run (Run : Ada_Quality.Reporting.Run_Record) return Boolean is
      State : constant String :=
        (case Run.State is
            when Assessment_Running => "running",
            when Assessment_Completed => "completed",
            when Assessment_Invalid => "invalid",
            when Assessment_Interrupted => "interrupted");
   begin
      return Run.Id <= Snapshot and then
        (Status = "all" or else Status = State) and then
        (Tag_Filter = "" or else Tagged_Projects.Contains (Run.Project_Id)) and then
        In_Time_Range (Run.Started_At, Since_Time, Until_Time);
   end Include_Run;

   procedure Collect_Runs is
      procedure Consider_Run (Run : Ada_Quality.Reporting.Run_Record) is
      begin
         if Include_Run (Run) then
            Run_Pages.Consider
              (Filtered, Run, Total, Request.Page);
         end if;
      end Consider_Run;
   begin
      Ada_Quality.Reporting.Visit_Runs
        (Session, Project_Id, Descending => True,
         Process => Consider_Run'Access);
      Run_Pages.Complete
        (Filtered, Ada_Quality.Pagination.Backward);
   end Collect_Runs;

   procedure Emit_Result is
   begin
      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Emit_Document
           (Ada_Quality.JSON_Reports.Render_History
              (Filtered,
               Page_Metadata
                 (Total, Request.Page.Offset, Natural (Filtered.Length),
                  Request.Page.Limit, Snapshot, Project_Boundary,
                  Project_Revision_Value, Binding),
               Pretty => True));
      else
         declare
            Output : Ada.Strings.Unbounded.Unbounded_String;
         begin
            for Run of Filtered loop
               Append
                 (Output, Positive'Image (Run.Id) & " project" &
                  Positive'Image (Run.Project_Id) & " " &
                  (case Run.State is
                     when Assessment_Running => "running",
                     when Assessment_Completed => "completed",
                     when Assessment_Invalid => "invalid",
                     when Assessment_Interrupted => "interrupted") &
                  (if Run.Started_At.Present then
                     " " & Ada_Quality.Reporting.Image (Run.Started_At)
                   else "") & ASCII.LF);
            end loop;
            Emit_Document (To_String (Output));
         end;
      end if;
   end Emit_Result;
begin
   Prepare_Query;
   Require_Project;
   Collect_Runs;
   Emit_Result;
   return 0;
end Run_History;
