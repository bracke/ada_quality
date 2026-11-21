separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_storage_test owner=core expires=2027-11-21 justification=storage-fixture-matrix
procedure Run_Storage_Test is
begin
declare
   Path  : constant String := Fixture_Root & "/storage_test.db";
   Relocated_Root : constant String := Fixture_Root & "/relocated-project";
   Root  : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Store : Ada_Quality.Storage.Store;
   Pid   : Positive;
   Run_Id : Positive;
   Count  : Natural;
   First_Alias_Event : Positive := 1;
   Value  : Assessment;
   Raised : Boolean := False;

   procedure Set_Coverage (Basis_Points : Long_Long_Integer) is
   begin
      for Index in Value.Results.First_Index .. Value.Results.Last_Index loop
         if Value.Results (Index).Indicator = TST_03 then
            declare
               Result : Indicator_Result := Value.Results (Index);
            begin
               Result.Measurement :=
                 (Kind => Decimal_Value, Basis_Points => Basis_Points);
               Value.Results.Replace_Element (Index, Result);
               return;
            end;
         end if;
      end loop;
      raise Program_Error with "TST-03 fixture result is absent";
   end Set_Coverage;
begin
   if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
   if Ada.Directories.Exists (Relocated_Root) then Project_Tools.Files.Delete_Tree (Relocated_Root); end if;
   Ada_Quality.Storage.Open (Store, Path);
   Ada_Quality.Storage.Integrity.Check (Store);
   Assert (Ada_Quality.Storage.Integrity.Schema_Version (Store) = 5,
     "new databases use the current migrated schema version");
   Raised := False;
   begin
      declare
         Ignored : constant Positive :=
           Ada_Quality.Storage.Registry.Add_Project
             (Store, Root & "/missing-project");
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "invalid projects are rejected before identifier reservation");
   Pid := Ada_Quality.Storage.Registry.Add_Project (Store, Root);
   Assert (Pid = 1, "first persisted project ID is one");
   Ada.Directories.Create_Path (Relocated_Root);
   Project_Tools.Files.Write_Text_File
     (Relocated_Root & "/alire.toml", "name = ""relocated_fixture""" & ASCII.LF &
      "version = ""0.1.0""" & ASCII.LF);
   Ada_Quality.Storage.Registry.Relocate_Project
     (Store, Pid, Relocated_Root);
   Assert (To_String (Ada_Quality.Storage.Registry.Project (Store, Pid).Path) =
     Ada.Directories.Full_Name (Relocated_Root),
     "project relocation preserves the project identity and replaces its canonical path");
   Ada_Quality.Storage.Registry.Relocate_Project (Store, Pid, Root);
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   Assert (Ada_Quality.Storage.Registry.Project (Store, 1).Enabled,
     "project survives close and reopen");
   Ada_Quality.Storage.Registry.Add_Tag (Store, Pid, "ci");
   Ada_Quality.Storage.Registry.Add_Tag (Store, Pid, "core");
   Ada_Quality.Storage.Registry.Add_Tag (Store, Pid, "ci");
   Assert
     (To_String (Ada_Quality.Storage.Registry.Project (Store, Pid).Tags) = "ci,core" and then
      Ada_Quality.Storage.Registry.Has_Tag
        (Ada_Quality.Storage.Registry.Project (Store, Pid), "core"),
      "project tags are canonical, sorted, idempotent, and queryable");
   Ada_Quality.Storage.Registry.Remove_Tag (Store, Pid, "ci");
   Assert (To_String (Ada_Quality.Storage.Registry.Project (Store, Pid).Tags) = "core",
     "project tags can be removed without changing project identity");
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Assessments.Start
        (Store, Pid, "", "policy");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "invalid assessment identities are rejected before identifier reservation");
   Run_Id := Ada_Quality.Storage.Assessments.Start
     (Store, Pid, "source", "policy");
   Assert (Run_Id = 1, "first assessment ID is one");
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   Ada_Quality.Storage.Assessments.Recover (Store, Count);
   Assert (Count = 1, "recovery marks one abandoned running assessment");
   Assert (To_String
     (Ada_Quality.Storage.Assessments.History (Store).Last_Element.Status) = "interrupted",
     "recovered assessment is interrupted");
   Run_Id := Ada_Quality.Storage.Assessments.Start
     (Store, Pid, "source-2", "policy");
   Value.Id := Run_Id;
   Value.Project_Id := Pid;
   Value.Status := Assessment_Completed;
   Value.Source_Fingerprint := To_Unbounded_String ("source-2");
   Value.Policy_Fingerprint := To_Unbounded_String ("policy");
   Value.Toolchain_Fingerprint := To_Unbounded_String ("toolchain");
   Value.Executions.Append
     (Tool_Execution'(Tool => To_Unbounded_String ("fixture"),
      Command => To_Unbounded_String ("/bin/fixture"), Status => Tool_Completed,
      Exit_Code => 0, Output_Digest => To_Unbounded_String ("a430d84680aabd0b"),
      Output_Bytes => 4, Truncated => False));
   for Indicator in Indicator_Id loop
      Value.Results.Append
        (Indicator_Result'(Indicator => Indicator, Execution => Succeeded, Compliance => Pass,
          Applicable => True, Summary => To_Unbounded_String ("pass"),
          Evidence => To_Unbounded_String ("test"),
          Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>));
   end loop;
   Set_Coverage (9_100);
   declare
      First_Result : Indicator_Result := Value.Results.First_Element;
   begin
      First_Result.Findings.Append
        (Finding'(Indicator => STR_01, Rule => To_Unbounded_String ("storage-fixture"), Level => Low,
          Message => To_Unbounded_String ("persisted finding"),
          Relative_Path => To_Unbounded_String ("src/fixture.adb"), Line => 1,
          Fingerprint => To_Unbounded_String
            (Ada_Quality.Finding_Identity.Create
               (STR_01, "storage-fixture", "src/fixture.adb", "persisted finding"))));
      Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
   end;
   declare
      First_Result : Indicator_Result := Value.Results.First_Element;
   begin
      First_Result.Findings.Append (First_Result.Findings.First_Element);
      Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
      Assert (not Is_Publishable (Value),
        "duplicate stable finding identities are rejected before publication");
      First_Result.Findings.Delete_Last;
      Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
   end;
   declare
      First_Result : Indicator_Result := Value.Results.First_Element;
      Saved : constant Ada.Strings.Unbounded.Unbounded_String :=
        First_Result.Findings.First_Element.Fingerprint;
   begin
      First_Result.Findings.Reference (First_Result.Findings.First_Index).Fingerprint :=
        To_Unbounded_String
          (Ada_Quality.Finding_Identity.Create
             (SRC_01, "storage-fixture", "src/fixture.adb", "persisted finding"));
      Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
      Assert (not Is_Publishable (Value),
        "finding identities cannot contradict their structured indicator and payload");
      First_Result.Findings.Reference (First_Result.Findings.First_Index).Fingerprint := Saved;
      Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
   end;
   declare
      First_Result : Indicator_Result := Value.Results.First_Element;
      Saved : constant Ada.Strings.Unbounded.Unbounded_String :=
        First_Result.Findings.First_Element.Fingerprint;
   begin
      First_Result.Findings.Reference (First_Result.Findings.First_Index).Fingerprint :=
        To_Unbounded_String ("STR-01:storage-fixture:src/fixture.adb:persisted finding");
      Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
      Assert (not Is_Publishable (Value),
        "new lossless publication rejects delimiter-based legacy finding identities");
      First_Result.Findings.Reference (First_Result.Findings.First_Index).Fingerprint := Saved;
      Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
   end;
   Assert (Ada_Quality.Storage.Assessments.Publish (Store, Value) = Run_Id,
     "publication finalizes the pre-created running assessment");
   Ada_Quality.Storage.Assessments.Add_Alias (Store, Run_Id, "release-1");
   Assert
     (Ada_Quality.Storage.Assessments.Events (Store, Run_Id).Length = 3,
      "a completed assessment accepts an append-only alias event");
   First_Alias_Event :=
     Ada_Quality.Storage.Assessments.Events (Store, Run_Id).Last_Element.Id;
   Raised := False;
   begin
      Ada_Quality.Storage.Assessments.Add_Alias (Store, Run_Id, "release-1");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "assessment aliases are globally unique");
   Raised := False;
   begin
      Ada_Quality.Storage.Assessments.Add_Alias
        (Store, Run_Id, "Invalid Alias");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "assessment aliases use one canonical safe spelling");
   Ada_Quality.Storage.Assessments.Add_Alias
     (Store, Run_Id, "release-1.1");
   Assert
     (Ada_Quality.Storage.Assessments.Events
        (Store, Run_Id).Last_Element.Id = First_Alias_Event + 1,
      "rejected aliases do not consume persistent event identities");
   Assert (Ada_Quality.Storage.Assessments.Measurements
     (Store, Run_Id).Length = 33,
     "typed measurement rows are persisted for every indicator");
   Assert (Ada_Quality.Storage.Assessments.Executions
     (Store, Run_Id).Length = 1,
     "individual tool execution rows are persisted");
   Value.Id := 0;
   Value.Status := Assessment_Completed;
   Set_Coverage (9_200);
   declare
      Invalid : Assessment := Value;
      Rejected : Boolean := False;
   begin
      Invalid.Results.Delete_Last;
      begin
         declare
            Ignored : constant Positive :=
              Ada_Quality.Storage.Assessments.Publish (Store, Invalid);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Ada_Quality.Storage.Storage_Error => Rejected := True;
      end;
      Assert (Rejected, "invalid publication is rejected before identifier reservation");
   end;
   declare
      Regressed : Indicator_Result := Value.Results.First_Element;
      Escalated : Finding := Regressed.Findings.First_Element;
   begin
      Regressed.Compliance := Violation;
      Regressed.Summary := To_Unbounded_String ("regressed");
      Escalated.Level := High;
      Regressed.Findings.Replace_Element (Regressed.Findings.First_Index, Escalated);
      Value.Results.Replace_Element (Value.Results.First_Index, Regressed);
   end;
   Assert (Ada_Quality.Storage.Assessments.Publish (Store, Value) = 3,
     "direct publication remains available for imported terminal assessments");
   Raised := False;
   begin
      Ada_Quality.Storage.Integrity.Check
        (Store, (Max_Total_Rows => 1, Max_Text_Bytes => 268_435_456));
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "database integrity checking enforces its aggregate row limit while scanning");
   Raised := False;
   begin
      Ada_Quality.Storage.Integrity.Check
        (Store, (Max_Total_Rows => 2_500_000, Max_Text_Bytes => 1));
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "database integrity checking enforces its aggregate text limit while scanning");
   Ada_Quality.Storage.Integrity.Check (Store);
   Ada_Quality.Storage.Transfer.Compact (Store);
   Ada_Quality.Storage.Integrity.Check (Store);
   Assert (True, "transactional compaction preserves database integrity");
   declare
      Session : Ada_Quality.Reporting.Session;
   begin
      Ada_Quality.Storage.Close (Store);
      Ada_Quality.Reporting.Open (Session, Path);
      Assert
        (Ada_Quality.Reporting.Resolve_Assessment (Session, "release-1") = 2 and then
         Ada_Quality.Reporting.Resolve_Assessment (Session, "2") = 2 and then
         Ada_Quality.Reporting.Aliases (Session, 2).Length = 2,
         "reporting resolves numeric and human-readable assessment references");
      declare
         Stats : constant Ada_Quality.Reporting.Snapshot_Statistics :=
           Ada_Quality.Reporting.Statistics (Session);
         Status_JSON : constant String :=
           Ada_Quality.JSON_Reports.Render_Status (Session);
      begin
         Assert
           (Stats.Projects = 1 and then Stats.Assessments = 3 and then
            Stats.Events = 7 and then Stats.Total_Rows > Stats.Events and then Stats.Text_Bytes > 0,
            "reporting exposes bounded database row and text consumption");
         Assert
           (Ada.Strings.Fixed.Index (Status_JSON, """kind"":""portfolio-status""") > 0 and then
            Ada.Strings.Fixed.Index (Status_JSON, """latest_assessment_id"":3") > 0,
            "portfolio status JSON summarizes each project's latest assessment");
      end;
      declare
         Archive : constant String :=
           Ada_Quality.JSON_Reports.Render_Archive (Session);
         Pretty_Archive : constant String :=
           Ada_Quality.JSON_Reports.Render_Archive (Session, Pretty => True);
         Doc : Jsonlib.Documents.Document;
         Error : Jsonlib.Errors.Error_Info;
      begin
         Assert (Ada.Strings.Fixed.Index (Archive, """new-violation""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """increased-severity""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """schema_version"":2") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """comparisons""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """comparison-available""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """measurements""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """executions""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """output_digest""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """truncated""") > 0 and then
           Ada.Strings.Fixed.Index (Archive, """evidence"":""command=""") = 0,
           "archive JSON exports persisted evidence and derived regressions");
         Jsonlib.Parsers.Parse (Pretty_Archive, Doc, Error);
         Assert (not Jsonlib.Errors.Failed (Error),
           "streamed pretty archive output remains strict RFC 8259 JSON");
      end;
      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant String :=
                 Ada_Quality.JSON_Reports.Render_Archive
                   (Session, Max_Output_Bytes => 1);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Ada_Quality.Reporting.Limit_Error => Raised := True;
         end;
         Assert (Raised, "archive JSON fails closed when its output budget is exceeded");
      end;
      Ada_Quality.Reporting.Close (Session);
      Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   end;
   Set_Coverage (9_400);
   Assert (Ada_Quality.Storage.Assessments.Publish (Store, Value) = 4,
     "a third completed assessment is available for recovery-history integration");
   Run_Id := Ada_Quality.Storage.Assessments.Start
     (Store, Pid, "recovery-source", "policy");
   Assert (Run_Id = 5, "the recovery fixture leaves the newest assessment running");
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   Ada_Quality.Storage.Assessments.Recover (Store, Count);
   declare
      Runs : constant Ada_Quality.Storage.History_Vectors.Vector :=
        Ada_Quality.Storage.Assessments.History (Store, Pid);
      Trend : constant Ada_Quality.History.Trend_Vectors.Vector :=
        Ada_Quality.History.Metric_Trend
          (Runs, Ada_Quality.Storage.Assessments.Measurements (Store), TST_03);
      Selection : constant Ada_Quality.History.Comparison_Selection :=
        Ada_Quality.History.Select_Comparison (Runs);
   begin
      Assert (Count = 1 and then To_String (Runs.Last_Element.Status) = "interrupted",
        "recovery interrupts the abandoned latest assessment");
      Assert (Trend.Length = 3 and then Trend (Trend.First_Index).Value = 9_100 and then
        Trend (Trend.First_Index + 1).Value = 9_200 and then
        Trend (Trend.Last_Index).Value = 9_400,
        "recovery preserves three compatible completed metric points in chronological order");
      Assert (Ada_Quality.History.Baseline_Id (Runs, 4) = 3 and then
        Selection.Status = Ada_Quality.History.Current_Incomplete,
        "recovery preserves completed baseline selection and names latest comparison unavailability");
   end;
   Run_Id := Ada_Quality.Storage.Assessments.Start
     (Store, Pid, "interrupt-source", "policy");
   Ada_Quality.Storage.Testing.Inject_Next_Fault
     (Store, Ada_Quality.Storage.Testing.Assessment_Interruption);
   Raised := False;
   begin
      Ada_Quality.Storage.Assessments.Interrupt
        (Store, Run_Id, "faulted interruption");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then
     To_String
       (Ada_Quality.Storage.Assessments.History
          (Store, Pid).Last_Element.Status) = "running" and then
     Ada_Quality.Storage.Assessments.Events (Store, Run_Id).Length = 1,
     "an interruption commit fault rolls back both state and event");
   Ada_Quality.Storage.Assessments.Interrupt
     (Store, Run_Id, "controlled test interruption");
   Assert (To_String
     (Ada_Quality.Storage.Assessments.History
        (Store, Pid).Last_Element.Status) = "interrupted",
     "explicit interruption atomically closes a running assessment");
   Assert (Ada_Quality.Storage.Assessments.Events (Store, Run_Id).Length = 2,
     "explicit interruption records its terminal event");
   Ada_Quality.Storage.Assessments.Interrupt
     (Store, Run_Id, "duplicate interruption");
   Assert (Ada_Quality.Storage.Assessments.Events (Store, Run_Id).Length = 2,
     "interrupting an already terminal assessment is idempotent");
   declare
      First_Abandoned : constant Positive := Ada_Quality.Storage.Assessments.Start
        (Store, Pid, "multi-recovery-source-1", "policy");
      Second_Abandoned : constant Positive := Ada_Quality.Storage.Assessments.Start
        (Store, Pid, "multi-recovery-source-2", "policy");
      Following : Positive;
   begin
      Ada_Quality.Storage.Assessments.Recover (Store, Count);
      Assert
        (Count = 2 and then
         Ada_Quality.Storage.Assessments.Events
           (Store, First_Abandoned).Length = 2 and then
         Ada_Quality.Storage.Assessments.Events
           (Store, Second_Abandoned).Length = 2,
         "recovery allocates a distinct event identity for every running assessment");
      Following := Ada_Quality.Storage.Assessments.Start
        (Store, Pid, "post-recovery-source", "policy");
      Ada_Quality.Storage.Assessments.Interrupt
        (Store, Following, "post-recovery verification");
      Assert (Ada_Quality.Storage.Assessments.Events
        (Store, Following).Length = 2,
        "event allocation remains synchronized after multi-run recovery");
   end;
   Ada_Quality.Storage.Close (Store);
   declare
      Exit_Code : constant Natural :=
        Ada_Quality.CLI.Run
          (Ada_Quality.CLI_Arguments.Create
             ([To_Unbounded_String ("scan"),
               To_Unbounded_String ("--project"), To_Unbounded_String ("1"),
               To_Unbounded_String ("--changed-file"),
               To_Unbounded_String ("src/ada_quality.ads"),
               To_Unbounded_String ("--changed-file"),
               To_Unbounded_String ("src/ada_quality-cli.ads"),
               To_Unbounded_String ("--database"), To_Unbounded_String (Path),
               To_Unbounded_String ("--policy"),
               To_Unbounded_String (Root & "/quality-policy.toml")]));
   begin
      Assert
        (Exit_Code in 0 | 1,
         "injected CLI scans accept repeated changed-file arguments instead of ambient process state");
   end;
   Ada.Directories.Delete_File (Path);
   Project_Tools.Files.Delete_Tree (Relocated_Root);
end;
end Run_Storage_Test;
