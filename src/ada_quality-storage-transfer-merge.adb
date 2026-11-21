separate (Ada_Quality.Storage.Transfer)
   procedure Merge
     (Item : in out Store; Sources : Source_Vectors.Vector; Dry_Run : Boolean;
      Report : out Merge_Report)
   is
      package Id_Maps is new Ada.Containers.Ordered_Maps (Positive, Positive);
      package Id_Sets is new Ada.Containers.Ordered_Sets (Positive);
      package Alias_Maps is new Ada.Containers.Ordered_Maps
        (Unbounded_String, Positive, "<" => Ada.Strings.Unbounded."<");
      type Project_Action is record
         Id : Positive;
         Path, Tags : Unbounded_String;
         Enabled, Removed, Inserted : Boolean;
      end record;
      package Project_Action_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Project_Action);
      type Run_Action is record
         Id : Positive;
         Value : Assessment;
      end record;
      package Run_Action_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Run_Action);
      type Alias_Action is record
         Run_Id : Positive;
         Name : Unbounded_String;
      end record;
      package Alias_Action_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Alias_Action);

      Temp : Ada_Quality.Temporary_Directories.Temporary_Directory;
      Session : Ada_Quality.Reporting.Session;
      Project_Map, Run_Map : Id_Maps.Map;
      Claimed_Runs : Id_Sets.Set;
      Target_Projects : Project_Vectors.Vector :=
        Ada_Quality.Storage.Registry.Projects
          (Item, Include_Removed => True);
      Target_History : History_Vectors.Vector :=
        Ada_Quality.Storage.Assessments.History (Item);
      Planned_Aliases : Alias_Maps.Map;
      Project_Actions : Project_Action_Vectors.Vector;
      Run_Actions : Run_Action_Vectors.Vector;
      Alias_Actions : Alias_Action_Vectors.Vector;
      Next_Project : Positive := Item.Next_Identifiers (Projects_Table);
      Next_Run : Positive := Item.Next_Identifiers (Assessments_Table);
      First_Planned_Run : constant Positive := Next_Run;
      Tx : Database.Transactions.Transaction;

      function Planned_Evidence_Matches
        (Run_Id : Positive; Value : Assessment) return Boolean
      is
      begin
         for Action of Run_Actions loop
            if Action.Id = Run_Id then
               return Action.Value.Results = Value.Results and then
                 Action.Value.Executions = Value.Executions;
            end if;
         end loop;
         return False;
      end Planned_Evidence_Matches;

      function Result_Matches
        (Stored : Detail_Info; Value : Indicator_Result) return Boolean is
        (To_String (Stored.Kind) = Image (Value.Indicator) and then
         To_String (Stored.State) =
           Image (Value.Execution) & "/" & Image (Value.Compliance) and then
         To_String (Stored.Summary) = Result_Payload (Value));

      function Measurement_Matches
        (Stored : Detail_Info; Value : Indicator_Result) return Boolean is
        (To_String (Stored.Kind) = Image (Value.Indicator) and then
         To_String (Stored.State) =
           Measurement_State (Value.Indicator, Value.Measurement.Kind) and then
         To_String (Stored.Summary) = Image (Value.Measurement));

      function Finding_Matches
        (Stored : Detail_Info; Value : Finding) return Boolean is
        (To_String (Stored.Kind) = To_String (Value.Fingerprint) and then
         To_String (Stored.State) = Severity'Image (Value.Level) and then
         To_String (Stored.Summary) = Finding_Payload (Value));

      function Execution_Matches
        (Stored : Detail_Info; Value : Tool_Execution) return Boolean is
        (To_String (Stored.Kind) = To_String (Value.Tool) and then
         To_String (Stored.State) = Image (Value.Status) and then
         To_String (Stored.Summary) = Execution_Payload (Value));

      function Stored_Results_Match
        (Run_Id : Positive; Value : Assessment) return Boolean
      is
         Stored_Results      : constant Detail_Vectors.Vector :=
           Ada_Quality.Storage.Assessments.Results (Item, Run_Id);
         Stored_Measurements : constant Detail_Vectors.Vector :=
           Ada_Quality.Storage.Assessments.Measurements (Item, Run_Id);
      begin
         if Stored_Results.Length /= Value.Results.Length or else
           Stored_Measurements.Length /= Value.Results.Length
         then
            return False;
         end if;
         for Index in Value.Results.First_Index .. Value.Results.Last_Index loop
            if not Result_Matches (Stored_Results (Index), Value.Results (Index)) or else
              not Measurement_Matches
                (Stored_Measurements (Index), Value.Results (Index))
            then
               return False;
            end if;
         end loop;
         return True;
      end Stored_Results_Match;

      function Stored_Findings_Match
        (Run_Id : Positive; Value : Assessment) return Boolean
      is
         Stored_Findings : constant Detail_Vectors.Vector :=
           Ada_Quality.Storage.Assessments.Findings (Item, Run_Id);
         Index           : Natural := 0;
      begin
         for Result of Value.Results loop
            for Value_Finding of Result.Findings loop
               Index := Index + 1;
               if Index > Natural (Stored_Findings.Length) or else
                 not Finding_Matches (Stored_Findings (Index), Value_Finding)
               then
                  return False;
               end if;
            end loop;
         end loop;
         return Index = Natural (Stored_Findings.Length);
      end Stored_Findings_Match;

      function Stored_Executions_Match
        (Run_Id : Positive; Value : Assessment) return Boolean
      is
         Stored : constant Detail_Vectors.Vector :=
           Ada_Quality.Storage.Assessments.Executions (Item, Run_Id);
      begin
         if Stored.Length /= Value.Executions.Length then
            return False;
         end if;
         for Index in Value.Executions.First_Index .. Value.Executions.Last_Index loop
            if not Execution_Matches (Stored (Index), Value.Executions (Index)) then
               return False;
            end if;
         end loop;
         return True;
      end Stored_Executions_Match;

      function Stored_Evidence_Matches
        (Run_Id : Positive; Value : Assessment) return Boolean is
        (Stored_Results_Match (Run_Id, Value) and then
         Stored_Findings_Match (Run_Id, Value) and then
         Stored_Executions_Match (Run_Id, Value));

      function Existing_Run
        (Project_Id : Positive; Run : Ada_Quality.Reporting.Run_Record;
         Value : Assessment) return Natural
      is
      begin
         for Candidate of Target_History loop
            if not Claimed_Runs.Contains (Candidate.Id) and then
              Candidate.Project_Id = Project_Id and then To_String (Candidate.Status) = "completed" and then
              Candidate.Source_Fingerprint = Run.Source_Id and then
              Candidate.Policy_Fingerprint = Run.Policy_Id and then
              Candidate.Toolchain_Fingerprint = Run.Toolchain_Id and then
              (if Candidate.Id >= First_Planned_Run
               then Planned_Evidence_Matches (Candidate.Id, Value)
               else Stored_Evidence_Matches (Candidate.Id, Value))
            then
               return Candidate.Id;
            end if;
         end loop;
         return 0;
      end Existing_Run;

      function Target_Path (Id : Positive) return Unbounded_String is
      begin
         for Project of Target_Projects loop
            if Project.Id = Id then return Project.Path; end if;
         end loop;
         raise Storage_Error with "merge project mapping is incomplete";
      end Target_Path;

      function Alias_Target (Name : String) return Natural is
      begin
         return
           (if Planned_Aliases.Contains (To_Unbounded_String (Name))
            then Planned_Aliases.Element (To_Unbounded_String (Name)) else 0);
      end Alias_Target;

      procedure Insert_Assessment (Action : Run_Action) is
         Value : Assessment renames Action.Value;
         Result_Id : Natural := Reserve_Ids
           (Item, Indicator_Results_Table, Natural (Value.Results.Length));
         Measure_Id : Natural := Reserve_Ids
           (Item, Measurements_Table, Natural (Value.Results.Length));
         Finding_Count : Natural := 0;
         Finding_Id, Execution_Id : Natural;
         Event_Id : Positive;
         Stamp : constant String := UTC_Now;
         procedure Insert (Table : Positive; Row : Entity; Context : String) is
         begin
            Require_OK (Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Table), Row), Context);
         end Insert;
      begin
         for Result of Value.Results loop
            Finding_Count := Finding_Count + Natural (Result.Findings.Length);
         end loop;
         Finding_Id := Reserve_Ids (Item, Findings_Table, Finding_Count);
         Execution_Id := Reserve_Ids (Item, Executions_Table, Natural (Value.Executions.Length));
         Event_Id := Next_Id (Item, Events_Table);
         Insert
           (Assessments_Table,
            (Id => Action.Id, Parent_Id => Value.Project_Id, Kind => WW ("assessment"),
             State => WW (Assessment_Status_Image (Value.Status)),
             Payload => WW (Assessment_Payload
               (To_String (Value.Source_Fingerprint), To_String (Value.Policy_Fingerprint),
                To_String (Value.Toolchain_Fingerprint), Started_At => Stamp,
                Finished_At => Stamp, Lossless => True)),
             Active => Value.Status = Assessment_Completed), "insert merged assessment");
         for Result of Value.Results loop
            Insert
              (Indicator_Results_Table,
               (Id => Positive (Result_Id), Parent_Id => Action.Id, Kind => WW (Image (Result.Indicator)),
                State => WW (Image (Result.Execution) & "/" & Image (Result.Compliance)),
                Payload => WW (Result_Payload (Result)), Active => Result.Compliance = Pass),
               "insert merged result");
            Result_Id := Result_Id + 1;
            Insert
              (Measurements_Table,
               (Id => Positive (Measure_Id), Parent_Id => Action.Id, Kind => WW (Image (Result.Indicator)),
                State => WW (Measurement_State (Result.Indicator, Result.Measurement.Kind)),
                Payload => WW (Image (Result.Measurement)), Active => Result.Execution = Succeeded),
               "insert merged measurement");
            Measure_Id := Measure_Id + 1;
            for Finding of Result.Findings loop
               Insert
                 (Findings_Table,
                  (Id => Positive (Finding_Id), Parent_Id => Action.Id,
                   Kind => WW (To_String (Finding.Fingerprint)), State => WW (Severity'Image (Finding.Level)),
                   Payload => WW (Finding_Payload (Finding)), Active => True), "insert merged finding");
               Finding_Id := Finding_Id + 1;
            end loop;
         end loop;
         for Execution of Value.Executions loop
            Insert
              (Executions_Table,
               (Id => Positive (Execution_Id), Parent_Id => Action.Id,
                Kind => WW (To_String (Execution.Tool)), State => WW (Image (Execution.Status)),
                Payload => WW (Execution_Payload (Execution)),
                Active => Execution.Status = Tool_Completed), "insert merged execution");
            Execution_Id := Execution_Id + 1;
         end loop;
         Insert
           (Events_Table,
            (Id => Event_Id, Parent_Id => Action.Id, Kind => WW ("published"),
             State => WW (Assessment_Status_Image (Value.Status)),
             Payload => WW ("atomic merge publication"), Active => True), "insert merged event");
      end Insert_Assessment;

      procedure Plan_Projects is
      begin
         for Source_Project of Ada_Quality.Reporting.Projects
           (Session, Include_Removed => True)
         loop
            declare
               Target_Index : Natural := 0;
            begin
               for Index in Target_Projects.First_Index .. Target_Projects.Last_Index loop
                  if Target_Projects (Index).Path = Source_Project.Path then
                     Target_Index := Index;
                  end if;
               end loop;
               if Target_Index = 0 then
                  Project_Map.Insert (Source_Project.Id, Next_Project);
                  Project_Actions.Append
                    (Project_Action'
                       (Id => Next_Project, Path => Source_Project.Path,
                        Tags => Source_Project.Tags, Enabled => Source_Project.Enabled,
                        Removed => Source_Project.Removed, Inserted => True));
                  Target_Projects.Append
                    (Project_Info'
                       (Id => Next_Project, Path => Source_Project.Path,
                        Tags => Source_Project.Tags, Enabled => Source_Project.Enabled,
                        Removed => Source_Project.Removed));
                  Next_Project := Next_Project + 1;
                  Report.Added_Projects := Report.Added_Projects + 1;
               else
                  declare
                     Target : Project_Info := Target_Projects (Positive (Target_Index));
                     Tags   : constant String := Merge_Project_Tags
                       (To_String (Target.Tags),
                        To_String (Source_Project.Tags));
                  begin
                     if not Target.Removed and then
                       Tags /= To_String (Target.Tags)
                     then
                        Target.Tags := To_Unbounded_String (Tags);
                        Target_Projects.Replace_Element (Positive (Target_Index), Target);
                        Project_Actions.Append
                          (Project_Action'
                             (Id => Target.Id, Path => Target.Path, Tags => Target.Tags,
                              Enabled => Target.Enabled, Removed => Target.Removed,
                              Inserted => False));
                     end if;
                     Project_Map.Insert (Source_Project.Id, Target.Id);
                  end;
               end if;
            end;
         end loop;
      end Plan_Projects;

      function Imported_Assessment
        (Run : Ada_Quality.Reporting.Run_Record;
         Target_Project : Positive) return Assessment
      is
         Stored : constant Ada_Quality.Reporting.Assessment_Record :=
           Ada_Quality.Reporting.Read_Assessment (Session, Run.Id);
         Value : Assessment;
      begin
         Value.Project_Id := Target_Project;
         Value.Project_Path := Target_Path (Target_Project);
         Value.Source_Fingerprint := Run.Source_Id;
         Value.Policy_Fingerprint := Run.Policy_Id;
         Value.Toolchain_Fingerprint := Run.Toolchain_Id;
         Value.Status := Assessment_Completed;
         Value.Results := Stored.Results;
         for Execution of Stored.Executions loop
            Value.Executions.Append
              (Tool_Execution'
                 (Tool => Execution.Tool, Command => Execution.Command,
                  Status => Execution.Status, Exit_Code => Execution.Exit_Code,
                  Output_Digest => Execution.Output_Digest,
                  Output_Bytes => Execution.Output_Bytes,
                  Truncated => Execution.Truncated));
         end loop;
         if not Is_Publishable (Value) then
            raise Storage_Error with
              "source contains an unpublishable completed assessment";
         end if;
         return Value;
      end Imported_Assessment;

      procedure Plan_Runs is
      begin
         for Run of Ada_Quality.Reporting.Runs (Session) loop
            if Run.State = Assessment_Completed then
               declare
                  Target_Project : constant Positive :=
                    Project_Map.Element (Run.Project_Id);
                  Value      : constant Assessment :=
                    Imported_Assessment (Run, Target_Project);
                  Existing   : constant Natural := Existing_Run (Target_Project, Run, Value);
                  Target_Run : Positive;
               begin
                  if Existing > 0 then
                     Target_Run := Positive (Existing);
                     Report.Reused_Assessments := Report.Reused_Assessments + 1;
                  else
                     Target_Run := Next_Run;
                     Next_Run := Next_Run + 1;
                     Run_Actions.Append (Run_Action'(Id => Target_Run, Value => Value));
                     Target_History.Append
                       (History_Item'
                          (Id => Target_Run, Project_Id => Target_Project,
                           Status => To_Unbounded_String ("completed"),
                           Summary => Null_Unbounded_String,
                           Source_Fingerprint => Run.Source_Id,
                           Policy_Fingerprint => Run.Policy_Id,
                           Toolchain_Fingerprint => Run.Toolchain_Id));
                     Report.Added_Assessments := Report.Added_Assessments + 1;
                  end if;
                  Claimed_Runs.Insert (Target_Run);
                  Run_Map.Insert (Run.Id, Target_Run);
               end;
            end if;
         end loop;
      end Plan_Runs;

      procedure Plan_Aliases is
      begin
         for Source_Alias of Ada_Quality.Reporting.Aliases (Session) loop
            if Run_Map.Contains (Source_Alias.Run_Id) then
               declare
                  Existing : constant Natural :=
                    Alias_Target (To_String (Source_Alias.Name));
                  Target : constant Positive := Run_Map.Element (Source_Alias.Run_Id);
               begin
                  if Existing = 0 then
                     Alias_Actions.Append
                       (Alias_Action'(Run_Id => Target, Name => Source_Alias.Name));
                     Planned_Aliases.Insert (Source_Alias.Name, Target);
                     Report.Added_Aliases := Report.Added_Aliases + 1;
                  elsif Existing /= Target then
                     Report.Conflicts.Append
                       (Merge_Conflict'
                          (Name => Source_Alias.Name,
                           Detail => To_Unbounded_String
                             ("target assessment" & Positive'Image (Target) &
                              " conflicts with existing assessment" &
                              Natural'Image (Existing))));
                  end if;
               end;
            end if;
         end loop;
      end Plan_Aliases;

      procedure Plan_Source (Source_Index : Positive) is
         Source      : constant String := To_String (Sources (Source_Index));
         Source_Path : Unbounded_String := To_Unbounded_String (Source);
      begin
         Project_Map.Clear;
         Run_Map.Clear;
         Claimed_Runs.Clear;
         begin
            Ada_Quality.Reporting.Open (Session, Source);
         exception
            when Ada_Quality.Reporting.Reporting_Error |
              Ada_Quality.Reporting.Schema_Error |
              Ada_Quality.Reporting.Integrity_Error =>
               Source_Path := To_Unbounded_String
                 (Ada_Quality.Temporary_Directories.Child
                    (Temp, "source-" & Ada.Strings.Fixed.Trim
                       (Positive'Image (Source_Index), Ada.Strings.Both) & ".db"));
               Import (Source, To_String (Source_Path));
               Ada_Quality.Reporting.Open (Session, To_String (Source_Path));
         end;
         Plan_Projects;
         Plan_Runs;
         Plan_Aliases;
         Ada_Quality.Reporting.Close (Session);
      exception
         when others =>
            if Ada_Quality.Reporting.Is_Open (Session) then
               Ada_Quality.Reporting.Close (Session);
            end if;
            raise;
      end Plan_Source;

      procedure Apply_Project (Action : Project_Action) is
      begin
         if Action.Inserted then
            Require_OK
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Projects_Table),
                  (Id => Action.Id, Parent_Id => 0, Kind => WW ("ada_project"),
                   State => WW (if Action.Removed then "removed" else "registered"),
                   Payload => WW
                     (Project_Payload
                        (To_String (Action.Path), To_String (Action.Tags))),
                   Active => Action.Enabled and then not Action.Removed)),
               "insert merged project");
         else
            declare
               Row : Entity;
            begin
               Require_OK
                 (Entity_Tables.Find
                    (Tx, Item.DB, Item.Schemas (Projects_Table), Action.Id, Row),
                  "load merged project tags");
               Row.Payload := WW
                 (Project_Payload
                    (To_String (Action.Path), To_String (Action.Tags)));
               Require_OK
                 (Entity_Tables.Update
                    (Tx, Item.DB, Item.Schemas (Projects_Table), Row),
                  "update merged project tags");
            end;
         end if;
      end Apply_Project;

      procedure Reserve_Plan_Identifiers is
         Dummy : Positive;
      begin
         if Report.Added_Projects > 0 then
            Dummy := Reserve_Ids (Item, Projects_Table, Report.Added_Projects);
         end if;
         if Report.Added_Assessments > 0 then
            Dummy := Reserve_Ids
              (Item, Assessments_Table, Report.Added_Assessments);
         end if;
         pragma Unreferenced (Dummy);
      end Reserve_Plan_Identifiers;

      procedure Apply_Plan is
      begin
         Reserve_Plan_Identifiers;
         Database.Transactions.Begin_Write (Item.DB, Tx);
         for Action of Project_Actions loop
            Apply_Project (Action);
         end loop;
         for Action of Run_Actions loop
            Insert_Assessment (Action);
         end loop;
         for Action of Alias_Actions loop
            Require_OK
              (Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Events_Table),
                  (Id => Next_Id (Item, Events_Table), Parent_Id => Action.Run_Id,
                   Kind => WW ("alias"), State => WW ("alias"),
                   Payload => WW (To_String (Action.Name)), Active => True)),
               "insert merged alias");
         end loop;
         Require_OK
           (Database.Transactions.Commit (Tx), "commit atomic database merge");
         Ada_Quality.Storage.Integrity.Check (Item);
      exception
         when others =>
            if Database.Transactions.Is_Active (Tx) then
               Database.Transactions.Rollback (Tx);
            end if;
            raise;
      end Apply_Plan;
   begin
      Report := (Conflicts => <>, others => 0);
      if Sources.Is_Empty then
         raise Storage_Error with "database merge requires at least one source";
      end if;
      Ada_Quality.Temporary_Directories.Create (Temp, "ada-quality-merge");
      for Event of Ada_Quality.Storage.Assessments.Events (Item) loop
         if To_String (Event.Kind) = "alias" then
            Planned_Aliases.Include (Event.Summary, Event.Run_Id);
         end if;
      end loop;
      for Source_Index in Sources.First_Index .. Sources.Last_Index loop
         Plan_Source (Source_Index);
      end loop;
      if Dry_Run or else not Report.Conflicts.Is_Empty then
         return;
      end if;
      Apply_Plan;
   end Merge;
