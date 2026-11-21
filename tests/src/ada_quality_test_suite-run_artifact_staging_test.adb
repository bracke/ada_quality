with Ada_Quality.Artifact_Staging;

separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_artifact_staging_test owner=aq expires=2027-11-21 justification=staging-fixtures
procedure Run_Artifact_Staging_Test is
   Root          : constant String := Fixture_Root & "/artifact-staging";
   Private_Path  : constant String := Root & "/signing.key";
   Public        : constant String := Root & "/signing.pub";
   Export        : constant String := Root & "/database.export";
   Unsigned      : constant String := Root & "/unsigned.export";
   Backup        : constant String := Root & "/database.backup";
   Staged_Export : constant String := Root & "/staged.export";
   Staged_Backup : constant String := Root & "/staged.backup";
   Original      : constant String := "native logical export fixture" & ASCII.LF;
   Raised        : Boolean := False;
begin
   if Ada.Directories.Exists (Root) then Project_Tools.Files.Delete_Tree (Root); end if;
   Ada.Directories.Create_Path (Backup & "/nested");
   Project_Tools.Files.Write_Raw_File (Export, Original);
   Project_Tools.Files.Write_Raw_File (Unsigned, Original);
   Project_Tools.Files.Write_Raw_File
     (Backup & "/manifest.dbbackup", "backup manifest fixture" & ASCII.LF);
   Project_Tools.Files.Write_Raw_File (Backup & "/nested/evidence", "nested fixture" & ASCII.LF);
   Ada_Quality.Artifact_Signing.Generate_Keypair (Private_Path, Public);
   Ada_Quality.Artifact_Signing.Sign (Export, Private_Path);
   Ada_Quality.Artifact_Signing.Sign (Backup, Private_Path);
   Ada_Quality.Artifact_Staging.Copy (Export, Staged_Export);
   Ada_Quality.Artifact_Staging.Copy (Backup, Staged_Backup);
   declare
      Linked_Export : constant String := Root & "/linked.export";
      Unsafe_Link   : constant String := Backup & "/unsafe-link";
      Link_Run      : Ada_Quality.Execution.Run_Result := Ada_Quality.Execution.Run
        (Root, "ln",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Export),
             Project_Tools.Processes.Argument (Linked_Export)]),
         Timeout_Seconds => 2, Maximum_Bytes => 128);
   begin
      Assert
        (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
         "artifact staging root-symlink fixture is created");
      Raised := False;
      begin
         Ada_Quality.Artifact_Staging.Copy (Linked_Export, Root & "/rejected-linked.export");
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "artifact staging refuses linked source roots");
      Raised := False;
      begin
         Ada_Quality.Artifact_Signing.Verify (Linked_Export, Public);
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "direct verification refuses linked artifact roots");

      Link_Run := Ada_Quality.Execution.Run
        (Root, "ln",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Export),
             Project_Tools.Processes.Argument (Unsafe_Link)]),
         Timeout_Seconds => 2, Maximum_Bytes => 128);
      Assert
        (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
         "artifact staging entry-symlink fixture is created");
      Raised := False;
      begin
         Ada_Quality.Artifact_Staging.Copy (Backup, Root & "/rejected-linked.backup");
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "artifact staging refuses linked directory entries");
      declare
         Linked_Manifest_Backup : constant String := Root & "/linked-manifest.backup";
      begin
         Ada.Directories.Create_Path (Linked_Manifest_Backup);
         Link_Run := Ada_Quality.Execution.Run
           (Root, "ln",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("-s"),
                Project_Tools.Processes.Argument (Export),
                Project_Tools.Processes.Argument
                  (Linked_Manifest_Backup & "/manifest.dbbackup")]),
            Timeout_Seconds => 2, Maximum_Bytes => 128);
         Assert
           (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
            "linked backup-manifest fixture is created");
         Raised := False;
         begin
            Ada_Quality.Artifact_Signing.Verify (Linked_Manifest_Backup, Public);
         exception
            when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
         end;
         Assert (Raised, "verification opens backup manifests through a no-follow descriptor");
      end;
      Assert
        (not Ada.Directories.Exists (Root & "/rejected-linked.backup"),
         "failed directory staging removes its partial destination");
      Ada.Directories.Delete_File (Unsafe_Link);

      Raised := False;
      begin
         Ada_Quality.Artifact_Staging.Copy (Unsigned, Root & "/rejected-unsigned.export");
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert
        (Raised and then not Ada.Directories.Exists (Root & "/rejected-unsigned.export"),
         "missing signature staging removes its copied artifact");

      Raised := False;
      begin
         Ada_Quality.Artifact_Staging.Copy
           (Export, Root & "/missing-parent/rejected.export");
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert
        (Raised and then not Ada.Directories.Exists (Root & "/missing-parent"),
         "artifact staging reports a destination whose parent is unavailable");

      Raised := False;
      begin
         Ada_Quality.Artifact_Staging.Copy (Export, Staged_Export);
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "artifact staging refuses an existing destination");

      declare
         Collision : constant String := Root & "/collision.export";
      begin
         Project_Tools.Files.Write_Raw_File (Collision & ".sig", "sentinel" & ASCII.LF);
         Raised := False;
         begin
            Ada_Quality.Artifact_Staging.Copy (Export, Collision);
         exception
            when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
         end;
         Assert
           (Raised and then not Ada.Directories.Exists (Collision) and then
            Project_Tools.Files.Read_Raw_File (Collision & ".sig") = "sentinel" & ASCII.LF,
            "artifact staging preserves a pre-existing destination sidecar");
         Ada.Directories.Delete_File (Collision & ".sig");
      end;

      Ada.Directories.Create_Directory (Unsigned & ".sig");
      Raised := False;
      begin
         Ada_Quality.Artifact_Staging.Copy (Unsigned, Root & "/rejected-sidecar.export");
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert
        (Raised and then not Ada.Directories.Exists (Root & "/rejected-sidecar.export"),
         "artifact staging rejects a directory in place of a signature sidecar");
      Ada.Directories.Delete_Directory (Unsigned & ".sig");

      declare
         Special_Root  : constant String := Root & "/special-root";
         Special_Child : constant String := Backup & "/special-child";
      begin
         for Path of Project_Tools.Processes.Argument_Items'
           ([Project_Tools.Processes.Argument (Special_Root),
             Project_Tools.Processes.Argument (Special_Child)])
         loop
            Link_Run := Ada_Quality.Execution.Run
              (Root, "mkfifo",
               Project_Tools.Processes.Arguments
                 ([Path]),
               Timeout_Seconds => 2, Maximum_Bytes => 128);
            Assert
              (Link_Run.Status = Ada_Quality.Execution.Completed and then
               Link_Run.Exit_Code = 0,
               "artifact staging special-file fixture is created");
         end loop;
         Raised := False;
         begin
            Ada_Quality.Artifact_Staging.Copy (Special_Root, Root & "/rejected-special-root");
         exception
            when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
         end;
         Assert (Raised, "artifact staging refuses a special-file root");
         Raised := False;
         begin
            Ada_Quality.Artifact_Staging.Copy (Backup, Root & "/rejected-special-child");
         exception
            when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
         end;
         Assert
           (Raised and then not Ada.Directories.Exists (Root & "/rejected-special-child"),
            "artifact staging refuses and rolls back a special directory entry");
         for Path of Project_Tools.Processes.Argument_Items'
           ([Project_Tools.Processes.Argument (Special_Root),
             Project_Tools.Processes.Argument (Special_Child)])
         loop
            Link_Run := Ada_Quality.Execution.Run
              (Root, "unlink", Project_Tools.Processes.Arguments ([Path]),
               Timeout_Seconds => 2, Maximum_Bytes => 128);
            Assert
              (Link_Run.Status = Ada_Quality.Execution.Completed and then
               Link_Run.Exit_Code = 0,
               "artifact staging special-file fixture is removed");
         end loop;
      end;
   end;
   Project_Tools.Files.Write_Raw_File (Export, Original & "replaced after staging");
   Project_Tools.Files.Write_Raw_File
     (Backup & "/manifest.dbbackup", "replaced after staging" & ASCII.LF);
   Ada_Quality.Artifact_Signing.Verify (Staged_Export, Public);
   Ada_Quality.Artifact_Signing.Verify (Staged_Backup, Public);
   Project_Tools.Files.Write_Raw_File (Export, Original);
   Project_Tools.Files.Write_Raw_File
     (Backup & "/manifest.dbbackup", "backup manifest fixture" & ASCII.LF);
   Assert
     (Project_Tools.Files.Read_Raw_File (Staged_Export) = Original,
      "verification staging binds later consumption to the copied artifact bytes");
end Run_Artifact_Staging_Test;
