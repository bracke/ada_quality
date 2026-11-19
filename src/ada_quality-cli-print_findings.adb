separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=put_line justification=filtered-and-lifecycle-reporting-share-one-read-snapshot
procedure Print_Findings (DB_Path : String) is
   Session : Ada_Quality.Reporting.Session;
   Requested : constant String := Option ("--format", "");
   JSON_Mode : constant Boolean := Has_Flag ("--json");
   Format : constant String :=
     (if JSON_Mode then "json" elsif Requested = "" then "text" else Requested);
   Structured : constant Boolean := Requested /= "" or else JSON_Mode or else
     Option ("--project", "") /= "" or else Option ("--indicator", "") /= "" or else
     Option ("--severity", "") /= "" or else Option ("--path", "") /= "" or else
     Option ("--since", "") /= "" or else Option ("--until", "") /= "";
   Output : Ada.Strings.Unbounded.Unbounded_String;

   procedure Put_Line (Text : String) is
   begin
      Append (Output, Text & ASCII.LF);
   end Put_Line;
begin
   Ada_Quality.Reporting.Open (Session, DB_Path);
   if Structured then
      declare
         Project_Id : Natural := 0;
         Indicator : Indicator_Id := Indicator_Id'First;
         Filter_Indicator : constant Boolean := Option ("--indicator", "") /= "";
         Minimum : Severity := Severity'First;
         Path_Filter : constant String := Option ("--path", "");
         Since_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--since");
         Until_Time : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--until");
         Items : Finding_Vectors.Vector;
         use type Ada.Calendar.Time;
      begin
         if Format not in "text" | "json" | "sarif" then
            raise Usage_Error with "findings format requires text, json, or sarif";
         elsif JSON_Mode and then Requested not in "" | "json" then
            raise Usage_Error with "--json conflicts with non-JSON --format";
         elsif Since_Time.Present and then Until_Time.Present and then
           Since_Time.Value > Until_Time.Value
         then
            raise Usage_Error with "--since must not be later than --until";
         end if;
         if Option ("--project", "") /= "" then
            Project_Id := Positive_Option ("--project", "project");
         end if;
         if Filter_Indicator and then
           not Ada_Quality.Indicators.Parse_Canonical (Option ("--indicator", ""), Indicator)
         then
            raise Usage_Error with "--indicator requires a canonical indicator ID";
         end if;
         if Option ("--severity", "") /= "" then
            begin
               Minimum := Severity'Value (Option ("--severity", ""));
            exception
               when Constraint_Error =>
                  raise Usage_Error with "--severity requires info, low, medium, high, or critical";
            end;
         end if;
         for Run of Ada_Quality.Reporting.Runs (Session, Project_Id) loop
            if Run.State = Assessment_Completed and then
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
                           Items.Append (Finding);
                        end if;
                     end loop;
                  end loop;
               end;
            end if;
         end loop;
         if Format = "json" then
            Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
            Emit_Document (Ada_Quality.JSON.Render_Findings (Items, Pretty => True));
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
