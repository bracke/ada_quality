with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
function Run_Status (DB_Path : String) return Natural is
   type Status_Request is record
      Format       : Ada.Strings.Unbounded.Unbounded_String;
      Filter       : Ada.Strings.Unbounded.Unbounded_String;
      Since_Text   : Ada.Strings.Unbounded.Unbounded_String;
      Stale_Before : Ada_Quality.Reporting.Optional_Timestamp;
      Tag_Filter   : Ada.Strings.Unbounded.Unbounded_String;
      Page         : Ada_Quality.Pagination.Page_Request;
   end record;

   function Parse_Request return Status_Request is
      Result : Status_Request;
   begin
      Result.Format := To_Unbounded_String
        (Selected_Output_Format
           ("text", "text|json", "status format requires text or json"));
      Result.Filter := To_Unbounded_String (Option ("--only", "all"));
      Result.Since_Text := To_Unbounded_String (Option ("--since", ""));
      Result.Stale_Before := Timestamp_Option ("--since");
      Result.Tag_Filter := To_Unbounded_String (Option ("--tag", ""));
      Result.Page := Requested_Page;
      if To_String (Result.Filter) not in
        "all" | "unhealthy" | "stale" | "regressed"
      then
         raise Usage_Error with "--only requires unhealthy, stale, or regressed";
      elsif Length (Result.Tag_Filter) > 0 and then
        not Ada_Quality.Storage.Registry.Is_Tag_Name
          (To_String (Result.Tag_Filter))
      then
         raise Usage_Error with
           "--tag requires lowercase letters, digits, hyphens, or underscores";
      elsif To_String (Result.Filter) = "stale" and then
        not Result.Stale_Before.Present
      then
         raise Usage_Error with "status --only stale requires --since TIME";
      end if;
      return Result;
   end Parse_Request;

   package Project_Pages is new Ada_Quality.Pagination.Stream_Pages
     (Ada_Quality.Reporting.Project_Vectors);

   Request      : constant Status_Request := Parse_Request;
   Format       : constant String := To_String (Request.Format);
   Filter       : constant String := To_String (Request.Filter);
   Stale_Before : constant Ada_Quality.Reporting.Optional_Timestamp :=
     Request.Stale_Before;
   Tag_Filter   : constant String := To_String (Request.Tag_Filter);
   Session      : Ada_Quality.Reporting.Session;
   Selected     : Ada_Quality.Reporting.Project_Vectors.Vector;
   Total : Natural := 0;
   Snapshot : Natural := 0;
   Project_Boundary : Natural := 0;
   Project_Revision_Value : Natural := 0;
   Binding : constant Natural := Query_Binding
     ("status|only=" & Filter & "|since=" & To_String (Request.Since_Text) &
      "|tag=" & Tag_Filter);
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

   function Snapshot_Runs
     (Project_Id : Positive) return Ada_Quality.Reporting.Run_Vectors.Vector
   is
      Result : Ada_Quality.Reporting.Run_Vectors.Vector :=
        Ada_Quality.Reporting.Runs (Session, Project_Id);
   begin
      while not Result.Is_Empty and then Result.Last_Element.Id > Snapshot loop
         Result.Delete_Last;
      end loop;
      return Result;
   end Snapshot_Runs;

   procedure Prepare_Query is
   begin
      Ada_Quality.Reporting.Open (Session, DB_Path);
      Require_Query_Binding (Binding);
      Snapshot := Cursor_Snapshot (Assessment_Snapshot (Session));
      Project_Boundary := Cursor_Secondary_Snapshot (Project_Snapshot (Session));
      Project_Revision_Value := Cursor_Tertiary_Snapshot
        (Project_Revision (Session, Project_Boundary));
      if Cursor_Version in 4 | 5 then
         Require_Project_Revision
           (Session, Project_Boundary, Project_Revision_Value);
      end if;
   end Prepare_Query;

   procedure Collect_Projects is
      procedure Consider_Project
        (Project : Ada_Quality.Reporting.Project_Record)
      is
         Runs : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
           Snapshot_Runs (Project.Id);
         Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
           (if Runs.Is_Empty then
               (Project_Id => Project.Id, Selection => (others => <>), Changes => <>)
            else Ada_Quality.Reporting.Compare_Project
              (Session, Project.Id, Runs.Last_Element.Id));
         Include : constant Boolean :=
           Filter = "all" or else
           (Filter = "unhealthy" and then Is_Unhealthy (Runs)) or else
           (Filter = "regressed" and then not Comparison.Changes.Is_Empty) or else
           (Filter = "stale" and then
            (Runs.Is_Empty or else
             not Runs.Last_Element.Started_At.Present or else
             Runs.Last_Element.Started_At.Value < Stale_Before.Value));
      begin
         if Project.Id <= Project_Boundary and then Include and then
           (Tag_Filter = "" or else Has_Tag (To_String (Project.Tags), Tag_Filter))
         then
            Project_Pages.Consider
              (Selected, Project, Total, Request.Page);
         end if;
      end Consider_Project;
   begin
      Ada_Quality.Reporting.Visit_Projects
        (Session, Process => Consider_Project'Access);
   end Collect_Projects;

   procedure Emit_Result is
   begin
      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Emit_Document
           (Ada_Quality.JSON_Reports.Render_Status
              (Session, Selected,
               Page_Metadata
                 (Total, Request.Page.Offset, Natural (Selected.Length),
                  Request.Page.Limit, Snapshot, Project_Boundary,
                  Project_Revision_Value, Binding),
               Pretty => True));
      else
         declare
            Output : Ada.Strings.Unbounded.Unbounded_String;
         begin
            for Project of Selected loop
               declare
                  Runs : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
                    Snapshot_Runs (Project.Id);
                  Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
                    (if Runs.Is_Empty then
                        (Project_Id => Project.Id, Selection => (others => <>), Changes => <>)
                     else Ada_Quality.Reporting.Compare_Project
                       (Session, Project.Id, Runs.Last_Element.Id));
                  Prefix : constant String :=
                    "project" & Positive'Image (Project.Id) & " " &
                    (if Project.Enabled then "enabled" else "disabled") & " " &
                    To_String (Project.Path);
               begin
                  if Runs.Is_Empty then
                     Append (Output, Prefix & ": never assessed" & ASCII.LF);
                  else
                     declare
                        Run : constant Ada_Quality.Reporting.Run_Record :=
                          Runs.Last_Element;
                        State : constant String :=
                          (case Run.State is
                              when Assessment_Running => "running",
                              when Assessment_Completed => "completed",
                              when Assessment_Invalid => "invalid",
                              when Assessment_Interrupted => "interrupted");
                     begin
                        Append
                          (Output, Prefix & ": run" & Positive'Image (Run.Id) &
                           " " & State & ", " &
                           (if Comparison.Selection.Status =
                             Ada_Quality.History.Comparison_Available
                            then Natural'Image
                              (Natural (Comparison.Changes.Length)) & " regression(s)"
                            else "comparison " & Ada_Quality.History.Image
                              (Comparison.Selection.Status)) & ASCII.LF);
                     end;
                  end if;
               end;
            end loop;
            Emit_Document (To_String (Output));
         end;
      end if;
   end Emit_Result;
begin
   Prepare_Query;
   Collect_Projects;
   Emit_Result;
   return 0;
end Run_Status;
