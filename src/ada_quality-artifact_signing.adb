with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with CryptoLib.Ed25519;
with CryptoLib.Errors;
with CryptoLib.Hashes;
with CryptoLib.Random;
with CryptoLib.Secure_Wipe;
with Interfaces.C;
with Project_Tools.Files;
with Project_Tools.Links;

package body Ada_Quality.Artifact_Signing is
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type CryptoLib.Errors.Status;
   use type Interfaces.C.int;

   Private_Format   : constant String := "ada-quality-ed25519-private-v1";
   Public_Format    : constant String := "ada-quality-ed25519-public-v1";
   Signature_Format : constant String := "ada-quality-artifact-signature-v1";
   Backup_Kind      : constant String := "physical-backup";
   Export_Kind      : constant String := "logical-export";
   Backup_Manifest  : constant String := "manifest.dbbackup";
   Backup_Signature : constant String := "ada-quality.signature";

   subtype Key_Array is Ada.Streams.Stream_Element_Array
     (1 .. Ada.Streams.Stream_Element_Offset (CryptoLib.Ed25519.Public_Key_Length));
   subtype Signature_Array is Ada.Streams.Stream_Element_Array
     (1 .. Ada.Streams.Stream_Element_Offset (CryptoLib.Ed25519.Signature_Length));
   subtype Digest_Array is Ada.Streams.Stream_Element_Array (1 .. 32);

   function C_Chmod
     (Path : Interfaces.C.char_array; Mode : Interfaces.C.unsigned) return Interfaces.C.int
   with Import, Convention => C, External_Name => "chmod";

   function C_Open
     (Path : Interfaces.C.char_array; Flags : Interfaces.C.int;
      Mode : Interfaces.C.unsigned) return Interfaces.C.int
   with Import, Convention => C, External_Name => "open";

   function C_Close (FD : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "close";

   function Bytes (Text : String) return Ada.Streams.Stream_Element_Array is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Text'Length));
   begin
      for J in Text'Range loop
         Result (Ada.Streams.Stream_Element_Offset (J - Text'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Text (J)));
      end loop;
      return Result;
   end Bytes;

   function Hex (Value : Ada.Streams.Stream_Element_Array) return String is
      Alphabet : constant String := "0123456789abcdef";
      Result : String (1 .. Value'Length * 2);
      Next   : Positive := Result'First;
   begin
      for Byte of Value loop
         Result (Next) := Alphabet (Natural (Byte) / 16 + 1);
         Result (Next + 1) := Alphabet (Natural (Byte) mod 16 + 1);
         Next := Next + 2;
      end loop;
      return Result;
   end Hex;

   function Nibble (Value : Character) return Ada.Streams.Stream_Element is
   begin
      if Value in '0' .. '9' then
         return Ada.Streams.Stream_Element (Character'Pos (Value) - Character'Pos ('0'));
      elsif Value in 'a' .. 'f' then
         return Ada.Streams.Stream_Element (Character'Pos (Value) - Character'Pos ('a') + 10);
      elsif Value in 'A' .. 'F' then
         return Ada.Streams.Stream_Element (Character'Pos (Value) - Character'Pos ('A') + 10);
      end if;
      raise Signing_Error with "key or signature contains non-hexadecimal data";
   end Nibble;

   procedure Decode_Hex
     (Text : String; Result : out Ada.Streams.Stream_Element_Array; Label : String) is
      Position : Natural := Text'First;
   begin
      if Text'Length /= Result'Length * 2 then
         raise Signing_Error with Label & " has an invalid length";
      end if;
      for J in Result'Range loop
         Result (J) := Ada.Streams.Stream_Element
           (Natural (Nibble (Text (Position))) * 16 +
            Natural (Nibble (Text (Position + 1))));
         Position := Position + 2;
      end loop;
   end Decode_Hex;

   procedure Require_Format (Path, Expected : String) is
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         raise Signing_Error with "key or signature file not found: " & Path;
      elsif Project_Tools.Links.Is_Link (Path) then
         raise Signing_Error with "key or signature file must not be a symbolic link: " & Path;
      elsif Project_Tools.Files.Value_Of (Path, "format") /= Expected then
         raise Signing_Error with "unsupported key or signature format: " & Path;
      end if;
   end Require_Format;

   procedure Artifact_Data
     (Artifact : String; Content_Path, Kind : out Project_Tools.Files.Unbounded_String) is
   begin
      if Project_Tools.Links.Is_Link (Artifact) then
         raise Signing_Error with "artifact must not be a symbolic link: " & Artifact;
      elsif Project_Tools.Files.Directory_Exists (Artifact) then
         if not Project_Tools.Files.File_Exists
           (Project_Tools.Files.Join (Artifact, Backup_Manifest))
         then
            raise Signing_Error with "physical backup manifest not found: " & Artifact;
         end if;
         Content_Path := Ada.Strings.Unbounded.To_Unbounded_String
           (Project_Tools.Files.Join (Artifact, Backup_Manifest));
         Kind := Ada.Strings.Unbounded.To_Unbounded_String (Backup_Kind);
      elsif Project_Tools.Files.File_Exists (Artifact) then
         Content_Path := Ada.Strings.Unbounded.To_Unbounded_String (Artifact);
         Kind := Ada.Strings.Unbounded.To_Unbounded_String (Export_Kind);
      else
         raise Signing_Error with "artifact not found: " & Artifact;
      end if;
   end Artifact_Data;

   function Digest
     (Content_Path, Kind : String) return Digest_Array
   is
      File    : Ada.Streams.Stream_IO.File_Type;
      Context : CryptoLib.Hashes.SHA256_Context;
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. 65_536);
      Last    : Ada.Streams.Stream_Element_Offset;
      Native  : CryptoLib.Hashes.SHA256_Digest;
      Result  : Digest_Array;
   begin
      CryptoLib.Hashes.Initialize_SHA256 (Context);
      CryptoLib.Hashes.Update
        (Context, Bytes (Signature_Format & ASCII.LF & Kind & ASCII.LF));
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Content_Path);
      while not Ada.Streams.Stream_IO.End_Of_File (File) loop
         Ada.Streams.Stream_IO.Read (File, Buffer, Last);
         if Last >= Buffer'First then
            CryptoLib.Hashes.Update (Context, Buffer (Buffer'First .. Last));
         end if;
      end loop;
      Ada.Streams.Stream_IO.Close (File);
      Native := CryptoLib.Hashes.Finalize (Context);
      for J in Result'Range loop
         Result (J) := Native (Positive (J));
      end loop;
      return Result;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then Ada.Streams.Stream_IO.Close (File); end if;
         raise Signing_Error with "cannot read artifact for signing: " & Content_Path;
   end Digest;

   function Signature_Path (Artifact : String) return String is
   begin
      if Project_Tools.Files.Directory_Exists (Artifact) then
         return Project_Tools.Files.Join (Artifact, Backup_Signature);
      end if;
      return Artifact & ".sig";
   end Signature_Path;

   procedure Generate_Keypair (Private_Key_Path, Public_Key_Path : String) is
      Rng    : CryptoLib.Random.Random_Source;
      Seed   : Key_Array;
      Public : Key_Array;
      Status : CryptoLib.Errors.Status;
      Descriptor : Interfaces.C.int := -1;
      Private_Created : Boolean := False;
      Public_Created  : Boolean := False;
   begin
      if Project_Tools.Files.Exists (Private_Key_Path) or else
        Project_Tools.Files.Exists (Public_Key_Path)
      then
         raise Signing_Error with "key destination already exists";
      end if;
      CryptoLib.Random.Initialize_Production (Rng);
      Status := CryptoLib.Ed25519.Generate_Keypair (Rng, Seed, Public);
      if Status /= CryptoLib.Errors.Ok then
         raise Signing_Error with "Ed25519 key generation failed: " & Status'Image;
      end if;
      Descriptor := C_Open
        (Interfaces.C.To_C (Private_Key_Path),
         Interfaces.C.int (1 + 64 + 128 + 131_072 + 524_288),
         Interfaces.C.unsigned (8#600#));
      if Descriptor < 0 then
         raise Signing_Error with "cannot create private key securely";
      end if;
      Private_Created := True;
      if C_Close (Descriptor) /= 0 then
         raise Signing_Error with "cannot create private key securely";
      end if;
      Descriptor := -1;
      Project_Tools.Files.Write_Text_File
        (Private_Key_Path, "format=" & Private_Format & ASCII.LF &
         "seed=" & Hex (Seed) & ASCII.LF & "public=" & Hex (Public) & ASCII.LF);
      if C_Chmod (Interfaces.C.To_C (Private_Key_Path), Interfaces.C.unsigned (8#600#)) /= 0 then
         Project_Tools.Files.Delete_File_If_Present (Private_Key_Path);
         Project_Tools.Files.Delete_File_If_Present (Public_Key_Path);
         raise Signing_Error with "cannot restrict private key permissions";
      end if;
      Public_Created := True;
      Project_Tools.Files.Write_Text_File
        (Public_Key_Path, "format=" & Public_Format & ASCII.LF &
         "public=" & Hex (Public) & ASCII.LF);
      CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
   exception
      when others =>
         if Descriptor >= 0 then
            declare Ignored : constant Interfaces.C.int := C_Close (Descriptor); pragma Unreferenced (Ignored);
            begin null; end;
         end if;
         if Private_Created then Project_Tools.Files.Delete_File_If_Present (Private_Key_Path); end if;
         if Public_Created then Project_Tools.Files.Delete_File_If_Present (Public_Key_Path); end if;
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         raise;
   end Generate_Keypair;

   procedure Sign (Artifact, Private_Key_Path : String) is
      Content_Path, Kind : Project_Tools.Files.Unbounded_String;
      Seed, Public, Derived : Key_Array;
      Signature : Signature_Array;
      Artifact_Digest : Digest_Array;
      Status : CryptoLib.Errors.Status;
      Sidecar : constant String := Signature_Path (Artifact);
   begin
      if Project_Tools.Files.Exists (Sidecar) then
         raise Signing_Error with "signature destination already exists: " & Sidecar;
      end if;
      Require_Format (Private_Key_Path, Private_Format);
      Decode_Hex (Project_Tools.Files.Value_Of (Private_Key_Path, "seed"), Seed, "private seed");
      Decode_Hex (Project_Tools.Files.Value_Of (Private_Key_Path, "public"), Public, "public key");
      Status := CryptoLib.Ed25519.Public_Key_From_Seed (Seed, Derived);
      if Status /= CryptoLib.Errors.Ok or else Derived /= Public then
         raise Signing_Error with "private key file is internally inconsistent";
      end if;
      Artifact_Data (Artifact, Content_Path, Kind);
      Artifact_Digest := Digest
        (Ada.Strings.Unbounded.To_String (Content_Path), Ada.Strings.Unbounded.To_String (Kind));
      Status := CryptoLib.Ed25519.Sign (Seed, Public, Artifact_Digest, Signature);
      if Status /= CryptoLib.Errors.Ok then
         raise Signing_Error with "Ed25519 signing failed: " & Status'Image;
      end if;
      Project_Tools.Files.Write_Text_File
        (Sidecar, "format=" & Signature_Format & ASCII.LF &
         "algorithm=ed25519-sha256" & ASCII.LF &
         "kind=" & Ada.Strings.Unbounded.To_String (Kind) & ASCII.LF &
         "digest=" & Hex (Artifact_Digest) & ASCII.LF &
         "signature=" & Hex (Signature) & ASCII.LF);
      CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
   exception
      when others =>
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         raise;
   end Sign;

   procedure Verify (Artifact, Public_Key_Path : String) is
      Content_Path, Kind : Project_Tools.Files.Unbounded_String;
      Public : Key_Array;
      Signature : Signature_Array;
      Recorded_Digest, Actual_Digest : Digest_Array;
      Sidecar : constant String := Signature_Path (Artifact);
      Status : CryptoLib.Errors.Status;
   begin
      Require_Format (Public_Key_Path, Public_Format);
      Require_Format (Sidecar, Signature_Format);
      if Project_Tools.Files.Value_Of (Sidecar, "algorithm") /= "ed25519-sha256" then
         raise Signing_Error with "unsupported artifact signature algorithm";
      end if;
      Artifact_Data (Artifact, Content_Path, Kind);
      if Project_Tools.Files.Value_Of (Sidecar, "kind") /=
        Ada.Strings.Unbounded.To_String (Kind)
      then
         raise Signing_Error with "artifact signature kind does not match the artifact";
      end if;
      Decode_Hex (Project_Tools.Files.Value_Of (Public_Key_Path, "public"), Public, "public key");
      Decode_Hex (Project_Tools.Files.Value_Of (Sidecar, "signature"), Signature, "signature");
      Decode_Hex (Project_Tools.Files.Value_Of (Sidecar, "digest"), Recorded_Digest, "artifact digest");
      Actual_Digest := Digest
        (Ada.Strings.Unbounded.To_String (Content_Path), Ada.Strings.Unbounded.To_String (Kind));
      if Recorded_Digest /= Actual_Digest then
         raise Signing_Error with "artifact digest does not match its signature metadata";
      end if;
      Status := CryptoLib.Ed25519.Verify (Public, Signature, Actual_Digest);
      if Status /= CryptoLib.Errors.Ok then
         raise Signing_Error with "artifact signature verification failed";
      end if;
   end Verify;
end Ada_Quality.Artifact_Signing;
