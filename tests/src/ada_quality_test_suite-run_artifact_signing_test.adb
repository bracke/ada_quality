with Ada_Quality.Artifact_Signing;

separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_artifact_signing_test owner=aq expires=2099-12-31 justification=security-fixture-matrix
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
   Original   : constant String := "native logical export fixture" & ASCII.LF;
   Raised     : Boolean := False;
begin
   if Ada.Directories.Exists (Root) then Project_Tools.Files.Delete_Tree (Root); end if;
   Ada.Directories.Create_Path (Backup);
   Ada.Directories.Create_Path (Empty_Backup);
   Project_Tools.Files.Write_Raw_File (Export, Original);
   Project_Tools.Files.Write_Raw_File (Unsigned, Original);
   Project_Tools.Files.Write_Raw_File (Backup & "/manifest.dbbackup", "backup manifest fixture" & ASCII.LF);

   Ada_Quality.Artifact_Signing.Generate_Keypair (Private_Path, Public);
   Ada_Quality.Artifact_Signing.Generate_Keypair (Other_Priv, Other_Pub);
   Ada_Quality.Artifact_Signing.Sign (Export, Private_Path);
   Ada_Quality.Artifact_Signing.Sign (Backup, Private_Path);
   Ada_Quality.Artifact_Signing.Verify (Export, Public);
   Ada_Quality.Artifact_Signing.Verify (Backup, Public);
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
   Ada_Quality.Artifact_Signing.Verify (Export, Public);

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

      procedure Write_Sidecar (Algorithm, Kind : String) is
      begin
         Project_Tools.Files.Write_Text_File
           (Sidecar, "format=ada-quality-artifact-signature-v1" & ASCII.LF &
            "algorithm=" & Algorithm & ASCII.LF & "kind=" & Kind & ASCII.LF &
            "digest=" & Digest & ASCII.LF & "signature=" & Signature & ASCII.LF);
      end Write_Sidecar;
   begin
      Write_Sidecar ("unsupported", "logical-export");
      Raised := False;
      begin
         Ada_Quality.Artifact_Signing.Verify (Export, Public);
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "verification rejects unsupported signature algorithms");

      Write_Sidecar ("ed25519-sha256", "physical-backup");
      Raised := False;
      begin
         Ada_Quality.Artifact_Signing.Verify (Export, Public);
      exception
         when Ada_Quality.Artifact_Signing.Signing_Error => Raised := True;
      end;
      Assert (Raised, "verification rejects signature metadata for another artifact kind");
      Write_Sidecar ("ed25519-sha256", "logical-export");
      Ada_Quality.Artifact_Signing.Verify (Export, Public);
   end;

   Project_Tools.Files.Delete_Tree (Root);
end Run_Artifact_Signing_Test;
