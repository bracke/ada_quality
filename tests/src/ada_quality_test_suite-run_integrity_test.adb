separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_integrity_test justification=one-component-fixture-matrix
procedure Run_Integrity_Test is
begin
declare
   Path   : constant String := Fixture_Root & "/integrity_test.db";
   Fault_Path : constant String := Fixture_Root & "/creation_fault.db";
   Fault_Isolation_Path : constant String := Fixture_Root & "/unaffected_creation.db";
   Bad_Root : constant String := Fixture_Root & "/bad_manifest";
   Link_Root : constant String := Fixture_Root & "/project_link";
   Unicode_Root : constant String := Fixture_Root & "/ünicode_project";
   Root   : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Store  : Ada_Quality.Storage.Store;
   Locked_Store : Ada_Quality.Storage.Store;
   Missing_Store : Ada_Quality.Storage.Store;
   Unaffected_Store : Ada_Quality.Storage.Store;
   Value  : Assessment;
   Pid    : Positive;
   Run_Id : Positive;
   Count  : Natural;
   Raised : Boolean := False;
begin
   Project_Tools.Files.Delete_File_If_Present (Path);
   Project_Tools.Files.Delete_File_If_Present (Fault_Path);
   Ada_Quality.Storage.Testing.Inject_Next_Fault
     (Missing_Store, Ada_Quality.Storage.Testing.Schema_Creation);
   Ada_Quality.Storage.Open (Unaffected_Store, Fault_Isolation_Path);
   Assert (Ada_Quality.Storage.Is_Open (Unaffected_Store),
     "fault injection is scoped to one store instance");
   Ada_Quality.Storage.Close (Unaffected_Store);
   Project_Tools.Files.Delete_File_If_Present (Fault_Isolation_Path);
   Raised := False;
   begin
      Ada_Quality.Storage.Open (Missing_Store, Fault_Path);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then not Ada_Quality.Storage.Is_Open (Missing_Store),
     "a schema-creation commit fault closes the incomplete store");
   Project_Tools.Files.Delete_File_If_Present (Fault_Path);
   Raised := False;
   begin
      Ada_Quality.Storage.Open
        (Missing_Store, Fixture_Root & "/missing_storage.db", Create_If_Missing => False);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then not Ada_Quality.Storage.Is_Open (Missing_Store),
     "opening a missing database without creation fails closed");
   Raised := False;
   begin
      Ada_Quality.Storage.Check (Missing_Store);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "integrity checking a closed database is rejected");
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Schema_Version (Missing_Store);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "reading a schema version from a closed database fails safely");
   Raised := False;
   begin
      Ada_Quality.Storage.Testing.Set_Schema_Version (Missing_Store, 2);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "writing a schema version to a closed database fails safely");
   Ada_Quality.Storage.Open (Store, Path);
   Assert (Ada_Quality.Storage.Is_Open (Store), "created database reports open");
   Raised := False;
   begin
      Pid := Ada_Quality.Storage.Project (Store, 999).Id;
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "loading a missing project fails without leaking a read transaction");
   Raised := False;
   begin
      Pid := Ada_Quality.Storage.Add_Project (Store, Fixture_Root & "/missing_project_root");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "a missing project root cannot be registered");
   Project_Tools.Files.Delete_Tree (Link_Root);
   declare
      Link_Run : constant Ada_Quality.Execution.Run_Result := Ada_Quality.Execution.Run
        (Ada.Directories.Current_Directory, "ln",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Root),
             Project_Tools.Processes.Argument (Link_Root)]),
         Timeout_Seconds => 2, Maximum_Bytes => 128);
   begin
      Assert (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
        "project-root symlink fixture is created");
   end;
   Raised := False;
   begin
      Pid := Ada_Quality.Storage.Add_Project (Store, Link_Root);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "a symbolic-link project root cannot be registered");
   Project_Tools.Files.Delete_Tree (Link_Root);
   Raised := False;
   begin
      Ada_Quality.Storage.Open (Locked_Store, Path, Create_If_Missing => False);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "a second process-style handle observes the persistent lock conflict");
   Project_Tools.Files.Delete_Tree (Bad_Root);
   Ada.Directories.Create_Path (Bad_Root);
   Project_Tools.Files.Write_Text_File (Bad_Root & "/alire.toml", "name = ""broken""" & ASCII.LF);
   Raised := False;
   begin
      Pid := Ada_Quality.Storage.Add_Project (Store, Bad_Root);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "malformed Alire manifests are rejected by the registry");
   Project_Tools.Files.Delete_Tree (Bad_Root);
   Project_Tools.Files.Delete_Tree (Unicode_Root);
   Ada.Directories.Create_Path (Unicode_Root);
   Project_Tools.Files.Write_Text_File
     (Unicode_Root & "/alire.toml", "name = ""unicode_project""" & ASCII.LF &
      "version = ""0.1.0""" & ASCII.LF);
   declare
      Unicode_Id : constant Positive := Ada_Quality.Storage.Add_Project (Store, Unicode_Root);
   begin
      Assert (To_String (Ada_Quality.Storage.Project (Store, Unicode_Id).Path) = Unicode_Root,
        "canonical project paths round-trip valid UTF-8");
      Ada_Quality.Storage.Remove_Project (Store, Unicode_Id);
   end;
   Project_Tools.Files.Delete_Tree (Unicode_Root);
   Pid := Ada_Quality.Storage.Add_Project (Store, Root);
   Raised := False;
   begin
      declare
         Duplicate_Id : constant Positive := Ada_Quality.Storage.Add_Project (Store, Root);
         pragma Unreferenced (Duplicate_Id);
      begin
         null;
      end;
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "duplicate active project registration is rejected");
   Raised := False;
   begin
      Ada_Quality.Storage.Set_Enabled (Store, 999, True);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "updating a missing project is rejected");
   Ada_Quality.Storage.Set_Enabled (Store, Pid, False);
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "disabled", "policy");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "disabled projects cannot start assessments");
   Ada_Quality.Storage.Set_Enabled (Store, Pid, True);
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "", "policy");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then Ada_Quality.Storage.History (Store, Pid).Is_Empty,
     "assessment start rejects identities that its integrity decoder cannot read");
   Ada_Quality.Storage.Testing.Inject_Next_Fault
     (Store, Ada_Quality.Storage.Testing.Assessment_Start);
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "faulted-source", "policy");
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then Ada_Quality.Storage.History (Store, Pid).Is_Empty,
     "an assessment-start commit fault rolls back both run and event");
   Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source", "policy");
   Value.Id := Run_Id;
   Value.Project_Id := Pid;
   Value.Status := Assessment_Completed;
   Value.Source_Fingerprint := To_Unbounded_String ([1 => Character'Val (255)]);
   Value.Policy_Fingerprint := To_Unbounded_String ("policy");
   Value.Toolchain_Fingerprint := To_Unbounded_String ("toolchain");
   for Indicator in Indicator_Id loop
      Value.Results.Append
        (Indicator_Result'(Indicator => Indicator, Execution => Succeeded, Compliance => Pass,
          Applicable => True, Summary => To_Unbounded_String ("pass"),
          Evidence => To_Unbounded_String ("test"),
          Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>));
   end loop;
   Value.Status := Assessment_Running;
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Publish (Store, Value);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "running assessments cannot be published as terminal evidence");
   Value.Status := Assessment_Completed;
   declare
      Saved : constant Indicator_Result := Value.Results.Last_Element;
   begin
      Value.Results.Delete_Last;
      Raised := False;
      begin
         Run_Id := Ada_Quality.Storage.Publish (Store, Value);
      exception
         when Ada_Quality.Storage.Storage_Error => Raised := True;
      end;
      Assert (Raised, "partial result sets cannot be published");
      Value.Results.Append (Saved);
   end;
   declare
      Saved : constant Indicator_Result := Value.Results.Last_Element;
   begin
      Value.Results.Replace_Element (Value.Results.Last_Index, Value.Results.First_Element);
      Raised := False;
      begin
         Run_Id := Ada_Quality.Storage.Publish (Store, Value);
      exception
         when Ada_Quality.Storage.Storage_Error => Raised := True;
      end;
      Assert (Raised, "duplicate indicator results cannot be published");
      Value.Results.Replace_Element (Value.Results.Last_Index, Saved);
   end;
   declare
      Saved : constant Indicator_Result := Value.Results.First_Element;
      Bad   : Indicator_Result := Saved;
   begin
      Bad.Execution := Blocked;
      Value.Results.Replace_Element (Value.Results.First_Index, Bad);
      Raised := False;
      begin
         Run_Id := Ada_Quality.Storage.Publish (Store, Value);
      exception
         when Ada_Quality.Storage.Storage_Error => Raised := True;
      end;
      Assert (Raised, "internally inconsistent indicator results cannot be published");
      Value.Results.Replace_Element (Value.Results.First_Index, Saved);
   end;
   begin
      Run_Id := Ada_Quality.Storage.Publish (Store, Value);
   exception
      when Ada_Quality.Storage.Storage_Error | Ada.Strings.UTF_Encoding.Encoding_Error =>
         Raised := True;
   end;
   Assert (Raised, "invalid encoded evidence injects a publication failure");
   Assert (To_String (Ada_Quality.Storage.History (Store).Last_Element.Status) = "running",
     "failed publication rolls back the assessment state");
   Assert (Ada_Quality.Storage.Results (Store, Run_Id).Length = 0,
     "failed publication leaves no partial results");
   Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 1,
     "failed publication leaves only the committed start event");
   Value.Source_Fingerprint := To_Unbounded_String ("source");
   Ada_Quality.Storage.Testing.Inject_Next_Fault
     (Store, Ada_Quality.Storage.Testing.Assessment_Publication);
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Publish (Store, Value);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then Ada_Quality.Storage.Results (Store, Run_Id).Is_Empty and then
     To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "running",
     "a publication commit fault preserves the running record without partial evidence");
   Assert (Ada_Quality.Storage.Publish (Store, Value) = Run_Id,
     "a valid publication succeeds after rollback");
   Raised := False;
   begin
      Run_Id := Ada_Quality.Storage.Publish (Store, Value);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "terminal assessments are immutable");
   Assert (Ada_Quality.Storage.Results (Store, Run_Id).Length = 33,
     "immutable assessment retains its complete result set");
   Value.Id := 0;
   Value.Status := Assessment_Interrupted;
   declare
      Imported_Id : constant Positive := Ada_Quality.Storage.Publish (Store, Value);
      pragma Unreferenced (Imported_Id);
   begin
      null;
   end;
   Assert (To_String (Ada_Quality.Storage.History (Store).Last_Element.Status) = "interrupted",
     "imported interrupted assessments retain terminal status");
   Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source-2", "policy");
   Ada_Quality.Storage.Testing.Inject_Next_Fault
     (Store, Ada_Quality.Storage.Testing.Assessment_Recovery);
   Raised := False;
   begin
      Ada_Quality.Storage.Recover (Store, Count);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then Ada_Quality.Storage.Events (Store, Run_Id).Length = 1 and then
     To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "running",
     "a recovery commit fault rolls back state and recovery event together");
   Ada_Quality.Storage.Recover (Store, Count);
   Assert (Count = 1, "recovery handles the abandoned running assessment");
   Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
     "recovery atomically records an event");
   Ada_Quality.Storage.Recover (Store, Count);
   Assert (Count = 0 and then Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
     "recovery is idempotent");
   Ada_Quality.Storage.Testing.Set_Schema_Version (Store, 1);
   Ada_Quality.Storage.Close (Store);
   Ada_Quality.Storage.Testing.Inject_Next_Fault
     (Store, Ada_Quality.Storage.Testing.Schema_Migration);
   Raised := False;
   begin
      Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then not Ada_Quality.Storage.Is_Open (Store),
     "a migration commit fault leaves the database closed at its prior version");
   Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   Assert (Ada_Quality.Storage.Schema_Version (Store) = 3,
     "opening a version-1 database runs the explicit migration to version 3");
   Ada_Quality.Storage.Testing.Set_Schema_Version (Store, 99);
   Raised := False;
   begin
      Ada_Quality.Storage.Check (Store);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "integrity checking rejects an unsupported schema version");
   Ada_Quality.Storage.Close (Store);
   Raised := False;
   begin
      Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised and then not Ada_Quality.Storage.Is_Open (Store),
     "unsupported schema versions fail closed");
   Project_Tools.Files.Delete_File_If_Present (Path);
end;
end Run_Integrity_Test;
