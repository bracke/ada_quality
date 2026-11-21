separate (Ada_Quality.Reporting)
--  AQ-WAIVER: SRC-03 target=decode_details owner=core expires=2027-11-21 justification=single-snapshot-table-dispatch
   procedure Decode_Snapshot (Item : in out Session; Rows : in out Entity_Table_Array) is
      Digest : Interfaces.Unsigned_64 := 16#CBF2_9CE4_8422_2325#;
      Known_Projects : Run_Index_Maps.Map;
      procedure Index_Rows is
      begin
         Hash (Digest, "ada-quality-snapshot-identity-v2");
         for Table in Rows'Range loop
            Entity_Sorting.Sort (Rows (Table));
            Hash (Digest, Positive'Image (Table));
            for Row of Rows (Table) loop
               Hash (Digest, Positive'Image (Row.Id));
               Hash (Digest, Natural'Image (Row.Parent_Id));
               Hash (Digest, S (Row.Kind));
               Hash (Digest, S (Row.State));
               Hash (Digest, S (Row.Payload));
               Hash (Digest, Boolean'Image (Row.Active));
            end loop;
         end loop;
         Item.Identity := To_Unbounded_String ("fnv1a64:" & Hex (Digest));
      end Index_Rows;

      procedure Decode_Projects is
      begin
         for Row of Rows (Projects_Table) loop
            declare
               Context : constant String := Context_Of ("project", Row.Id);
               State   : constant String := S (Row.State);
               Path, Tags : Ada.Strings.Unbounded.Unbounded_String;
            begin
               if not Project_Row_Is_Valid (Row) or else
                 not Decode_Project_Payload (S (Row.Payload), Path, Tags)
               then
                  raise Integrity_Error with Context & ": malformed registry entry";
               end if;
               Item.All_Projects.Append
                 (Project_Record'(Id => Row.Id, Path => Path, Tags => Tags,
                   Enabled => Row.Active, Removed => State = "removed"));
               Item.Project_Index.Insert (Row.Id, Item.All_Projects.Last_Index);
               Known_Projects.Insert (Row.Id, Item.All_Projects.Last_Index);
            end;
         end loop;
         Rows (Projects_Table).Clear;
      end Decode_Projects;

      procedure Decode_Runs is
      begin
         for Row of Rows (Assessments_Table) loop
            declare
               Context : constant String := Context_Of ("assessment run", Row.Id);
               Payload : constant String := S (Row.Payload);
               State   : Assessment_Status;
               Decoded : Assessment_Payload_Data;
            begin
               if not Decode_Assessment_Row (Row, Decoded, State) or else
                 not Known_Projects.Contains (Row.Parent_Id)
               then
                  raise Integrity_Error with Context & ": run is not owned by a registered project";
               end if;
               Item.All_Runs.Append
                 (Run_Record'(Id => Row.Id, Project_Id => Row.Parent_Id, State => State,
                   Source_Id => Decoded.Source_Fingerprint,
                   Policy_Id => Decoded.Policy_Fingerprint,
                   Toolchain_Id => Decoded.Toolchain_Fingerprint,
                   Started_At =>
                     (if Decoded.Started_At.Present
                      then (Present => True, Value => Decoded.Started_At.Value)
                      else (Present => False)),
                   Finished_At =>
                     (if Decoded.Finished_At.Present
                      then (Present => True, Value => Decoded.Finished_At.Value)
                      else (Present => False)),
                   Format => (if Decoded.Lossless then Lossless_Evidence else Legacy_Evidence)));
               Item.Run_Index.Insert (Row.Id, Item.All_Runs.Last_Index);
               if not Item.Project_Runs.Contains (Row.Parent_Id) then
                  Item.Project_Runs.Insert
                    (Row.Parent_Id, History_Position_Vectors.Empty_Vector);
               end if;
               Item.Project_Runs.Reference (Row.Parent_Id).Append
                 (Item.All_Runs.Last_Index);
               declare
                  History_Row : constant Ada_Quality.History_Data.History_Item :=
                    (Id => Row.Id, Project_Id => Row.Parent_Id, Status => To_Unbounded_String (S (Row.State)),
                     Summary => To_Unbounded_String (Payload),
                     Source_Fingerprint => Decoded.Source_Fingerprint,
                     Policy_Fingerprint => Decoded.Policy_Fingerprint,
                     Toolchain_Fingerprint => Decoded.Toolchain_Fingerprint);
               begin
                  Item.Payloads.Append (History_Row);
                  if not Item.Project_Histories.Contains (Row.Parent_Id) then
                     Item.Project_Histories.Insert (Row.Parent_Id, History_Position_Vectors.Empty_Vector);
                  end if;
                  declare
                     Positions : History_Position_Vectors.Vector renames
                       Item.Project_Histories.Reference (Row.Parent_Id);
                  begin
                     Positions.Append (Item.Payloads.Last_Index);
                  end;
               end;
               Item.Details.Insert (Row.Id, (others => <>));
            end;
         end loop;
         Rows (Assessments_Table).Clear;
      end Decode_Runs;

      procedure Decode_Details is
      begin
         for Table in Indicator_Results_Table .. Events_Table loop
            for Row of Rows (Table) loop
               if not Item.Details.Contains (Row.Parent_Id) then
                  raise Integrity_Error with
                    Context_Of (Decode (Table_Name (Table)), Row.Id) & ": orphaned evidence";
               end if;
               declare
                  Group : Detail_Group renames Item.Details.Reference (Row.Parent_Id);
               begin
                  case Table is
                     when Indicator_Results_Table =>
                        declare
                           Context : constant String := Context_Of ("indicator result", Row.Id);
                           Id : constant Indicator_Id := Parse_Indicator (S (Row.Kind), Context);
                           Execution : Execution_Status;
                           Compliance : Compliance_Status;
                        begin
                           if not Decode_Result_State (S (Row.State), Execution, Compliance) or else
                             Row.Active /= (Compliance = Pass)
                           then
                              raise Integrity_Error with Context & ": malformed active state";
                           end if;
                           Group.Has_Result_State (Id) := True;
                           Group.Result_Succeeded (Id) := Execution = Succeeded;
                           Group.Results.Append (To_Detail (Row));
                        end;
                     when Measurements_Table =>
                        declare
                           Context : constant String := Context_Of ("measurement", Row.Id);
                           Id : constant Indicator_Id := Parse_Indicator (S (Row.Kind), Context);
                        begin
                           if not Group.Has_Result_State (Id) or else
                             Row.Active /= Group.Result_Succeeded (Id)
                           then
                              raise Integrity_Error with Context & ": active flag contradicts result execution";
                           end if;
                           Group.Measurements.Append (To_Detail (Row));
                        end;
                     when Findings_Table =>
                        if not Row.Active then
                           raise Integrity_Error with Context_Of ("finding", Row.Id) & ": inactive finding";
                        end if;
                        Group.Findings.Append (To_Detail (Row));
                     when Executions_Table =>
                        declare
                           Decoded : Tool_Execution;
                           Valid   : constant Boolean :=
                             Decode_Execution_Row (S (Row.State), S (Row.Payload), Row.Active, Decoded);
                        begin
                           if Length (Row.Kind) = 0 or else not Valid then
                              raise Integrity_Error with
                                Context_Of ("tool execution", Row.Id) & ": malformed row";
                           end if;
                           Decoded.Tool := To_Unbounded_String (S (Row.Kind));
                           Group.Executions.Append
                             (Execution_Record'
                                (Id => Row.Id, Run_Id => Positive (Row.Parent_Id),
                                 Tool => Decoded.Tool, Command => Decoded.Command,
                                 Status => Decoded.Status, Exit_Code => Decoded.Exit_Code,
                                 Output_Digest => Decoded.Output_Digest,
                                 Output_Bytes => Decoded.Output_Bytes,
                                 Truncated => Decoded.Truncated));
                        end;
                     when Events_Table =>
                        if not Event_Row_Is_Valid (Row) then
                           raise Integrity_Error with Context_Of ("assessment event", Row.Id) & ": malformed row";
                        end if;
                        Group.Events.Append (To_Detail (Row));
                  end case;
               end;
            end loop;
            Rows (Table).Clear;
         end loop;
      end Decode_Details;
   begin
      Index_Rows;
      Decode_Projects;
      Decode_Runs;
      Decode_Details;
   end Decode_Snapshot;
