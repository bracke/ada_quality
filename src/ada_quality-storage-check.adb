separate (Ada_Quality.Storage)
procedure Check
  (Item   : in out Store;
   Limits : Integrity_Limits := (others => <>))
is
   type Table_Rows is array (Positive range 1 .. Logical_Table_Count) of Entity_Vectors.Vector;

   Status : Database.Status.Result;
   Tx     : Database.Transactions.Transaction;
   Rows   : Table_Rows;

   package Id_Sets is new Ada.Containers.Ordered_Sets (Positive);
   package Finding_Key_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "<" => Ada.Strings.Unbounded."<",
      "=" => Ada.Strings.Unbounded."=");
   package Id_Position_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Positive);
   package Id_Boolean_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Boolean);
   package Parent_Head_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Natural);
   package Position_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Natural);

   type Parent_Head_Array is
     array (Indicator_Results_Table .. Events_Table) of Parent_Head_Maps.Map;
   type Position_Vector_Array is
     array (Indicator_Results_Table .. Events_Table) of Position_Vectors.Vector;

   Project_Ids  : Id_Sets.Set;
   Assessment_Aliases : Finding_Key_Sets.Set;
   Run_Positions : Id_Position_Maps.Map;
   Run_Formats   : Id_Boolean_Maps.Map;
   Parent_Heads : Parent_Head_Array;
   Next_Row     : Position_Vector_Array;

   function Has_Project (Id : Natural) return Boolean is
     (Id > 0 and then Project_Ids.Contains (Positive (Id)));

   function Has_Run (Id : Natural) return Boolean is
     (Id > 0 and then Run_Positions.Contains (Positive (Id)));

   function Child_Count (Table, Run_Id : Positive) return Natural is
      Result : Natural := 0;
      Position : Natural :=
        (if Parent_Heads (Table).Contains (Run_Id)
         then Parent_Heads (Table).Element (Run_Id) else 0);
   begin
      while Position /= 0 loop
         Result := Result + 1;
         Position := Next_Row (Table) (Positive (Position));
      end loop;
      return Result;
   end Child_Count;

   function Lossless_Run (Id : Positive) return Boolean is
     (Run_Formats.Element (Id));

   procedure Build_Indexes is
   begin
      for Position in Rows (Projects_Table).First_Index .. Rows (Projects_Table).Last_Index loop
         if Project_Ids.Contains (Rows (Projects_Table) (Position).Id) then
            raise Storage_Error with
              "duplicate project identifier" &
              Positive'Image (Rows (Projects_Table) (Position).Id);
         end if;
         Project_Ids.Insert (Rows (Projects_Table) (Position).Id);
      end loop;
      for Position in Rows (Assessments_Table).First_Index .. Rows (Assessments_Table).Last_Index loop
         if Run_Positions.Contains (Rows (Assessments_Table) (Position).Id) then
            raise Storage_Error with
              "duplicate assessment identifier" &
              Positive'Image (Rows (Assessments_Table) (Position).Id);
         end if;
         Run_Positions.Insert (Rows (Assessments_Table) (Position).Id, Position);
      end loop;
      for Table in Indicator_Results_Table .. Events_Table loop
         for Position in Rows (Table).First_Index .. Rows (Table).Last_Index loop
            declare
               Row  : constant Entity := Rows (Table) (Position);
               Head : Natural := 0;
            begin
               if Row.Parent_Id = 0 or else not Has_Run (Row.Parent_Id) then
                  raise Storage_Error with
                    Decode (Table_Name (Table)) & " row has no owning assessment" &
                    Positive'Image (Row.Id);
               end if;
               if Parent_Heads (Table).Contains (Positive (Row.Parent_Id)) then
                  Head := Parent_Heads (Table).Element (Positive (Row.Parent_Id));
                  Parent_Heads (Table).Replace (Positive (Row.Parent_Id), Position);
               else
                  Parent_Heads (Table).Insert (Positive (Row.Parent_Id), Position);
               end if;
               Next_Row (Table).Append (Head);
            end;
         end loop;
      end loop;
   end Build_Indexes;

   procedure Load_All_Rows is
      Cursor : Entity_Tables.Cursor;
      Total_Rows : Natural := 0;
      Total_Text_Bytes : Long_Long_Integer := 0;

      procedure Account (Row : Entity) is
         Text_Bytes : constant Long_Long_Integer :=
           Long_Long_Integer (Length (Row.Kind)) +
           Long_Long_Integer (Length (Row.State)) +
           Long_Long_Integer (Length (Row.Payload));
      begin
         if Total_Rows = Limits.Max_Total_Rows then
            raise Storage_Error with
              "database integrity check exceeds the row limit of" &
              Positive'Image (Limits.Max_Total_Rows);
         end if;
         Total_Rows := Total_Rows + 1;
         if Text_Bytes > Long_Long_Integer (Limits.Max_Text_Bytes) - Total_Text_Bytes then
            raise Storage_Error with
              "database integrity check exceeds the text limit of" &
              Positive'Image (Limits.Max_Text_Bytes) & " bytes";
         end if;
         Total_Text_Bytes := Total_Text_Bytes + Text_Bytes;
      end Account;
   begin
      for Table in Rows'Range loop
         Status := Entity_Tables.Scan
           (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "scan " & Decode (Table_Name (Table)) & " for integrity check");
         while Entity_Tables.Has_Element (Cursor) loop
            declare
               Row : constant Entity := Entity_Tables.Element (Cursor);
            begin
               Account (Row);
               Rows (Table).Append (Row);
            end;
            Status := Entity_Tables.Next
              (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
            Require_OK (Status, "advance " & Decode (Table_Name (Table)) & " integrity scan");
         end loop;
      end loop;
   end Load_All_Rows;

   procedure Validate_Metadata is
   begin
      if Rows (Metadata_Table).Length /= 1 then
         raise Storage_Error with "database must contain exactly one schema metadata row";
      end if;
      declare
         Row : constant Entity := Rows (Metadata_Table).First_Element;
      begin
         if not Metadata_Row_Is_Valid (Row) or else S (Row.Payload) /= Current_Schema_Version
         then
            raise Storage_Error with "schema metadata is malformed or unsupported";
         end if;
      end;
   end Validate_Metadata;

   procedure Validate_Projects is
   begin
      for Row of Rows (Projects_Table) loop
         if not Project_Row_Is_Valid (Row) then
            raise Storage_Error with "malformed project row" & Positive'Image (Row.Id);
         end if;
      end loop;
   end Validate_Projects;

   procedure Validate_Runs is
      --  AQ-WAIVER: SRC-03 target=validate_lifecycle owner=aq expires=2099-12-31 justification=lifecycle-matrix
      procedure Validate_Lifecycle (Run : Entity; State : Assessment_Status) is
         Started_Count  : Natural := 0;
         Terminal_Count : Natural := 0;
         Alias_Count    : Natural := 0;
         Event_Count    : Natural := 0;
         Position       : Natural :=
           (if Parent_Heads (Events_Table).Contains (Run.Id)
            then Parent_Heads (Events_Table).Element (Run.Id) else 0);
      begin
         while Position /= 0 loop
            declare
               Event : constant Entity := Rows (Events_Table) (Positive (Position));
            begin
               Event_Count := Event_Count + 1;
               if not Event.Active then
                  raise Storage_Error with "inactive assessment event" & Positive'Image (Event.Id);
               else
                  case Classify_Lifecycle_Event (State, S (Event.Kind), S (Event.State)) is
                     when Started_Lifecycle_Event => Started_Count := Started_Count + 1;
                     when Terminal_Lifecycle_Event => Terminal_Count := Terminal_Count + 1;
                     when Alias_Event =>
                        declare
                           Name : constant Ada.Strings.Unbounded.Unbounded_String :=
                             Ada.Strings.Unbounded.To_Unbounded_String (S (Event.Payload));
                        begin
                           if Assessment_Aliases.Contains (Name) then
                              raise Storage_Error with
                                "duplicate assessment alias " & S (Event.Payload);
                           end if;
                           Assessment_Aliases.Insert (Name);
                           Alias_Count := Alias_Count + 1;
                        end;
                     when Invalid_Lifecycle_Event =>
                        raise Storage_Error with
                          "contradictory assessment event" & Positive'Image (Event.Id);
                  end case;
               end if;
               Position := Next_Row (Events_Table) (Positive (Position));
            end;
         end loop;
         if not Lifecycle_Counts_Are_Valid
           (State, Started_Count, Terminal_Count, Alias_Count, Event_Count)
         then
            raise Storage_Error with "invalid assessment lifecycle" & Positive'Image (Run.Id);
         end if;
      end Validate_Lifecycle;
   begin
      for Row of Rows (Assessments_Table) loop
         declare
            State : constant String := S (Row.State);
            Results : constant Natural := Child_Count (Indicator_Results_Table, Row.Id);
            Measurements : constant Natural := Child_Count (Measurements_Table, Row.Id);
            Findings : constant Natural := Child_Count (Findings_Table, Row.Id);
            Executions : constant Natural := Child_Count (Executions_Table, Row.Id);
            Payload : Assessment_Payload_Data;
            Run_State : Assessment_Status;
         begin
            if not Decode_Assessment_Row (Row, Payload, Run_State) or else
              not Has_Project (Row.Parent_Id)
            then
               raise Storage_Error with "malformed assessment row" & Positive'Image (Row.Id);
            elsif State in "completed" | "invalid" or else
              (State = "interrupted" and then Results > 0)
            then
               if Results /= Indicator_Count'Last or else Measurements /= Indicator_Count'Last then
                  raise Storage_Error with
                    "terminal assessment has incomplete result or measurement cardinality" &
                    Positive'Image (Row.Id);
               end if;
            elsif Results /= 0 or else Measurements /= 0 or else Findings /= 0 or else Executions /= 0 then
               raise Storage_Error with
                 "unpublished assessment owns terminal evidence" & Positive'Image (Row.Id);
            end if;
            Run_Formats.Insert (Row.Id, Payload.Lossless);
            Validate_Lifecycle (Row, Run_State);
         end;
      end loop;
   end Validate_Runs;

   --  AQ-WAIVER: SRC-03 target=validate_results_and_measurements owner=aq expires=2099-12-31 justification=audit
   procedure Validate_Results_And_Measurements is
   begin
      for Run of Rows (Assessments_Table) loop
         if S (Run.State) in "completed" | "invalid" or else
           (S (Run.State) = "interrupted" and then Child_Count (Indicator_Results_Table, Run.Id) > 0)
         then
            declare
               Seen_Result, Seen_Measurement : array (Indicator_Id) of Boolean := [others => False];
               Result_Executions : array (Indicator_Id) of Execution_Status := [others => Not_Run];
               Result_States, Result_Payloads, Measurement_States :
                 array (Indicator_Id) of Unbounded_Wide_Wide_String;
               Result_Position : Natural :=
                 (if Parent_Heads (Indicator_Results_Table).Contains (Run.Id)
                  then Parent_Heads (Indicator_Results_Table).Element (Run.Id) else 0);
               Measurement_Position : Natural :=
                 (if Parent_Heads (Measurements_Table).Contains (Run.Id)
                  then Parent_Heads (Measurements_Table).Element (Run.Id) else 0);
            begin
               while Result_Position /= 0 loop
                  declare
                     Row : constant Entity :=
                       Rows (Indicator_Results_Table) (Positive (Result_Position));
                  begin
                     declare
                        Id     : Indicator_Id;
                        State  : constant String := S (Row.State);
                        Parsed : constant Boolean := Ada_Quality.Indicators.Parse_Canonical (S (Row.Kind), Id);
                        Execution  : Execution_Status;
                        Compliance : Compliance_Status;
                     begin
                        if not Parsed or else Seen_Result (Id) or else
                          not Decode_Result_State (State, Execution, Compliance) or else
                          Row.Active /= (Compliance = Pass)
                        then
                           raise Storage_Error with
                             "invalid or duplicate indicator result" & Positive'Image (Row.Id);
                        end if;
                        if Lossless_Run (Run.Id) then
                           declare
                              Value : Indicator_Result;
                           begin
                              if not Decode_Result_Payload (S (Row.Payload), Value) then
                                 raise Storage_Error with
                                   "indicator result has noncanonical payload" & Positive'Image (Row.Id);
                              end if;
                           end;
                        elsif Ada.Strings.Fixed.Index (S (Row.Payload), [Character'Val (10)]) = 0 then
                           raise Storage_Error with
                             "legacy indicator result payload is malformed" & Positive'Image (Row.Id);
                        end if;
                        Result_States (Id) := Row.State;
                        Result_Payloads (Id) := Row.Payload;
                        Result_Executions (Id) := Execution;
                        Seen_Result (Id) := True;
                     end;
                     Result_Position :=
                       Next_Row (Indicator_Results_Table) (Positive (Result_Position));
                  end;
               end loop;
               while Measurement_Position /= 0 loop
                  declare
                     Row : constant Entity :=
                       Rows (Measurements_Table) (Positive (Measurement_Position));
                  begin
                     declare
                        Id     : Indicator_Id;
                        State  : constant String := S (Row.State);
                        Parsed : constant Boolean := Ada_Quality.Indicators.Parse_Canonical (S (Row.Kind), Id);
                        Value  : Measurement_Value;
                     begin
                        if not Parsed or else not Seen_Result (Id) or else Seen_Measurement (Id) or else
                          Row.Active /= (Result_Executions (Id) = Succeeded) or else
                          not Decode_Measurement
                            (State, S (Row.Payload), Value,
                             Require_Versioned => Lossless_Run (Run.Id))
                        then
                              raise Storage_Error with
                                "invalid, duplicate, or noncanonical measurement" & Positive'Image (Row.Id);
                        end if;
                        Measurement_States (Id) := Row.State;
                        Seen_Measurement (Id) := True;
                     end;
                     Measurement_Position :=
                       Next_Row (Measurements_Table) (Positive (Measurement_Position));
                  end;
               end loop;
               if (for some Id in Indicator_Id => not Seen_Result (Id) or else not Seen_Measurement (Id)) then
                  raise Storage_Error with
                    "terminal assessment is missing indicator evidence" & Positive'Image (Run.Id);
               end if;
               for Id in Indicator_Id loop
                  if not Result_Measurement_Are_Consistent
                    (S (Result_States (Id)), S (Result_Payloads (Id)),
                     S (Measurement_States (Id)), Lossless_Run (Run.Id))
                  then
                     raise Storage_Error with
                       "inconsistent result and measurement evidence for " & Image (Id) &
                       " in assessment" & Positive'Image (Run.Id);
                  end if;
               end loop;
            end;
         end if;
      end loop;
   end Validate_Results_And_Measurements;

   --  AQ-WAIVER: SRC-03 target=validate_other_details owner=aq expires=2099-12-31 justification=terminal-row-audit
   procedure Validate_Other_Details is
      Seen_Findings : Finding_Key_Sets.Set;
   begin
      for Row of Rows (Findings_Table) loop
         declare
            Level : Severity;
            Key : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String
                (Positive'Image (Positive (Row.Parent_Id)) & Character'Val (0) & S (Row.Kind));
         begin
            if Length (Row.Kind) = 0 or else not Row.Active or else
              not Decode_Severity (S (Row.State), Level) or else
              Seen_Findings.Contains (Key)
            then
               raise Storage_Error with "malformed finding row" & Positive'Image (Row.Id);
            end if;
            Seen_Findings.Insert (Key);
            if Lossless_Run (Positive (Row.Parent_Id)) then
               declare
                  Payload : constant String := S (Row.Payload);
                  Value   : Finding;
               begin
                  if not Decode_Finding_Payload (Payload, Value) then
                     raise Storage_Error with "malformed finding payload" & Positive'Image (Row.Id);
                  elsif not Ada_Quality.Finding_Identity.Matches
                    (S (Row.Kind), Value.Indicator, To_String (Value.Rule),
                     To_String (Value.Relative_Path), To_String (Value.Message))
                  then
                     raise Storage_Error with
                       "finding identity contradicts payload" & Positive'Image (Row.Id);
                  end if;
               end;
            elsif Ada.Strings.Fixed.Index (S (Row.Payload), [Character'Val (10)]) = 0 then
               raise Storage_Error with "malformed legacy finding payload" & Positive'Image (Row.Id);
            end if;
         end;
      end loop;
      for Row of Rows (Executions_Table) loop
         if Length (Row.Kind) = 0 or else
           not Execution_Row_Is_Valid (S (Row.State), S (Row.Payload), Row.Active)
         then
            raise Storage_Error with "malformed execution row" & Positive'Image (Row.Id);
         end if;
      end loop;
      for Row of Rows (Events_Table) loop
         if not Event_Row_Is_Valid (Row) then
            raise Storage_Error with "malformed event row" & Positive'Image (Row.Id);
         end if;
      end loop;
   end Validate_Other_Details;
begin
   if not Item.Opened or else not Database.Is_Open (Item.DB) then
      raise Storage_Error with "database is not open";
   end if;
   if Database.Catalog.Table_Count (Database.Catalog_State_Key (Item.DB)) /= 8 then
      raise Storage_Error with "database must contain exactly eight logical tables";
   end if;
   Database.Transactions.Begin_Read (Item.DB, Tx);
   Load_All_Rows;
   Build_Indexes;
   Validate_Metadata;
   Validate_Projects;
   Validate_Runs;
   Validate_Results_And_Measurements;
   Validate_Other_Details;
   Require_OK (Database.Transactions.Commit (Tx), "database integrity read");
exception
   when Storage_Error =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
   when E : others =>  --  AQ: audited exception boundary
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise Storage_Error with "database integrity validation failed: " & Ada.Exceptions.Exception_Message (E);
end Check;
