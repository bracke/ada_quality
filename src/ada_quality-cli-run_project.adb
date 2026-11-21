with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=run_project owner=aq expires=2027-11-21 justification=project-command-router
function Run_Project
  (Store : in out Ada_Quality.Storage.Store;
   DB_Path : String;
   Subcommand : Subcommand_Id) return Natural is
   type Project_List_Request is record
      Page   : Ada_Quality.Pagination.Page_Request;
      Format : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Parse_Project_List_Request return Project_List_Request is
     ((Page   => Requested_Page,
       Format => To_Unbounded_String
         (Selected_Output_Format
            ("text", "text|json", "project list format requires text or json"))));

   package Project_Pages is new Ada_Quality.Pagination.Stream_Pages
     (Ada_Quality.Reporting.Project_Vectors);

   function Id_Argument (Index : Positive) return Positive is
   begin
      return Positive'Value (Positional (Index));
   exception
      when Constraint_Error =>
         raise Usage_Error with "a positive project ID is required";
   end Id_Argument;
begin
   if Subcommand = Project_Add then
      if Positional (3) = "" or else Starts_With (Positional (3), "--") then
         raise Usage_Error with "project add requires a path";
      end if;
      declare
         Id : constant Positive := Ada_Quality.Storage.Registry.Add_Project
           (Store, Positional (3));
      begin
         Ada.Text_IO.Put_Line ("registered project" & Positive'Image (Id));
      end;
   elsif Subcommand = Project_Discover then
      return Run_Project_Discover
        (Store, Positional (3), Has_Flag ("--add"), Remove_Missing => False);
   elsif Subcommand = Project_Sync then
      return Run_Project_Discover
        (Store, Positional (3), Add => True,
         Remove_Missing => Has_Flag ("--remove-missing"));
   elsif Subcommand = Project_List then
      declare
         Session : Ada_Quality.Reporting.Session;
      begin
         Ada_Quality.Reporting.Open (Session, DB_Path);
         declare
            Request : constant Project_List_Request :=
              Parse_Project_List_Request;
            Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
            Snapshot : constant Natural := Cursor_Snapshot
              (Project_Snapshot (Session));
            Revision : constant Natural := Cursor_Secondary_Snapshot
              (Project_Revision (Session, Snapshot));
            Binding : constant Natural := Query_Binding ("project-list");
            Format : constant String := To_String (Request.Format);
            Total : Natural := 0;

            procedure Consider_Project
              (Project : Ada_Quality.Reporting.Project_Record) is
            begin
               if Project.Id <= Snapshot then
                  Project_Pages.Consider
                    (Projects, Project, Total, Request.Page);
               end if;
            end Consider_Project;
         begin
            Require_Query_Binding (Binding);
            if Cursor_Version = 3 then
               Require_Project_Revision (Session, Snapshot, Revision);
            elsif Cursor_Version = 4 then
               raise Usage_Error with "cursor version is not valid for project list";
            elsif Cursor_Version = 5 then
               Require_Project_Revision (Session, Snapshot, Revision);
            end if;
            Ada_Quality.Reporting.Visit_Projects
              (Session, Process => Consider_Project'Access);
            if Format = "json" then
               Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
               Emit_Document
                 (Ada_Quality.JSON_Reports.Render_Projects
                    (Projects, Page_Metadata
                       (Total, Request.Page.Offset, Natural (Projects.Length),
                        Request.Page.Limit, Snapshot, Revision, 0, Binding),
                     Pretty => True));
            else
               declare Output : Ada.Strings.Unbounded.Unbounded_String; begin
                  for P of Projects loop Append (Output, Project_Text (P) & ASCII.LF); end loop;
                  Emit_Document (To_String (Output));
               end;
            end if;
         end;
      end;
   elsif Subcommand = Project_Show then
      declare
         Session : Ada_Quality.Reporting.Session;
         Id      : constant Positive := Id_Argument (3);
      begin
         Ada_Quality.Reporting.Open (Session, DB_Path);
         declare
            Project : constant Ada_Quality.Reporting.Project_Record :=
              Ada_Quality.Reporting.Project (Session, Id);
            Format : constant String := Selected_Output_Format
              ("text", "text|json", "project show format requires text or json");
         begin
            if Format = "json" then
               declare Projects : Ada_Quality.Reporting.Project_Vectors.Vector; begin
                  Projects.Append (Project);
                  Emit_Document
                    (Ada_Quality.JSON_Reports.Render_Projects
                       (Projects, Pretty => True));
               end;
            else
               Emit_Document (Project_Text (Project) & ASCII.LF);
            end if;
         end;
      end;
   elsif Subcommand = Project_Enable then
      Ada_Quality.Storage.Registry.Set_Enabled (Store, Id_Argument (3), True);
   elsif Subcommand = Project_Disable then
      Ada_Quality.Storage.Registry.Set_Enabled (Store, Id_Argument (3), False);
   elsif Subcommand = Project_Relocate then
      if Positional (4) = "" then
         raise Usage_Error with "project relocate requires an ID and path";
      end if;
      Ada_Quality.Storage.Registry.Relocate_Project
        (Store, Id_Argument (3), Positional (4));
      Ada.Text_IO.Put_Line ("relocated project" & Positive'Image (Id_Argument (3)));
   elsif Subcommand = Project_Remove then
      Ada_Quality.Storage.Registry.Remove_Project (Store, Id_Argument (3));
   elsif Subcommand in Project_Tag | Project_Untag then
      if Positional (4) = "" then
         raise Usage_Error with
           "project " & Image (Subcommand) & " requires an ID and tag name";
      end if;
      if Subcommand = Project_Tag then
         Ada_Quality.Storage.Registry.Add_Tag
           (Store, Id_Argument (3), Positional (4));
      else
         Ada_Quality.Storage.Registry.Remove_Tag
           (Store, Id_Argument (3), Positional (4));
      end if;
      Ada.Text_IO.Put_Line
        (Image (Subcommand) & "ged project" & Positive'Image (Id_Argument (3)));
   elsif Subcommand = Project_Tags then
      declare
         Session : Ada_Quality.Reporting.Session;
         Output : Ada.Strings.Unbounded.Unbounded_String;
         Id : Natural := 0;
      begin
         if Positional (3) /= "" then Id := Id_Argument (3); end if;
         Ada_Quality.Reporting.Open (Session, DB_Path);
         declare Selected : Ada_Quality.Reporting.Project_Vectors.Vector; begin
         for P of Ada_Quality.Reporting.Projects (Session) loop
            if Id = 0 or else P.Id = Id then
               Selected.Append (P);
               Append
                 (Output, Positive'Image (P.Id) &
                  (if Length (P.Tags) = 0 then "" else " " & To_String (P.Tags)) & ASCII.LF);
            end if;
         end loop;
         if Selected_Output_Format
           ("text", "text|json", "project tags format requires text or json") = "json"
         then
            Emit_Document
              (Ada_Quality.JSON_Reports.Render_Projects
                 (Selected, Pretty => True));
         else
            Emit_Document (To_String (Output));
         end if;
         end;
      end;
   else
      raise Usage_Error with "unknown project subcommand";
   end if;
   return 0;
end Run_Project;
