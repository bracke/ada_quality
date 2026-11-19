with Ada.Calendar;
separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=set_coverage owner=core expires=2099-12-31 justification=one-component-fixture-matrix
procedure Run_Storage_Test is
begin
declare
   Path  : constant String := Fixture_Root & "/storage_test.db";
   Backup_Path : constant String := Fixture_Root & "/storage_test.backup";
   Export_Path : constant String := Fixture_Root & "/storage_test.export";
   Restored_Path : constant String := Fixture_Root & "/storage_test_restored.db";
   Imported_Path : constant String := Fixture_Root & "/storage_test_imported.db";
   Retention_Path : constant String := Fixture_Root & "/storage_test_retention.export";
   Retention_Restore_Path : constant String := Fixture_Root & "/storage_test_retention_restore.db";
   Merge_Path : constant String := Fixture_Root & "/storage_test_merge.db";
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
   if Ada.Directories.Exists (Backup_Path) then Project_Tools.Files.Delete_Tree (Backup_Path); end if;
   if Ada.Directories.Exists (Export_Path) then Ada.Directories.Delete_File (Export_Path); end if;
   if Ada.Directories.Exists (Restored_Path) then Ada.Directories.Delete_File (Restored_Path); end if;
   if Ada.Directories.Exists (Imported_Path) then Ada.Directories.Delete_File (Imported_Path); end if;
   if Ada.Directories.Exists (Retention_Path) then Ada.Directories.Delete_File (Retention_Path); end if;
   if Ada.Directories.Exists (Retention_Restore_Path) then
      Ada.Directories.Delete_File (Retention_Restore_Path);
   end if;
   if Ada.Directories.Exists (Merge_Path) then Ada.Directories.Delete_File (Merge_Path); end if;
   if Ada.Directories.Exists (Relocated_Root) then Project_Tools.Files.Delete_Tree (Relocated_Root); end if;
   Ada_Quality.Storage.Open (Store, Path);
   Ada_Quality.Storage.Check (Store);
   Assert (Ada_Quality.Storage.Schema_Version (Store) = 5,
     "new databases use the current migrated schema version");
   Raised := False;
   begin
      declare
         Ignored : constant Positive :=
           Ada_Quality.Storage.Add_Project (Store, Root & "/missing-project");
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "invalid projects are rejected before identifier reservation");
   Pid := Ada_Quality.Storage.Add_Project (Store, Root);
   Assert (Pid = 1, "first persisted project ID is one");
   Ada.Directories.Create_Path (Relocated_Root);
   Project_Tools.Files.Write_Text_File
     (Relocated_Root & "/alire.toml", "name = ""relocated_fixture""" & ASCII.LF &
      "version = ""0.1.0""" & ASCII.LF);
   Ada_Quality.Storage.Relocate_Project (Store, Pid, Relocated_Root);
   Assert (To_String (Ada_Quality.Storage.Project (Store, Pid).Path) =
     Ada.Directories.Full_Name (Relocated_Root),
     "project relocation preserves the project identity and replaces its canonical path");
   Ada_Quality.Storage.Relocate_Project (Store, Pid, Root);
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   Assert (Ada_Quality.Storage.Project (Store, 1).Enabled, "project survives close and reopen");
   Ada_Quality.Storage.Add_Project_Tag (Store, Pid, "ci");
   Ada_Quality.Storage.Add_Project_Tag (Store, Pid, "core");
   Ada_Quality.Storage.Add_Project_Tag (Store, Pid, "ci");
   Assert
     (To_String (Ada_Quality.Storage.Project (Store, Pid).Tags) = "ci,core" and then
      Ada_Quality.Storage.Has_Project_Tag (Ada_Quality.Storage.Project (Store, Pid), "core"),
      "project tags are canonical, sorted, idempotent, and queryable");
   Ada_Quality.Storage.Remove_Project_Tag (Store, Pid, "ci");
   Assert (To_String (Ada_Quality.Storage.Project (Store, Pid).Tags) = "core",
     "project tags can be removed without changing project identity");
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "", "policy");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "invalid assessment identities are rejected before identifier reservation");
   Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source", "policy");
   Assert (Run_Id = 1, "first assessment ID is one");
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   Ada_Quality.Storage.Recover (Store, Count);
   Assert (Count = 1, "recovery marks one abandoned running assessment");
   Assert (To_String (Ada_Quality.Storage.History (Store).Last_Element.Status) = "interrupted",
     "recovered assessment is interrupted");
   Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source-2", "policy");
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
   Assert (Ada_Quality.Storage.Publish (Store, Value) = Run_Id,
     "publication finalizes the pre-created running assessment");
   Ada_Quality.Storage.Add_Assessment_Alias (Store, Run_Id, "release-1");
   Assert
     (Ada_Quality.Storage.Events (Store, Run_Id).Length = 3,
      "a completed assessment accepts an append-only alias event");
   First_Alias_Event := Ada_Quality.Storage.Events (Store, Run_Id).Last_Element.Id;
   Raised := False;
   begin
      Ada_Quality.Storage.Add_Assessment_Alias (Store, Run_Id, "release-1");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "assessment aliases are globally unique");
   Raised := False;
   begin
      Ada_Quality.Storage.Add_Assessment_Alias (Store, Run_Id, "Invalid Alias");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "assessment aliases use one canonical safe spelling");
   Ada_Quality.Storage.Add_Assessment_Alias (Store, Run_Id, "release-1.1");
   Assert
     (Ada_Quality.Storage.Events (Store, Run_Id).Last_Element.Id = First_Alias_Event + 1,
      "rejected aliases do not consume persistent event identities");
   Assert (Ada_Quality.Storage.Measurements (Store, Run_Id).Length = 33,
     "typed measurement rows are persisted for every indicator");
   Assert (Ada_Quality.Storage.Executions (Store, Run_Id).Length = 1,
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
            Ignored : constant Positive := Ada_Quality.Storage.Publish (Store, Invalid);
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
   Assert (Ada_Quality.Storage.Publish (Store, Value) = 3,
     "direct publication remains available for imported terminal assessments");
   Raised := False;
   begin
      Ada_Quality.Storage.Check
        (Store, (Max_Total_Rows => 1, Max_Text_Bytes => 268_435_456));
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "database integrity checking enforces its aggregate row limit while scanning");
   Raised := False;
   begin
      Ada_Quality.Storage.Check
        (Store, (Max_Total_Rows => 2_500_000, Max_Text_Bytes => 1));
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "database integrity checking enforces its aggregate text limit while scanning");
   Ada_Quality.Storage.Check (Store);
   Ada_Quality.Storage.Compact (Store);
   Ada_Quality.Storage.Check (Store);
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
         Status_JSON : constant String := Ada_Quality.JSON.Render_Status (Session);
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
         Archive : constant String := Ada_Quality.JSON.Render_Archive (Session);
         Pretty_Archive : constant String :=
           Ada_Quality.JSON.Render_Archive (Session, Pretty => True);
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
                 Ada_Quality.JSON.Render_Archive (Session, Max_Output_Bytes => 1);
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
   Assert (Ada_Quality.Storage.Publish (Store, Value) = 4,
     "a third completed assessment is available for recovery-history integration");
   Run_Id := Ada_Quality.Storage.Start_Assessment
     (Store, Pid, "recovery-source", "policy");
   Assert (Run_Id = 5, "the recovery fixture leaves the newest assessment running");
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   Ada_Quality.Storage.Recover (Store, Count);
   declare
      Runs : constant Ada_Quality.Storage.History_Vectors.Vector :=
        Ada_Quality.Storage.History (Store, Pid);
      Trend : constant Ada_Quality.History.Trend_Vectors.Vector :=
        Ada_Quality.History.Metric_Trend
          (Runs, Ada_Quality.Storage.Measurements (Store), TST_03);
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
   Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "interrupt-source", "policy");
   Ada_Quality.Storage.Testing.Inject_Next_Fault
     (Store, Ada_Quality.Storage.Testing.Assessment_Interruption);
   Raised := False;
   begin
      Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, "faulted interruption");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then
     To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "running" and then
     Ada_Quality.Storage.Events (Store, Run_Id).Length = 1,
     "an interruption commit fault rolls back both state and event");
   Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, "controlled test interruption");
   Assert (To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "interrupted",
     "explicit interruption atomically closes a running assessment");
   Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
     "explicit interruption records its terminal event");
   Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, "duplicate interruption");
   Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
     "interrupting an already terminal assessment is idempotent");
   declare
      First_Abandoned : constant Positive := Ada_Quality.Storage.Start_Assessment
        (Store, Pid, "multi-recovery-source-1", "policy");
      Second_Abandoned : constant Positive := Ada_Quality.Storage.Start_Assessment
        (Store, Pid, "multi-recovery-source-2", "policy");
      Following : Positive;
   begin
      Ada_Quality.Storage.Recover (Store, Count);
      Assert
        (Count = 2 and then
         Ada_Quality.Storage.Events (Store, First_Abandoned).Length = 2 and then
         Ada_Quality.Storage.Events (Store, Second_Abandoned).Length = 2,
         "recovery allocates a distinct event identity for every running assessment");
      Following := Ada_Quality.Storage.Start_Assessment
        (Store, Pid, "post-recovery-source", "policy");
      Ada_Quality.Storage.Interrupt_Assessment (Store, Following, "post-recovery verification");
      Assert (Ada_Quality.Storage.Events (Store, Following).Length = 2,
        "event allocation remains synchronized after multi-run recovery");
   end;
   Ada_Quality.Storage.Backup (Store, Backup_Path);
   Ada_Quality.Storage.Export (Store, Export_Path);
   Assert (Ada.Directories.Exists (Backup_Path & "/manifest.dbbackup") and then
     Ada.Directories.Exists (Export_Path),
     "verified physical backup and logical export artifacts are created");
   Raised := False;
   begin
      Ada_Quality.Storage.Export (Store, Export_Path);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "database artifacts are never overwritten implicitly");
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Restore (Backup_Path, Restored_Path);
   Ada_Quality.Storage.Open (Store, Restored_Path, Create_If_Missing => False);
   Ada_Quality.Storage.Check (Store);
   Assert (Ada_Quality.Storage.Projects (Store).Length = 1 and then
     Ada_Quality.Storage.History (Store, Pid).Length > 0,
     "a restored backup retains registry and assessment history");
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Import (Export_Path, Imported_Path);
   Ada_Quality.Storage.Open (Store, Imported_Path, Create_If_Missing => False);
   Ada_Quality.Storage.Check (Store);
   Assert
     (Ada_Quality.Storage.Projects (Store).Length = 1 and then
      Ada_Quality.Storage.History (Store, Pid).Length > 0,
      "a logical import retains registry and assessment history");
   declare
      Before_Count : constant Natural := Natural (Ada_Quality.Storage.History (Store, Pid).Length);
      Removed : Natural;
      use type Ada.Calendar.Time;
   begin
      Assert
        (Natural
           (Ada_Quality.Storage.Retention_Candidates
              (Store, Ada.Calendar.Clock + 86_400.0, Keep => 2).Length) = Before_Count - 2,
         "retention preview identifies exactly the rows a matching archive will remove");
      Ada_Quality.Storage.Archive_And_Prune
        (Store, Retention_Path, Ada.Calendar.Clock + 86_400.0, Keep => 2, Removed => Removed);
      Ada_Quality.Storage.Check (Store);
      Assert
        (Removed = Before_Count - 2 and then
         Ada_Quality.Storage.History (Store, Pid).Length = 2 and then
         Ada.Directories.Exists (Retention_Path),
         "retention archives the complete database before keeping the newest terminal assessments");
      Ada_Quality.Storage.Close (Store);
      Ada_Quality.Storage.Import (Retention_Path, Retention_Restore_Path);
      Ada_Quality.Storage.Open (Store, Retention_Restore_Path, Create_If_Missing => False);
      Ada_Quality.Storage.Check (Store);
      Assert
        (Natural (Ada_Quality.Storage.History (Store, Pid).Length) = Before_Count,
         "the verified retention archive restores every assessment removed from the live database");
   end;
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Open (Store, Merge_Path);
   declare Added_Projects, Added_Assessments, Again_Projects, Again_Assessments : Natural; begin
      Ada_Quality.Storage.Merge
        (Store, Retention_Restore_Path, Added_Projects, Added_Assessments);
      Ada_Quality.Storage.Merge
        (Store, Retention_Restore_Path, Again_Projects, Again_Assessments);
      Assert
        (Added_Projects = 1 and then Added_Assessments = 3 and then
         Again_Projects = 0 and then Again_Assessments = 0 and then
         To_String (Ada_Quality.Storage.Project (Store, 1).Tags) = "core",
         "database merge remaps projects, preserves tags, imports completed evidence, and deduplicates retries");
   end;
   Ada_Quality.Storage.Close (Store);
   Ada.Directories.Delete_File (Path);
   Ada.Directories.Delete_File (Export_Path);
   Ada.Directories.Delete_File (Restored_Path);
   Ada.Directories.Delete_File (Imported_Path);
   Ada.Directories.Delete_File (Retention_Path);
   Ada.Directories.Delete_File (Retention_Restore_Path);
   Ada.Directories.Delete_File (Merge_Path);
   Project_Tools.Files.Delete_Tree (Backup_Path);
   Project_Tools.Files.Delete_Tree (Relocated_Root);
end;
end Run_Storage_Test;
