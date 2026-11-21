separate (Ada_Quality.Storage)
--  AQ-WAIVER: SRC-03 target=apply_corruption owner=aq expires=2027-11-21 justification=corruption-fixture-matrix
procedure Testing_Corrupt (Item : in out Store; Run_Id : Positive; Kind : Testing_Corruption) is
   Table  : constant Positive := Testing_Corruption_Table (Kind);
   New_Id : constant Positive := Next_Id (Item, Table);
   Tx     : Database.Transactions.Transaction;
   Status : Database.Status.Result;
   Target : Entity;
   Found  : Boolean := False;

   procedure Apply_Corruption is
   begin
      case Kind is
         when Duplicate_Result =>
            Target.Id := New_Id;
            Status := Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Table), Target);
         when Missing_Result =>
            Status := Entity_Tables.Delete (Tx, Item.DB, Item.Schemas (Table), Target.Id);
         when Inconsistent_Result =>
            Target.State := WW ("succeeded/unknown");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Contradictory_Result_Active | Contradictory_Measurement_Active | Inactive_Finding =>
            Target.Active := not Target.Active;
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Nonterminal_Result =>
            declare
               Measurement : Entity;
               Measurement_Found : Boolean := False;
               Original_Kind : constant Unbounded_Wide_Wide_String := Target.Kind;
            begin
               Target.State := WW ("running/unknown");
               Require_OK
                 (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target),
                  "corrupt result as nonterminal");
               declare
                  Cursor : Entity_Tables.Cursor;
               begin
                  Status := Entity_Tables.Scan
                    (Tx, Item.DB, Item.Schemas (Measurements_Table),
                     Database.Predicates.True_Predicate, Cursor);
                  Require_OK (Status, "scan measurements to corrupt");
                  while Entity_Tables.Has_Element (Cursor) loop
                     declare
                        Candidate : constant Entity := Entity_Tables.Element (Cursor);
                     begin
                        if Candidate.Parent_Id = Run_Id and then Candidate.Kind = Original_Kind then
                           Measurement := Candidate;
                           Measurement_Found := True;
                           exit;
                        end if;
                     end;
                     Status := Entity_Tables.Next
                       (Tx, Item.DB, Item.Schemas (Measurements_Table),
                        Database.Predicates.True_Predicate, Cursor);
                     Require_OK (Status, "advance measurements to corrupt");
                  end loop;
               end;
               if not Measurement_Found then
                  raise Storage_Error with "run has no matching measurement to corrupt";
               end if;
               declare
                  Existing  : constant String := S (Measurement.State);
                  Separator : constant Natural := Ada.Strings.Fixed.Index (Existing, ";");
               begin
                  Measurement.State := WW
                    ("UNAVAILABLE_VALUE" &
                     (if Separator = 0 then "" else Existing (Separator .. Existing'Last)));
               end;
               Measurement.Payload := WW ("still running");
               Status := Entity_Tables.Update
                 (Tx, Item.DB, Item.Schemas (Measurements_Table), Measurement);
            end;
         when Noncanonical_Result =>
            Target.Payload := WW (S (Target.Payload) & Character'Val (10) & "extra=value");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Noncanonical_Indicator =>
            Target.Kind := WW ("str_01");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Missing_Terminal_Event =>
            Status := Entity_Tables.Delete (Tx, Item.DB, Item.Schemas (Table), Target.Id);
         when Invalid_Measurement =>
            Target.State := WW ("DECIMAL_VALUE");
            Target.Payload := WW ("ninety percent");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Noncanonical_Measurement =>
            Target.State := WW ("INTEGER_VALUE");
            Target.Payload := WW ("01");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Missing_Measurement_Semantics =>
            Target.State := WW ("BOOLEAN_VALUE");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Noncanonical_Measurement_Semantics =>
            Target.State := WW ("BOOLEAN_VALUE;garbage");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Duplicate_Finding =>
            Target.Id := New_Id;
            Status := Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Table), Target);
         when Malformed_Finding =>
            if Found then
               Target.Payload := WW ("not a finding");
               Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
            else
               Status := Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Table),
                  (Id => New_Id, Parent_Id => Run_Id, Kind => WW ("STR-01:corrupt"), State => WW ("HIGH"),
                   Payload => WW ("not a finding"), Active => True));
            end if;
         when Noncanonical_Finding =>
            Target.Payload := WW (S (Target.Payload) & Character'Val (10) & "extra=value");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Mismatched_Finding =>
            declare
               Value : Finding;
               Other : Indicator_Id;
            begin
               if not Decode_Finding_Payload (S (Target.Payload), Value) then
                  raise Storage_Error with "cannot decode finding selected for corruption";
               end if;
               Other := (if Value.Indicator = Indicator_Id'First then Indicator_Id'Succ (Value.Indicator)
                         else Indicator_Id'First);
               Target.Kind := WW
                 (Ada_Quality.Finding_Identity.Create
                    (Other, To_String (Value.Rule), To_String (Value.Relative_Path),
                     To_String (Value.Message)));
               Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
            end;
         when Malformed_Execution =>
            Target.Payload := WW ("not execution evidence");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Noncanonical_Execution =>
            Target.Payload := WW
              (With_Field (S (Target.Payload), "output_digest", "not-a-digest"));
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Invalid_Run_State | Unsupported_Evidence_Format | Malformed_Run_Timestamp |
           Incomplete_Run_Timestamps | Orphaned_Run_Finish | Inverted_Run_Timestamps =>
            null;
         when Malformed_Metadata =>
            Target.State := WW ("broken");
            Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target);
         when Extra_Metadata =>
            Status := Entity_Tables.Insert
              (Tx, Item.DB, Item.Schemas (Table),
               (Id => New_Id, Parent_Id => 0, Kind => WW ("schema_version"), State => WW ("active"),
                Payload => WW (Current_Schema_Version), Active => True));
      end case;
   end Apply_Corruption;
begin
   Database.Transactions.Begin_Write (Item.DB, Tx);
   if Kind in Malformed_Metadata | Extra_Metadata then
      Require_OK
        (Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Table), 1, Target), "load metadata to corrupt");
      Apply_Corruption;
      Require_OK (Status, "corrupt schema metadata");
   elsif Kind in Invalid_Run_State | Unsupported_Evidence_Format | Malformed_Run_Timestamp |
     Incomplete_Run_Timestamps | Orphaned_Run_Finish | Inverted_Run_Timestamps
   then
      Require_OK (Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Table), Run_Id, Target), "load run to corrupt");
      case Kind is
         when Invalid_Run_State =>
            Target.State := WW ("exploded");
         when Unsupported_Evidence_Format =>
            Target.Payload := WW (With_Field (S (Target.Payload), "evidence_format", "999"));
         when Malformed_Run_Timestamp =>
            Target.Payload := WW (With_Field (S (Target.Payload), "started_at", "not-a-timestamp"));
         when Incomplete_Run_Timestamps =>
            Target.Payload := WW
              (Assessment_Payload
                 (Field (S (Target.Payload), "source"), Field (S (Target.Payload), "policy"),
                  Field (S (Target.Payload), "toolchain"),
                  Started_At => Field (S (Target.Payload), "started_at"), Lossless => True));
         when Orphaned_Run_Finish =>
            Target.Payload := WW
              (Assessment_Payload
                 (Field (S (Target.Payload), "source"), Field (S (Target.Payload), "policy"),
                  Field (S (Target.Payload), "toolchain"),
                  Finished_At => Field (S (Target.Payload), "finished_at"), Lossless => True));
         when Inverted_Run_Timestamps =>
            Target.Payload := WW
              (Assessment_Payload
                 (Field (S (Target.Payload), "source"), Field (S (Target.Payload), "policy"),
                  Field (S (Target.Payload), "toolchain"),
                  Started_At => "2026-01-02T00:00:00Z", Finished_At => "2026-01-01T00:00:00Z",
                  Lossless => True));
         when others =>
            null;
      end case;
      Require_OK (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Table), Target), "corrupt run metadata");
   else
      Find_Testing_Evidence (Item, Tx, Table, Run_Id, Target, Found);
      Apply_Corruption;
      if Kind /= Malformed_Finding and then not Found then
         raise Storage_Error with "run has no evidence to corrupt";
      end if;
      Require_OK (Status, "corrupt evidence");
   end if;
   Require_OK (Database.Transactions.Commit (Tx), "commit corruption fixture");
exception
   when others =>  --  AQ: audited exception boundary
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Testing_Corrupt;
