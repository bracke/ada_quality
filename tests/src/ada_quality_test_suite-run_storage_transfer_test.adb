with Ada.Calendar;

separate (Ada_Quality_Test_Suite)
procedure Run_Storage_Transfer_Test is
   Database_Path : constant String := Fixture_Root & "/transfer_source.db";
   Backup_Path : constant String := Fixture_Root & "/transfer.backup";
   Export_Path : constant String := Fixture_Root & "/transfer.export";
   Restored_Path : constant String := Fixture_Root & "/transfer_restored.db";
   Imported_Path : constant String := Fixture_Root & "/transfer_imported.db";
   Retention_Path : constant String := Fixture_Root & "/transfer_retention.export";
   Retention_Restore_Path : constant String :=
     Fixture_Root & "/transfer_retention_restored.db";
   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward
       (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Store : Ada_Quality.Storage.Store;
   Project_Id : Positive;
   Value : Assessment;
   Raised : Boolean := False;

   procedure Remove_Fixtures is
   begin
      Project_Tools.Files.Delete_File_If_Present (Database_Path);
      Project_Tools.Files.Delete_File_If_Present (Export_Path);
      Project_Tools.Files.Delete_File_If_Present (Restored_Path);
      Project_Tools.Files.Delete_File_If_Present (Imported_Path);
      Project_Tools.Files.Delete_File_If_Present (Retention_Path);
      Project_Tools.Files.Delete_File_If_Present (Retention_Restore_Path);
      if Ada.Directories.Exists (Backup_Path) then
         Project_Tools.Files.Delete_Tree (Backup_Path);
      end if;
   end Remove_Fixtures;
begin
   Remove_Fixtures;
   Ada_Quality.Storage.Open (Store, Database_Path);
   Project_Id := Ada_Quality.Storage.Registry.Add_Project (Store, Root);
   Value.Project_Id := Project_Id;
   Value.Project_Path := To_Unbounded_String (Root);
   Value.Status := Assessment_Completed;
   Value.Policy_Fingerprint := To_Unbounded_String ("transfer-policy");
   Value.Toolchain_Fingerprint := To_Unbounded_String ("transfer-toolchain");
   for Indicator in Indicator_Id loop
      Value.Results.Append
        (Indicator_Result'
         (Indicator => Indicator, Execution => Succeeded, Compliance => Pass,
          Applicable => True, Summary => To_Unbounded_String ("transfer"),
          Evidence => Null_Unbounded_String,
          Measurement => (Kind => Boolean_Value, Boolean_Data => True),
          Findings => <>));
   end loop;
   for Number in 1 .. 3 loop
      Value.Source_Fingerprint :=
        To_Unbounded_String ("transfer-source-" & Number'Image);
      declare
         Published : constant Positive :=
           Ada_Quality.Storage.Assessments.Publish (Store, Value);
         pragma Unreferenced (Published);
      begin
         null;
      end;
   end loop;

   Ada_Quality.Storage.Transfer.Backup (Store, Backup_Path);
   Ada_Quality.Storage.Transfer.Export (Store, Export_Path);
   Assert
     (Ada.Directories.Exists (Backup_Path & "/manifest.dbbackup") and then
      Ada.Directories.Exists (Export_Path),
      "physical backup and logical export artifacts are created");
   begin
      Ada_Quality.Storage.Transfer.Export (Store, Export_Path);
   exception
      when Ada_Quality.Storage.Storage_Error => Raised := True;
   end;
   Assert (Raised, "database transfer artifacts are never overwritten implicitly");
   Ada_Quality.Storage.Close (Store);

   Ada_Quality.Storage.Transfer.Restore (Backup_Path, Restored_Path);
   Ada_Quality.Storage.Open (Store, Restored_Path, Create_If_Missing => False);
   Ada_Quality.Storage.Integrity.Check (Store);
   Assert
     (Ada_Quality.Storage.Assessments.History (Store, Project_Id).Length = 3,
      "a restored backup retains assessment history");
   Ada_Quality.Storage.Close (Store);

   Ada_Quality.Storage.Transfer.Import (Export_Path, Imported_Path);
   Ada_Quality.Storage.Open (Store, Imported_Path, Create_If_Missing => False);
   Ada_Quality.Storage.Integrity.Check (Store);
   declare
      Removed : Natural;
      use type Ada.Calendar.Time;
   begin
      declare
         Candidates : constant Ada_Quality.Storage.History_Vectors.Vector :=
           Ada_Quality.Storage.Transfer.Retention_Candidates
             (Store, Ada.Calendar.Clock + 86_400.0, Keep => 1);
      begin
         Assert
           (Candidates.Length = 2 and then
            Candidates.First_Element.Id < Candidates.Last_Element.Id,
            "retention preview identifies candidates in stable history order");
      end;
      Ada_Quality.Storage.Transfer.Archive_And_Prune
        (Store, Retention_Path, Ada.Calendar.Clock + 86_400.0,
         Keep => 1, Removed => Removed);
      Assert
        (Removed = 2 and then
         Ada_Quality.Storage.Assessments.History (Store, Project_Id).Length = 1,
         "retention archives before pruning to the requested history size");
   end;
   Ada_Quality.Storage.Close (Store);

   Ada_Quality.Storage.Transfer.Import
     (Retention_Path, Retention_Restore_Path);
   Ada_Quality.Storage.Open
     (Store, Retention_Restore_Path, Create_If_Missing => False);
   Ada_Quality.Storage.Integrity.Check (Store);
   Assert
     (Ada_Quality.Storage.Assessments.History (Store, Project_Id).Length = 3,
      "the retention archive restores all pruned assessments");
   Ada_Quality.Storage.Close (Store);
   Remove_Fixtures;
end Run_Storage_Transfer_Test;
