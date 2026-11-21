with Ada_Quality.CI_Formats;
with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=print_findings owner=aq expires=2027-11-21 justification=one-reporting-snapshot
procedure Print_Findings (DB_Path : String) is
   type Findings_Request is record
      Format           : Ada.Strings.Unbounded.Unbounded_String;
      Structured       : Boolean := False;
      Project_Id       : Natural := 0;
      Indicator        : Indicator_Id := Indicator_Id'First;
      Filter_Indicator : Boolean := False;
      Indicator_Text   : Ada.Strings.Unbounded.Unbounded_String;
      Minimum          : Severity := Severity'First;
      Severity_Text    : Ada.Strings.Unbounded.Unbounded_String;
      Path_Filter      : Ada.Strings.Unbounded.Unbounded_String;
      Tag_Filter       : Ada.Strings.Unbounded.Unbounded_String;
      Since_Text       : Ada.Strings.Unbounded.Unbounded_String;
      Until_Text       : Ada.Strings.Unbounded.Unbounded_String;
      Since_Time       : Ada_Quality.Reporting.Optional_Timestamp;
      Until_Time       : Ada_Quality.Reporting.Optional_Timestamp;
      Page             : Ada_Quality.Pagination.Page_Request;
   end record;

   function Parse_Request return Findings_Request is
      Result : Findings_Request;
   begin
      Result.Format := To_Unbounded_String
        (Selected_Output_Format
           ("text", "text|json|sarif",
            "findings format requires text, json, or sarif"));
      Result.Structured :=
        Option ("--format", "") /= "" or else Has_Flag ("--json") or else
        Option ("--project", "") /= "" or else Option ("--indicator", "") /= "" or else
        Option ("--severity", "") /= "" or else Option ("--path", "") /= "" or else
        Option ("--tag", "") /= "" or else Option ("--since", "") /= "" or else
        Option ("--until", "") /= "" or else Option ("--limit", "") /= "" or else
        Option ("--offset", "") /= "" or else Option ("--cursor", "") /= "";
      if Option ("--project", "") /= "" then
         Result.Project_Id := Positive_Option ("--project", "project");
      end if;
      Result.Indicator_Text := To_Unbounded_String (Option ("--indicator", ""));
      Result.Filter_Indicator := Length (Result.Indicator_Text) > 0;
      if Result.Filter_Indicator and then
        not Ada_Quality.Indicators.Parse_Canonical
          (To_String (Result.Indicator_Text), Result.Indicator)
      then
         raise Usage_Error with "--indicator requires a canonical indicator ID";
      end if;
      Result.Severity_Text := To_Unbounded_String (Option ("--severity", "info"));
      if Option ("--severity", "") /= "" then
         begin
            Result.Minimum := Severity'Value (Option ("--severity", ""));
         exception
            when Constraint_Error =>
               raise Usage_Error with
                 "--severity requires info, low, medium, high, or critical";
         end;
      end if;
      Result.Path_Filter := To_Unbounded_String (Option ("--path", ""));
      Result.Tag_Filter := To_Unbounded_String (Option ("--tag", ""));
      Result.Since_Text := To_Unbounded_String (Option ("--since", ""));
      Result.Until_Text := To_Unbounded_String (Option ("--until", ""));
      Result.Since_Time := Timestamp_Option ("--since");
      Result.Until_Time := Timestamp_Option ("--until");
      Result.Page := Requested_Page;
      if Result.Since_Time.Present and then Result.Until_Time.Present and then
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

   package Finding_Pages is new Ada_Quality.Pagination.Stream_Pages
     (Ada_Quality.Types.Finding_Vectors);

   Request : constant Findings_Request := Parse_Request;
   Session : Ada_Quality.Reporting.Session;
   Format : constant String := To_String (Request.Format);
   Output : Ada.Strings.Unbounded.Unbounded_String;

   procedure Put_Line (Text : String) is
   begin
      Append (Output, Text & ASCII.LF);
   end Put_Line;
begin
   Ada_Quality.Reporting.Open (Session, DB_Path);
   if Request.Structured then
      declare
         Project_Id : constant Natural := Request.Project_Id;
         Indicator : constant Indicator_Id := Request.Indicator;
         Filter_Indicator : constant Boolean := Request.Filter_Indicator;
         Minimum : constant Severity := Request.Minimum;
         Path_Filter : constant String := To_String (Request.Path_Filter);
         Tag_Filter : constant String := To_String (Request.Tag_Filter);
         Since_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Request.Since_Time;
         Until_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Request.Until_Time;
         Items : Finding_Vectors.Vector;
         Total : Natural := 0;
         Snapshot : Natural := 0;
         Project_Boundary : Natural := 0;
         Project_Revision_Value : Natural := 0;
         Binding : Natural := 0;
      begin
         Binding := Query_Binding
           ("findings|project=" & Natural'Image (Project_Id) &
            "|indicator=" & To_String (Request.Indicator_Text) &
            "|severity=" & To_String (Request.Severity_Text) & "|path=" & Path_Filter &
            "|tag=" & Tag_Filter & "|since=" & To_String (Request.Since_Text) &
            "|until=" & To_String (Request.Until_Text));
         Require_Query_Binding (Binding);
         Snapshot := Cursor_Snapshot (Assessment_Snapshot (Session));
         Project_Boundary := Cursor_Secondary_Snapshot (Project_Snapshot (Session));
         Project_Revision_Value := Cursor_Tertiary_Snapshot
           (Project_Revision (Session, Project_Boundary));
         if Cursor_Version in 4 | 5 then
            Require_Project_Revision (Session, Project_Boundary, Project_Revision_Value);
         end if;
         for Run of Ada_Quality.Reporting.Runs (Session, Project_Id) loop
            if Run.Id <= Snapshot and then Run.State = Assessment_Completed and then
              (Tag_Filter = "" or else Has_Tag
                 (To_String (Ada_Quality.Reporting.Project (Session, Run.Project_Id).Tags), Tag_Filter)) and then
              In_Time_Range (Run.Started_At, Since_Time, Until_Time)
            then
               declare
                  Value : constant Ada_Quality.Reporting.Assessment_Record :=
                    Ada_Quality.Reporting.Read_Assessment (Session, Run.Id);
               begin
                  for Result of Value.Results loop
                     for Finding of Result.Findings loop
                        if (not Filter_Indicator or else Finding.Indicator = Indicator) and then
                          Finding.Level >= Minimum and then
                          (Path_Filter = "" or else Ada.Strings.Fixed.Index
                             (To_String (Finding.Relative_Path), Path_Filter) > 0)
                        then
                           Finding_Pages.Consider
                             (Items, Finding, Total, Request.Page);
                        end if;
                     end loop;
                  end loop;
               end;
            end if;
         end loop;
         if Format = "json" then
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
            Emit_Document
              (Ada_Quality.JSON_Reports.Render_Findings
                 (Items, Page_Metadata
                    (Total, Request.Page.Offset, Natural (Items.Length),
                     Request.Page.Limit, Snapshot,
                     Project_Boundary, Project_Revision_Value, Binding),
                  Pretty => True));
         elsif Format = "sarif" then
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
            Emit_Document (Ada_Quality.CI_Formats.Render_SARIF (Items, Pretty => True));
         else
            for Finding of Items loop
               Put_Line
                 (Image (Finding.Indicator) & " " & Severity'Image (Finding.Level) & " " &
                  To_String (Finding.Relative_Path) &
                  (if Finding.Line = 0 then "" else ":" & Natural'Image (Finding.Line)) &
                  " " & To_String (Finding.Message));
            end loop;
            Emit_Document (To_String (Output));
         end if;
         return;
      end;
   end if;
   for Project of Ada_Quality.Reporting.Projects (Session, Include_Removed => True) loop
      declare
         Runs : constant Ada_Quality.Storage.History_Vectors.Vector :=
           Ada_Quality.Reporting.History_Items (Session, Project.Id);
      begin
         if not Runs.Is_Empty then
            declare
               Latest : constant Ada_Quality.Storage.History_Item := Runs.Last_Element;
               Current : constant Ada_Quality.Storage.Detail_Vectors.Vector :=
                 Ada_Quality.Reporting.Findings (Session, Latest.Id);
               Current_Results : constant Ada_Quality.Storage.Detail_Vectors.Vector :=
                 Ada_Quality.Reporting.Results (Session, Latest.Id);
               Previous : Ada_Quality.Storage.Detail_Vectors.Vector;
               Older    : Ada_Quality.Storage.Detail_Vectors.Vector;
               Baseline : constant Natural := Ada_Quality.History.Baseline_Id (Runs, Latest.Id);

               function Successfully_Remeasured
                 (Finding_Key : Ada.Strings.Unbounded.Unbounded_String) return Boolean
               is
                  Text  : constant String := To_String (Finding_Key);
                  Colon : constant Natural := Ada.Strings.Fixed.Index (Text, ":");
               begin
                  if Colon <= Text'First then
                     return False;
                  end if;
                  for Item of Current_Results loop
                     if To_String (Item.Kind) = Text (Text'First .. Colon - 1) then
                        return Ada.Strings.Fixed.Index (To_String (Item.State), "succeeded/") = 1;
                     end if;
                  end loop;
                  return False;
               end Successfully_Remeasured;
            begin
               if Baseline > 0 then
                  Previous := Ada_Quality.Reporting.Findings (Session, Baseline);
                  for Run of Runs loop
                     exit when Run.Id = Baseline;
                     Older.Append_Vector (Ada_Quality.Reporting.Findings (Session, Run.Id));
                  end loop;
               elsif To_String (Latest.Status) /= "completed" and then Runs.Length >= 2 then
                  Previous := Ada_Quality.Reporting.Findings (Session, Runs (Runs.Last_Index - 1).Id);
               end if;
               declare
                  Current_Findings : Ada_Quality.History.Finding_Index;
                  Classifier : constant Ada_Quality.History.Finding_Classifier :=
                    Ada_Quality.History.Build_Finding_Classifier (Current, Previous, Older);
               begin
                  Ada_Quality.History.Include_Findings (Current_Findings, Current);
                  for Finding of Current loop
                     Put_Line
                       (Ada_Quality.History.Image
                          (Ada_Quality.History.Classify_Finding
                             (Classifier, Finding.Kind, To_String (Latest.Status) = "completed")) & " " &
                        To_String (Finding.State) & " " & To_String (Finding.Summary));
                  end loop;
                  for Finding of Previous loop
                     if not Ada_Quality.History.Contains_Finding (Current_Findings, Finding.Kind) then
                        declare
                           Lifecycle : constant Ada_Quality.History.Finding_Lifecycle :=
                             Ada_Quality.History.Classify_Finding
                               (Classifier, Finding.Kind,
                                To_String (Latest.Status) = "completed" and then
                                  Successfully_Remeasured (Finding.Kind));
                        begin
                           if Lifecycle in Ada_Quality.History.Resolved | Ada_Quality.History.Unconfirmed then
                              Put_Line
                                (Ada_Quality.History.Image (Lifecycle) & " " &
                                 To_String (Finding.State) & " " & To_String (Finding.Summary));
                           end if;
                        end;
                     end if;
                  end loop;
               end;
            end;
         end if;
      end;
   end loop;
   Emit_Document (To_String (Output));
end Print_Findings;
