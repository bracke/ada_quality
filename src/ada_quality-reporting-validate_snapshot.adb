separate (Ada_Quality.Reporting)
--  AQ-WAIVER: SRC-03 target=validate_lifecycle justification=finite-persisted-state-transition-matrix
   procedure Validate_Snapshot (Item : in out Session) is
      Assessment_Aliases : Finding_Key_Sets.Set;
      procedure Validate_Lifecycle (Run : Run_Record; Group : Detail_Group) is
         Started_Count  : Natural := 0;
         Terminal_Count : Natural := 0;
         Alias_Count    : Natural := 0;
      begin
         for Event of Group.Events loop
            declare
               Kind  : constant String := To_String (Event.Kind);
               State : constant String := To_String (Event.State);
            begin
               case Classify_Lifecycle_Event (Run.State, Kind, State) is
                  when Started_Lifecycle_Event => Started_Count := Started_Count + 1;
                  when Terminal_Lifecycle_Event => Terminal_Count := Terminal_Count + 1;
                  when Alias_Event =>
                     declare
                        Name : constant UString := Event.Summary;
                     begin
                        if Assessment_Aliases.Contains (Name) then
                           raise Integrity_Error with
                             "duplicate assessment alias " & To_String (Name);
                        end if;
                        Assessment_Aliases.Insert (Name);
                        Alias_Count := Alias_Count + 1;
                     end;
                  when Invalid_Lifecycle_Event =>
                     raise Integrity_Error with
                       "assessment" & Positive'Image (Run.Id) & ": contradictory lifecycle event";
               end case;
            end;
         end loop;
         if not Lifecycle_Counts_Are_Valid
           (Run.State, Started_Count, Terminal_Count, Alias_Count, Natural (Group.Events.Length))
         then
            raise Integrity_Error with
              "assessment" & Positive'Image (Run.Id) & ": invalid lifecycle";
         end if;
      end Validate_Lifecycle;
   begin
      for Run of Item.All_Runs loop
         declare
            Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
         begin
            if Run.State in Assessment_Completed | Assessment_Invalid or else
              (Run.State = Assessment_Interrupted and then not Group.Results.Is_Empty)
            then
               declare
                  Validated : constant Assessment_Record :=
                    Decode_Assessment (Item, Run.Id, Allow_Terminal => True);
                  pragma Unreferenced (Validated);
               begin
                  null;
               end;
            elsif not Group.Results.Is_Empty or else not Group.Measurements.Is_Empty or else
              not Group.Findings.Is_Empty or else not Group.Executions.Is_Empty
            then
               raise Integrity_Error with
                 "assessment" & Positive'Image (Run.Id) & ": unpublished terminal evidence";
            end if;
            Validate_Lifecycle (Run, Group);
         end;
      end loop;
   end Validate_Snapshot;
