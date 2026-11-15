separate (Ada_Quality.CLI)
procedure Print_Findings (DB_Path : String) is
   Session : Ada_Quality.Reporting.Session;
begin
   Ada_Quality.Reporting.Open (Session, DB_Path);
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
                     Ada.Text_IO.Put_Line
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
                              Ada.Text_IO.Put_Line
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
end Print_Findings;
