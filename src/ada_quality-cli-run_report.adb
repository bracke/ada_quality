with Ada_Quality.HTML;
with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=run_report owner=aq expires=2027-11-21 justification=report-filter-matrix
function Run_Report (DB_Path : String) return Natural is
begin
   if Option ("--format", "") not in "json" | "html" then
      raise Usage_Error with "report requires --format json or html";
   end if;
   Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
   declare
      Session : Ada_Quality.Reporting.Session;
      Project_Id : Natural := 0;
      Project_Tag : constant String := Option ("--tag", "");
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
      if Project_Id > 0 and then Project_Tag /= "" then
         raise Usage_Error with "report --project and --tag are mutually exclusive";
      elsif Project_Tag /= "" and then
        not Ada_Quality.Storage.Registry.Is_Tag_Name (Project_Tag)
      then
         raise Usage_Error with "--tag requires lowercase letters, digits, hyphens, or underscores";
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
           (Ada_Quality.JSON_Reports.Render_Archive
              (Session, Pretty => True, Project_Id => Project_Id,
               Project_Tag => Project_Tag,
               Since_Time => Since_Time, Until_Time => Until_Time));
      else
         declare
            Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
         begin
            for P of Ada_Quality.Reporting.Projects (Session) loop
               if (Project_Id = 0 or else P.Id = Project_Id) and then
                 (Project_Tag = "" or else Has_Tag (To_String (P.Tags), Project_Tag))
               then
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
end Run_Report;
