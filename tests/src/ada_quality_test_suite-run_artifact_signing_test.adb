with Ada_Quality.Artifact_Signing;
with Ada_Quality.Artifact_Staging;

separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_artifact_signing_test owner=aq expires=2027-11-21 justification=security-fixture-matrix
procedure Run_Artifact_Signing_Test is
   Root       : constant String := Fixture_Root & "/artifact-signing";
   Private_Path : constant String := Root & "/signing.key";
   Public     : constant String := Root & "/signing.pub";
   Other_Priv : constant String := Root & "/other.key";
   Other_Pub  : constant String := Root & "/other.pub";
   Export     : constant String := Root & "/database.export";
   Unsigned   : constant String := Root & "/unsigned.export";
   Backup     : constant String := Root & "/database.backup";
   Empty_Backup : constant String := Root & "/empty.backup";
   Bad_Key    : constant String := Root & "/bad.key";
   Trust_Store : constant String := Root & "/trust";
   Real_Trust_Store : constant String := Root & "/real-trust";
   Outside_Key : constant String := Root & "/outside-key";
   Partial_Private : constant String := Root & "/partial.key";
   Missing_Public : constant String := Root & "/missing/public.pub";
   Long_Artifact : constant String := Root & "/" & [1 .. 252 => 'a'];
   Original   : constant String := "native logical export fixture" & ASCII.LF;
   Raised     : Boolean := False;
begin
   if Ada.Directories.Exists (Root) then Project_Tools.Files.Delete_Tree (Root); end if;
   Ada.Directories.Create_Path (Backup);
   Ada.Directories.Create_Path (Empty_Backup);
   Ada.Directories.Create_Path (Backup & "/nested");
   Project_Tools.Files.Write_Raw_File (Export, Original);
   Project_Tools.Files.Write_Raw_File (Unsigned, Original);
   Project_Tools.Files.Write_Raw_File (Backup & "/manifest.dbbackup", "backup manifest fixture" & ASCII.LF);
   Project_Tools.Files.Write_Raw_File (Backup & "/nested/evidence", "nested fixture" & ASCII.LF);

   Ada_Quality.Artifact_Signing.Generate_Keypair (Private_Path, Public);
   Ada_Quality.Artifact_Signing.Generate_Keypair (Other_Priv, Other_Pub);
   Ada_Quality.Artifact_Signing.Sign (Export, Private_Path);
   Ada_Quality.Artifact_Signing.Sign (Backup, Private_Path);
   Ada_Quality.Artifact_Signing.Verify (Export, Public);
   Ada_Quality.Artifact_Signing.Verify (Backup, Public);
   declare
      Id : constant String := Ada_Quality.Artifact_Signing.Key_Id (Public);
      Added : constant String :=
        Ada_Quality.Artifact_Signing.Add_Trusted_Key (Trust_Store, Public);
      Repeated : constant String :=
        Ada_Quality.Artifact_Signing.Add_Trusted_Key (Trust_Store, Public);
      Info : constant Ada_Quality.Artifact_Signing.Signature_Info :=
        Ada_Quality.Artifact_Signing.Inspect (Export);
      Outside_Before : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Ada_Quality.Artifact_Signing.Verify_Trusted (Export, Trust_Store);
      Assert
        (Id = Added and then Repeated = Id and then To_String (Info.Key) = Id and then
         Ada_Quality.Artifact_Signing.Trusted_Keys (Trust_Store).Length = 1,
         "signature metadata identifies keys and repeated trust insertion is idempotent");
      declare
         Trusted_Path : constant String := Trust_Store & "/" & Id & ".pub";
         Trusted_Content : constant String :=
           Project_Tools.Files.Read_Raw_File (Trusted_Path);
      begin
         Project_Tools.Files.Write_Text_File
           (Trusted_Path, Trusted_Content & "comment=collision" & ASCII.LF);
         Raised := False;
         begin
            declare
               Ignored : constant String :=
                 Ada_Quality.Artifact_Signing.Add_Trusted_Key (Trust_Store, Public);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
         end;
         Assert (Raised, "trust insertion rejects a key-identity content collision");

         Project_Tools.Files.Write_Text_File
           (Trusted_Path,
            [1 .. Ada_Quality.Resource_Limits.Maximum_Security_Metadata_Bytes + 1 => 'x']);
         Raised := False;
         begin
            declare
               Ignored : constant String :=
                 Ada_Quality.Artifact_Signing.Add_Trusted_Key (Trust_Store, Public);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
         end;
         Assert (Raised, "trust insertion rejects oversized stored-key metadata");
         Project_Tools.Files.Write_Text_File (Trusted_Path, Trusted_Content);
      end;
      Ada_Quality.Artifact_Signing.Remove_Trusted_Key (Trust_Store, Id);
      Assert
        (Ada_Quality.Artifact_Signing.Trusted_Keys (Trust_Store).Is_Empty,
         "trusted keys can be explicitly revoked");
      Project_Tools.Files.Write_Text_File (Outside_Key, "sentinel" & ASCII.LF);
      Outside_Before := To_Unbounded_String (Project_Tools.Files.Read_Raw_File (Outside_Key));
      declare
         Link_Run : constant Ada_Quality.Execution.Run_Result := Ada_Quality.Execution.Run
           (Root, "ln",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("-s"),
                Project_Tools.Processes.Argument (Outside_Key),
                Project_Tools.Processes.Argument (Trust_Store & "/" & Id & ".pub")]),
            Timeout_Seconds => 2, Maximum_Bytes => 128);
      begin
         Assert
           (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
            "trusted-key symlink fixture is created");
      end;
      Raised := False;
      begin
         declare Ignored : constant String :=
           Ada_Quality.Artifact_Signing.Add_Trusted_Key (Trust_Store, Public);
           pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "trust insertion rejects destination symlinks");
      Assert
        (Project_Tools.Files.Read_Raw_File (Outside_Key) = To_String (Outside_Before),
         "rejected trust insertion does not overwrite a symlink target");
      Ada.Directories.Delete_File (Trust_Store & "/" & Id & ".pub");
      declare Ignored : constant String :=
        Ada_Quality.Artifact_Signing.Add_Trusted_Key (Real_Trust_Store, Public);
        pragma Unreferenced (Ignored);
      begin null; end;
      Project_Tools.Files.Delete_Tree (Trust_Store);
      declare
         Link_Run : constant Ada_Quality.Execution.Run_Result := Ada_Quality.Execution.Run
           (Root, "ln",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("-s"),
                Project_Tools.Processes.Argument (Real_Trust_Store),
                Project_Tools.Processes.Argument (Trust_Store)]),
            Timeout_Seconds => 2, Maximum_Bytes => 128);
      begin
         Assert
           (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
            "trust-store symlink fixture is created");
      end;
      Raised := False;
      begin
         Ada_Quality.Artifact_Signing.Verify_Trusted (Export, Trust_Store);
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "trusted verification rejects a substituted store-directory symlink");
   end;
   Assert
     (Project_Tools.Files.File_Exists (Export & ".sig") and then
      Project_Tools.Files.File_Exists (Backup & "/ada-quality.signature"),
      "logical exports and physical backups receive deterministic signature sidecars");

   Raised := False;
   Project_Tools.Files.Write_Raw_File (Export, Original & "tampered");
   begin
      Ada_Quality.Artifact_Signing.Verify (Export, Public);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "artifact modification invalidates its signature");
   Project_Tools.Files.Write_Raw_File (Export, Original);
   Ada_Quality.Artifact_Signing.Verify (Export, Public);

   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Verify (Export, Other_Pub);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "a signature is accepted only for the trusted public key");

   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Export, Private_Path);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signature sidecars are never overwritten implicitly");

   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Generate_Keypair (Private_Path, Public);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert
     (Raised and then Project_Tools.Files.File_Exists (Private_Path) and then
      Project_Tools.Files.File_Exists (Public),
      "key generation refuses existing destinations without deleting trusted keys");
   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Generate_Keypair
        (Partial_Private, Missing_Public);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert
     (Raised and then not Project_Tools.Files.File_Exists (Partial_Private),
      "failed key generation wipes seed material and removes its private key");
   Ada_Quality.Artifact_Signing.Verify (Export, Public);

   Project_Tools.Files.Write_Raw_File (Long_Artifact, Original);
   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Long_Artifact, Private_Path);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert
     (Raised and then
      not Project_Tools.Files.File_Exists (Long_Artifact & ".sig"),
      "failed sidecar creation wipes seed material and leaves no partial file");

   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Unsigned, Root & "/missing.key");
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signing requires an existing private key");

   Project_Tools.Files.Write_Text_File (Bad_Key, "format=unknown" & ASCII.LF);
   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Unsigned, Bad_Key);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signing rejects unsupported private-key formats");

   Project_Tools.Files.Write_Text_File
     (Bad_Key,
      [1 .. Ada_Quality.Resource_Limits.Maximum_Security_Metadata_Bytes + 1 => 'x']);
   Raised := False;
   begin
      declare
         Ignored : constant String := Ada_Quality.Artifact_Signing.Key_Id (Bad_Key);
         pragma Unreferenced (Ignored);
      begin
         null;
      end;
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "key loading rejects oversized security metadata");

   Project_Tools.Files.Write_Text_File
     (Bad_Key, "format=ada-quality-ed25519-private-v1" & ASCII.LF &
      "seed=00" & ASCII.LF & "public=" & [1 .. 64 => '0'] & ASCII.LF);
   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Unsigned, Bad_Key);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signing rejects incorrectly sized private seeds");

   Project_Tools.Files.Write_Text_File
     (Bad_Key, "format=ada-quality-ed25519-private-v1" & ASCII.LF &
      "seed=" & [1 .. 64 => 'z'] & ASCII.LF & "public=" & [1 .. 64 => '0'] & ASCII.LF);
   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Unsigned, Bad_Key);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signing rejects non-hexadecimal private seeds");

   Project_Tools.Files.Write_Text_File
     (Bad_Key, "format=ada-quality-ed25519-private-v1" & ASCII.LF &
      "seed=" & Project_Tools.Files.Value_Of (Private_Path, "seed") & ASCII.LF &
      "public=" & Project_Tools.Files.Value_Of (Other_Pub, "public") & ASCII.LF);
   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Unsigned, Bad_Key);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signing rejects internally inconsistent key files");

   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Root & "/missing.export", Private_Path);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signing rejects missing artifacts");

   Raised := False;
   begin
      Ada_Quality.Artifact_Signing.Sign (Empty_Backup, Private_Path);
   exception
      when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
   end;
   Assert (Raised, "signing rejects backup directories without a manifest");

   declare
      Sidecar : constant String := Export & ".sig";
      Digest : constant String := Project_Tools.Files.Value_Of (Sidecar, "digest");
      Signature : constant String := Project_Tools.Files.Value_Of (Sidecar, "signature");
      Key_Id : constant String := Project_Tools.Files.Value_Of (Sidecar, "key_id");

      procedure Write_Sidecar
        (Algorithm, Kind : String; Digest_Value : String := Digest;
         Key_Value : String := Key_Id) is
      begin
         Project_Tools.Files.Write_Text_File
           (Sidecar, "format=ada-quality-artifact-signature-v1" & ASCII.LF &
            "algorithm=" & Algorithm & ASCII.LF & "kind=" & Kind & ASCII.LF &
            "key_id=" & Key_Value & ASCII.LF &
            "digest=" & Digest_Value & ASCII.LF & "signature=" & Signature & ASCII.LF);
      end Write_Sidecar;
   begin
      Project_Tools.Files.Write_Text_File
        (Sidecar,
         [1 .. Ada_Quality.Resource_Limits.Maximum_Security_Metadata_Bytes + 1 => 'x']);
      Raised := False;
      begin
         declare
            Ignored : constant Ada_Quality.Artifact_Signing.Signature_Info :=
              Ada_Quality.Artifact_Signing.Inspect (Export);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "signature inspection rejects oversized security metadata");

      Raised := False;
      begin
         Ada_Quality.Artifact_Staging.Copy
           (Export, Root & "/rejected-oversized-sidecar.export");
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert
        (Raised and then
         not Ada.Directories.Exists (Root & "/rejected-oversized-sidecar.export") and then
         not Ada.Directories.Exists (Root & "/rejected-oversized-sidecar.export.sig"),
         "staging rejects oversized signature metadata and removes partial output");
      Write_Sidecar ("ed25519-sha256", "logical-export");

      Write_Sidecar ("unsupported", "logical-export");
      Raised := False;
      begin
         Ada_Quality.Artifact_Signing.Verify (Export, Public);
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "verification rejects unsupported signature algorithms");
      Raised := False;
      begin
         declare Ignored : constant Ada_Quality.Artifact_Signing.Signature_Info :=
           Ada_Quality.Artifact_Signing.Inspect (Export);
           pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "inspection rejects unsupported signature algorithms");

      Write_Sidecar ("ed25519-sha256", "physical-backup");
      Raised := False;
      begin
         Ada_Quality.Artifact_Signing.Verify (Export, Public);
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "verification rejects signature metadata for another artifact kind");
      Write_Sidecar ("ed25519-sha256", "logical-export", Digest_Value => "00");
      Raised := False;
      begin
         declare Ignored : constant Ada_Quality.Artifact_Signing.Signature_Info :=
           Ada_Quality.Artifact_Signing.Inspect (Export);
           pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "inspection rejects malformed signature digests");
      Write_Sidecar
        ("ed25519-sha256", "logical-export", Key_Value => "ed25519-invalid");
      Raised := False;
      begin
         declare Ignored : constant Ada_Quality.Artifact_Signing.Signature_Info :=
           Ada_Quality.Artifact_Signing.Inspect (Export);
           pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "inspection rejects malformed signature key identities");
      Write_Sidecar ("ed25519-sha256", "logical-export");
      Ada_Quality.Artifact_Signing.Verify (Export, Public);
   end;

   Project_Tools.Files.Delete_Tree (Root);
end Run_Artifact_Signing_Test;
