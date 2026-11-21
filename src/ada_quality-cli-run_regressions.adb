with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=run_regressions owner=aq expires=2027-11-21 justification=regression-selection-matrix
function Run_Regressions (DB_Path : String) return Natural is
begin
   declare
      Projects_Seen : Natural := 0;
      Session : Ada_Quality.Reporting.Session;
      Gate_Exit : Natural := 0;
      Output : Ada.Strings.Unbounded.Unbounded_String;
      Tag_Filter : constant String := Option ("--tag", "");
      Comparisons : Ada_Quality.Command_Models.Comparison_Vectors.Vector;
      Format : constant String := Selected_Output_Format
        ("text", "text|json", "regressions format requires text or json");
      JSON_Mode : constant Boolean := Format = "json";

      procedure Handle (Comparison : Ada_Quality.Reporting.Project_Comparison) is
      begin
         Append (Output, Comparison_Text (Comparison));
         Comparisons.Append (Comparison);
         if Comparison.Selection.Status /= Ada_Quality.History.Comparison_Available then
            Gate_Exit := 3;
         elsif not Comparison.Changes.Is_Empty and then Gate_Exit < 3 then
            Gate_Exit := 1;
         end if;
      end Handle;
   begin
      if Tag_Filter /= "" and then
        not Ada_Quality.Storage.Registry.Is_Tag_Name (Tag_Filter)
      then
         raise Usage_Error with "--tag requires lowercase letters, digits, hyphens, or underscores";
      end if;
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
            if Tag_Filter /= "" and then not Has_Tag
              (To_String
                 (Ada_Quality.Reporting.Project
                    (Session, Ada_Quality.Reporting.Read_Assessment
                       (Session, Current_Id).Run.Project_Id).Tags), Tag_Filter)
            then
               raise Usage_Error with "selected assessment project does not have the requested tag";
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
            elsif Tag_Filter /= "" and then not Has_Tag
              (To_String (Ada_Quality.Reporting.Project (Session, Selected.Project_Id).Tags), Tag_Filter)
            then
               raise Usage_Error with "selected assessment project does not have the requested tag";
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
         begin
            if Tag_Filter /= "" and then not Has_Tag (To_String (Project.Tags), Tag_Filter) then
               raise Usage_Error with "selected project does not have the requested tag";
            end if;
            Handle (Ada_Quality.Reporting.Compare_Project (Session, Project_Id));
            Projects_Seen := 1;
         end;
      else
         for P of Ada_Quality.Reporting.Projects (Session) loop
            if Tag_Filter = "" or else Has_Tag (To_String (P.Tags), Tag_Filter) then
               Projects_Seen := Projects_Seen + 1;
               Handle (Ada_Quality.Reporting.Compare_Project (Session, P.Id));
            end if;
         end loop;
      end if;
      if Projects_Seen = 0 then
         Append (Output, "comparison unavailable: no projects are registered" & ASCII.LF);
         Gate_Exit := 3;
      end if;
      if JSON_Mode then
         Emit_Document
           (Ada_Quality.JSON_Reports.Render_Comparisons
              (Comparisons, Pretty => True));
      else
         Emit_Document (To_String (Output));
      end if;
      return (if Has_Flag ("--fail-on-regression") then Gate_Exit else 0);
   end;
end Run_Regressions;
