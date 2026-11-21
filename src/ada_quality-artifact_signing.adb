with Ada.Streams;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada_Quality.POSIX;
with Ada_Quality.Resource_Limits;
with CryptoLib.Ed25519;
with CryptoLib.Errors;
with CryptoLib.Hashes;
with CryptoLib.Random;
with CryptoLib.Secure_Wipe;
with Interfaces.C;
with Project_Tools.Files;
with Project_Tools.Links;

package body Ada_Quality.Artifact_Signing is
   use Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Array;
   use type Ada.Streams.Stream_Element_Offset;
   use type CryptoLib.Errors.Status;
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use Ada_Quality.POSIX;

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

   procedure Remove_Partial_File (Path : String) is
   begin
      Project_Tools.Files.Delete_File_If_Present (Path);
   exception
      when others =>  --  Preserve the primary signing failure during cleanup.
         null;
   end Remove_Partial_File;

   procedure Encode_Hex
     (Value  : Ada.Streams.Stream_Element_Array;
      Result : out String);

   procedure Write_All
     (Descriptor : Interfaces.C.int; Content, Label : String)
   is
      Written : Natural := 0;
   begin
      while Written < Content'Length loop
         declare
            Count : constant Interfaces.C.long := Write
              (Descriptor, Content (Content'First + Written)'Address,
               Interfaces.C.size_t (Content'Length - Written));
         begin
            if Count <= 0 then
               raise Signing_Error with "cannot write " & Label;
            end if;
            Written := Written + Natural (Count);
         end;
      end loop;
   end Write_All;

   procedure Create_Key_File
     (Path, Content, Label : String;
      Private_File : Boolean;
      Created : out Boolean)
   is
      Descriptor : Interfaces.C.int := -1;
   begin
      Created := False;
      Descriptor :=
        (if Private_File
         then Create_Private (Interfaces.C.To_C (Path))
         else Create_Public (Interfaces.C.To_C (Path)));
      if Descriptor < 0 then
         raise Signing_Error with Label & " destination already exists or is unsafe";
      end if;
      Created := True;
      Write_All (Descriptor, Content, Label);
      if not Close_Succeeded (Descriptor) then
         raise Signing_Error with "cannot complete " & Label;
      end if;
   exception
      when others =>
         Close (Descriptor);
         if Created then
            Remove_Partial_File (Path);
         end if;
         raise;
   end Create_Key_File;

   procedure Create_Private_Key_File
     (Path    : String;
      Seed    : Key_Array;
      Public  : Key_Array;
      Created : out Boolean)
   is
      Descriptor : Interfaces.C.int := -1;
      Encoded    : aliased String (1 .. Seed'Length * 2);

      procedure Wipe_Encoded is
      begin
         CryptoLib.Secure_Wipe.Wipe (Encoded'Address, Encoded'Length);
      end Wipe_Encoded;
   begin
      Created := False;
      Descriptor := Create_Private (Interfaces.C.To_C (Path));
      if Descriptor < 0 then
         raise Signing_Error with
           "private key destination already exists or is unsafe";
      end if;
      Created := True;
      Write_All (Descriptor, "format=" & Private_Format & ASCII.LF, "private key");
      Write_All (Descriptor, "seed=", "private key");
      Encode_Hex (Seed, Encoded);
      Write_All (Descriptor, Encoded, "private key");
      Wipe_Encoded;
      Write_All (Descriptor, ASCII.LF & "public=", "private key");
      Encode_Hex (Public, Encoded);
      Write_All (Descriptor, Encoded, "private key");
      Wipe_Encoded;
      Write_All (Descriptor, String'(1 => ASCII.LF), "private key");
      if not Close_Succeeded (Descriptor) then
         raise Signing_Error with "cannot complete private key";
      end if;
   exception
      when others =>
         Wipe_Encoded;
         Close (Descriptor);
         if Created then
            Remove_Partial_File (Path);
         end if;
         raise;
   end Create_Private_Key_File;

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

   procedure Encode_Hex
     (Value  : Ada.Streams.Stream_Element_Array;
      Result : out String)
   is
      Alphabet : constant String := "0123456789abcdef";
      Next     : Positive := Result'First;
   begin
      if Result'Length /= Value'Length * 2 then
         raise Program_Error with "hexadecimal destination has the wrong size";
      end if;
      for Byte of Value loop
         Result (Next) := Alphabet (Natural (Byte) / 16 + 1);
         Result (Next + 1) := Alphabet (Natural (Byte) mod 16 + 1);
         Next := Next + 2;
      end loop;
   end Encode_Hex;

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

   procedure Decode_Content_Hex
     (Content : String;
      Key     : String;
      Result  : out Ada.Streams.Stream_Element_Array;
      Label   : String)
   is
      Prefix      : constant String := Key & "=";
      Start       : Positive := Content'First;
      Value_First : Natural := 0;
      Value_Last  : Natural := 0;
   begin
      while Start <= Content'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index
              (Content, String'(1 => ASCII.LF), From => Start);
         begin
            if Stop = 0 then
               Stop := Content'Last + 1;
            end if;
            declare
               Last : Natural := Stop - 1;
            begin
               if Last >= Start and then Content (Last) = ASCII.CR then
                  Last := Last - 1;
               end if;
               if Last >= Start + Prefix'Length - 1 and then
                 Content (Start .. Start + Prefix'Length - 1) = Prefix
               then
                  Value_First := Start + Prefix'Length;
                  Value_Last := Last;
                  exit;
               end if;
            end;
            Start := Stop + 1;
         end;
      end loop;
      if Value_First = 0 or else Value_Last < Value_First or else
        Value_Last - Value_First + 1 /= Result'Length * 2
      then
         raise Signing_Error with Label & " has an invalid length";
      end if;
      declare
         Position : Natural := Value_First;
      begin
         for Index in Result'Range loop
            Result (Index) := Ada.Streams.Stream_Element
              (Natural (Nibble (Content (Position))) * 16 +
               Natural (Nibble (Content (Position + 1))));
            Position := Position + 2;
         end loop;
      end;
   end Decode_Content_Hex;

   function Content_Value (Content, Key : String) return String is
      Prefix : constant String := Key & "=";
      Start  : Positive := Content'First;
   begin
      while Start <= Content'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index (Content, String'(1 => ASCII.LF), From => Start);
         begin
            if Stop = 0 then
               Stop := Content'Last + 1;
            end if;
            declare
               Last : Natural := Stop - 1;
            begin
               if Last >= Start and then Content (Last) = ASCII.CR then
                  Last := Last - 1;
               end if;
               if Last >= Start + Prefix'Length - 1 and then
                 Content (Start .. Start + Prefix'Length - 1) = Prefix
               then
                  return Content (Start + Prefix'Length .. Last);
               end if;
            end;
            Start := Stop + 1;
         end;
      end loop;
      return "";
   end Content_Value;

   function Read_Descriptor
     (Descriptor : Interfaces.C.int; Label : String) return String;

   procedure Read_Descriptor
     (Descriptor : Interfaces.C.int;
      Buffer     : out String;
      Last       : out Natural;
      Label      : String)
   is
      Count : Interfaces.C.long;
   begin
      Last := 0;
      loop
         if Last = Buffer'Length then
            raise Signing_Error with Label & " exceeds the supported size";
         end if;
         Count := Read
           (Descriptor, Buffer (Buffer'First + Last)'Address,
            Interfaces.C.size_t (Buffer'Length - Last));
         if Count < 0 then
            raise Signing_Error with "cannot read " & Label;
         elsif Count = 0 then
            exit;
         end if;
         Last := Last + Natural (Count);
         if Last > Ada_Quality.Resource_Limits.Maximum_Security_Metadata_Bytes then
            raise Signing_Error with Label & " exceeds the supported size";
         end if;
      end loop;
   end Read_Descriptor;

   procedure Load_Private_Key
     (Path   : String;
      Seed   : out Key_Array;
      Public : out Key_Array)
   is
      Descriptor : Interfaces.C.int := -1;
      Buffer : aliased String
        (1 .. Ada_Quality.Resource_Limits.Maximum_Security_Metadata_Bytes + 1);
      Last : Natural := 0;

      procedure Wipe_Buffer is
      begin
         CryptoLib.Secure_Wipe.Wipe (Buffer'Address, Buffer'Length);
      end Wipe_Buffer;
   begin
      Descriptor := Open_Read_Nofollow (Interfaces.C.To_C (Path));
      if Descriptor < 0 or else Descriptor_Kind (Descriptor) /= 1 then
         if Descriptor >= 0 then
            Close (Descriptor);
         end if;
         raise Signing_Error with
           "key file is missing, linked, or not an ordinary file: " & Path;
      end if;
      Read_Descriptor (Descriptor, Buffer, Last, "private key file: " & Path);
      if not Close_Succeeded (Descriptor) then
         raise Signing_Error with "cannot close private key file: " & Path;
      end if;
      if Last = 0 or else
        Content_Value (Buffer (Buffer'First .. Last), "format") /= Private_Format
      then
         raise Signing_Error with "unsupported private key format: " & Path;
      end if;
      Decode_Content_Hex
        (Buffer (Buffer'First .. Last), "seed", Seed, "private seed");
      Decode_Content_Hex
        (Buffer (Buffer'First .. Last), "public", Public, "public key");
      Wipe_Buffer;
   exception
      when others =>
         Close (Descriptor);
         Wipe_Buffer;
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         raise;
   end Load_Private_Key;

   function Formatted_Content (Path, Expected : String) return String is
      Descriptor : Interfaces.C.int := -1;
   begin
      Descriptor := Open_Read_Nofollow (Interfaces.C.To_C (Path));
      if Descriptor < 0 or else Descriptor_Kind (Descriptor) /= 1 then
         if Descriptor >= 0 then
            Close (Descriptor);
         end if;
         raise Signing_Error with
           "key or signature file is missing, linked, or not an ordinary file: " & Path;
      end if;
      declare
         Content : constant String := Read_Descriptor (Descriptor, "key or signature file: " & Path);
      begin
         if not Close_Succeeded (Descriptor) then
            raise Signing_Error with "cannot close key or signature file: " & Path;
         end if;
         if Content_Value (Content, "format") /= Expected then
            raise Signing_Error with "unsupported key or signature format: " & Path;
         end if;
         return Content;
      end;
   exception
      when others =>
         Close (Descriptor);
         raise;
   end Formatted_Content;

   function Read_Descriptor (Descriptor : Interfaces.C.int; Label : String) return String is
      Result : Unbounded_String;
      Buffer : String (1 .. 4_096);
   begin
      loop
         declare
            Count : constant Interfaces.C.long := Read
              (Descriptor, Buffer (Buffer'First)'Address,
               Interfaces.C.size_t (Buffer'Length));
         begin
            if Count < 0 then
               raise Signing_Error with "cannot read " & Label;
            elsif Count = 0 then
               exit;
            elsif Length (Result) + Natural (Count) >
              Ada_Quality.Resource_Limits.Maximum_Security_Metadata_Bytes
            then
               raise Signing_Error with Label & " exceeds the supported size";
            end if;
            Append (Result, Buffer (Buffer'First .. Buffer'First + Natural (Count) - 1));
         end;
      end loop;
      return To_String (Result);
   end Read_Descriptor;

   procedure Open_Artifact_Content
     (Artifact   : String;
      Descriptor : out Interfaces.C.int;
      Kind       : out Project_Tools.Files.Unbounded_String)
   is
      Root_FD : Interfaces.C.int := -1;
      Child_FD : Interfaces.C.int := -1;
   begin
      Descriptor := -1;
      Root_FD := Open_Read_Nofollow (Interfaces.C.To_C (Artifact));
      if Root_FD < 0 then
         raise Signing_Error with "artifact is missing, linked, or unsafe: " & Artifact;
      end if;
      case Descriptor_Kind (Root_FD) is
         when 1 =>
            Kind := To_Unbounded_String (Export_Kind);
            Descriptor := Root_FD;
            Root_FD := -1;
         when 2 =>
            Child_FD := Open_Child_Nofollow
              (Root_FD, Interfaces.C.To_C (Backup_Manifest));
            if Child_FD < 0 or else Descriptor_Kind (Child_FD) /= 1 then
               raise Signing_Error with
                 "physical backup manifest is missing, linked, or unsafe: " & Artifact;
            end if;
            if not Close_Succeeded (Root_FD) then
               raise Signing_Error with "cannot close artifact directory: " & Artifact;
            end if;
            Kind := To_Unbounded_String (Backup_Kind);
            Descriptor := Child_FD;
            Child_FD := -1;
         when others =>
            raise Signing_Error with "artifact is not an ordinary file or directory: " & Artifact;
      end case;
   exception
      when others =>
         Close (Child_FD);
         Close (Root_FD);
         raise;
   end Open_Artifact_Content;

   function Digest
     (Descriptor : Interfaces.C.int;
      Kind, Label : String) return Digest_Array
   is
      Context : CryptoLib.Hashes.SHA256_Context;
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. 65_536);
      Native  : CryptoLib.Hashes.SHA256_Digest;
      Result  : Digest_Array;
   begin
      CryptoLib.Hashes.Initialize_SHA256 (Context);
      CryptoLib.Hashes.Update
        (Context, Bytes (Signature_Format & ASCII.LF & Kind & ASCII.LF));
      loop
         declare
            Count : constant Interfaces.C.long := Read
              (Descriptor, Buffer (Buffer'First)'Address,
               Interfaces.C.size_t (Buffer'Length));
         begin
            if Count < 0 then
               raise Signing_Error with "cannot read artifact for signing: " & Label;
            elsif Count = 0 then
               exit;
            end if;
            CryptoLib.Hashes.Update
              (Context,
               Buffer
                 (Buffer'First ..
                  Buffer'First + Ada.Streams.Stream_Element_Offset (Count) - 1));
         end;
      end loop;
      Native := CryptoLib.Hashes.Finalize (Context);
      for J in Result'Range loop
         Result (J) := Native (Positive (J));
      end loop;
      return Result;
   end Digest;

   function Signature_Path (Artifact : String) return String is
   begin
      if Project_Tools.Files.Directory_Exists (Artifact) then
         return Project_Tools.Files.Join (Artifact, Backup_Signature);
      end if;
      return Artifact & ".sig";
   end Signature_Path;

   function Public_Id (Public : Key_Array) return String is
      Context : CryptoLib.Hashes.SHA256_Context;
      Native  : CryptoLib.Hashes.SHA256_Digest;
      Prefix  : Digest_Array;
   begin
      CryptoLib.Hashes.Initialize_SHA256 (Context);
      CryptoLib.Hashes.Update (Context, Public);
      Native := CryptoLib.Hashes.Finalize (Context);
      for J in Prefix'Range loop Prefix (J) := Native (Positive (J)); end loop;
      return "ed25519-" & Hex (Prefix (1 .. 8));
   end Public_Id;

   function Key_Id (Public_Key_Path : String) return String is
      Content : constant String := Formatted_Content (Public_Key_Path, Public_Format);
      Public : Key_Array;
   begin
      Decode_Hex (Content_Value (Content, "public"), Public, "public key");
      return Public_Id (Public);
   end Key_Id;

   function Valid_Key_Id (Id : String) return Boolean;
   procedure Verify_Content (Artifact, Public_Content : String);

   function Inspect (Artifact : String) return Signature_Info is
      Descriptor : Interfaces.C.int := -1;
      Kind       : Project_Tools.Files.Unbounded_String;
   begin
      Open_Artifact_Content (Artifact, Descriptor, Kind);
      if not Close_Succeeded (Descriptor) then
         raise Signing_Error with "cannot close artifact after inspection: " & Artifact;
      end if;
      declare
         Sidecar : constant String :=
           (if To_String (Kind) = Backup_Kind
            then Project_Tools.Files.Join (Artifact, Backup_Signature)
            else Artifact & ".sig");
         Sidecar_Content : constant String := Formatted_Content (Sidecar, Signature_Format);
         Recorded_Kind : constant Project_Tools.Files.Unbounded_String :=
           To_Unbounded_String (Content_Value (Sidecar_Content, "kind"));
         Parsed_Digest : Digest_Array;
         Parsed_Signature : Signature_Array;
      begin
         if Recorded_Kind /= Kind then
            raise Signing_Error with "artifact kind does not match signature metadata";
         end if;
         declare
            Algorithm : constant String := Content_Value (Sidecar_Content, "algorithm");
            Digest_Text : constant String := Content_Value (Sidecar_Content, "digest");
            Key : constant String := Content_Value (Sidecar_Content, "key_id");
            Signature_Text : constant String := Content_Value (Sidecar_Content, "signature");
         begin
            if Algorithm /= "ed25519-sha256" then
               raise Signing_Error with "unsupported artifact signature algorithm";
            elsif not Valid_Key_Id (Key) then
               raise Signing_Error with "artifact signature has an invalid key identity";
            end if;
            Decode_Hex (Digest_Text, Parsed_Digest, "artifact digest");
            Decode_Hex (Signature_Text, Parsed_Signature, "signature");
            return
              (Path => To_Unbounded_String (Sidecar), Kind => Kind,
               Algorithm => To_Unbounded_String (Algorithm),
               Digest => To_Unbounded_String (Digest_Text), Key => To_Unbounded_String (Key));
         end;
      end;
   exception
      when others =>
         Close (Descriptor);
         raise;
   end Inspect;

   function Valid_Key_Id (Id : String) return Boolean is
   begin
      if Id'Length /= 24 or else Id (Id'First .. Id'First + 7) /= "ed25519-" then return False; end if;
      for J in Id'First + 8 .. Id'Last loop
         if Id (J) not in '0' .. '9' | 'a' .. 'f' then return False; end if;
      end loop;
      return True;
   end Valid_Key_Id;

   procedure Require_Trust_Store (Store : String; Create : Boolean := False) is
   begin
      if not Project_Tools.Files.Exists (Store) and then Create then
         Ada.Directories.Create_Path (Store);
      end if;
      if not Project_Tools.Files.Directory_Exists (Store) or else Project_Tools.Links.Is_Link (Store) then
         raise Signing_Error with "trust store must be an existing nonsymlink directory: " & Store;
      end if;
   end Require_Trust_Store;

   procedure Create_Trusted_Key
     (Store, Name, Content : String)
   is
      Directory_FD : Interfaces.C.int := -1;
      File_FD      : Interfaces.C.int := -1;
      Created      : Boolean := False;
      Temp_Name    : constant String :=
        "." & Name & ".tmp-" & Ada.Strings.Fixed.Trim
          (Interfaces.C.int'Image (Process_Id), Ada.Strings.Both);
   begin
      Directory_FD := Open_Directory_Nofollow (Interfaces.C.To_C (Store));
      if Directory_FD < 0 then
         raise Signing_Error with "cannot open trust store securely: " & Store;
      end if;
      File_FD := Create_Public_At
        (Directory_FD, Interfaces.C.To_C (Temp_Name));
      if File_FD < 0 then
         raise Signing_Error with "trusted key destination already exists or is unsafe: " & Name;
      end if;
      Created := True;
      Write_All (File_FD, Content, "trusted key: " & Name);
      if not Close_Succeeded (File_FD) then
         raise Signing_Error with "cannot complete trusted key: " & Name;
      end if;
      if Link_At
        (Directory_FD, Interfaces.C.To_C (Temp_Name),
         Directory_FD, Interfaces.C.To_C (Name), 0) /= 0
      then
         raise Signing_Error with "trusted key destination already exists or is unsafe: " & Name;
      end if;
      if Unlink_At (Directory_FD, Interfaces.C.To_C (Temp_Name), 0) /= 0 then
         raise Signing_Error with "cannot complete trusted key: " & Name;
      end if;
      Created := False;
      if not Close_Succeeded (Directory_FD) then
         raise Signing_Error with "cannot close trust store securely: " & Store;
      end if;
   exception
      when others =>
         Close (File_FD);
         if Created and then Directory_FD >= 0 then
            declare Ignored : constant Interfaces.C.int :=
              Unlink_At (Directory_FD, Interfaces.C.To_C (Temp_Name), 0);
              pragma Unreferenced (Ignored);
            begin null; end;
         end if;
         Close (Directory_FD);
         raise;
   end Create_Trusted_Key;

   function Add_Trusted_Key (Store, Public_Key_Path : String) return String
   is separate;

   procedure Remove_Trusted_Key (Store, Id : String)
   is separate;

   function Trusted_Keys (Store : String) return Trusted_Key_Vectors.Vector
   is separate;

   procedure Verify_Trusted (Artifact, Store : String)
   is separate;

   procedure Generate_Keypair (Private_Key_Path, Public_Key_Path : String) is
      Rng    : CryptoLib.Random.Random_Source;
      Seed   : Key_Array;
      Public : Key_Array;
      Status : CryptoLib.Errors.Status;
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
      Create_Private_Key_File
        (Private_Key_Path, Seed, Public, Created => Private_Created);
      Create_Key_File
        (Public_Key_Path,
         "format=" & Public_Format & ASCII.LF & "public=" & Hex (Public) & ASCII.LF,
         "public key", Private_File => False, Created => Public_Created);
      CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
   exception
      when others =>
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         if Private_Created then Remove_Partial_File (Private_Key_Path); end if;
         if Public_Created then Remove_Partial_File (Public_Key_Path); end if;
         raise;
   end Generate_Keypair;

   procedure Sign (Artifact, Private_Key_Path : String) is
      Descriptor : Interfaces.C.int := -1;
      Kind : Project_Tools.Files.Unbounded_String;
      Seed, Public, Derived : Key_Array;
      Signature : Signature_Array;
      Artifact_Digest : Digest_Array;
      Status : CryptoLib.Errors.Status;
      Sidecar : Unbounded_String;
      Sidecar_Created : Boolean := False;
   begin
      Load_Private_Key (Private_Key_Path, Seed, Public);
      Status := CryptoLib.Ed25519.Public_Key_From_Seed (Seed, Derived);
      if Status /= CryptoLib.Errors.Ok or else Derived /= Public then
         raise Signing_Error with "private key file is internally inconsistent";
      end if;
      Open_Artifact_Content (Artifact, Descriptor, Kind);
      Sidecar := To_Unbounded_String
        (if To_String (Kind) = Backup_Kind
         then Project_Tools.Files.Join (Artifact, Backup_Signature)
         else Artifact & ".sig");
      if Project_Tools.Files.Exists (To_String (Sidecar)) then
         raise Signing_Error with
           "signature destination already exists: " & To_String (Sidecar);
      end if;
      Artifact_Digest := Digest (Descriptor, To_String (Kind), Artifact);
      if not Close_Succeeded (Descriptor) then
         raise Signing_Error with "cannot close artifact after signing: " & Artifact;
      end if;
      Status := CryptoLib.Ed25519.Sign (Seed, Public, Artifact_Digest, Signature);
      if Status /= CryptoLib.Errors.Ok then
         raise Signing_Error with "Ed25519 signing failed: " & Status'Image;
      end if;
      Create_Key_File
        (To_String (Sidecar), "format=" & Signature_Format & ASCII.LF &
           "algorithm=ed25519-sha256" & ASCII.LF &
           "key_id=" & Public_Id (Public) & ASCII.LF &
           "kind=" & Ada.Strings.Unbounded.To_String (Kind) & ASCII.LF &
           "digest=" & Hex (Artifact_Digest) & ASCII.LF &
           "signature=" & Hex (Signature) & ASCII.LF,
         "signature", Private_File => False, Created => Sidecar_Created);
      CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
   exception
      when others =>
         Close (Descriptor);
         CryptoLib.Secure_Wipe.Wipe (Seed'Address, Seed'Length);
         if Sidecar_Created then
            Remove_Partial_File (To_String (Sidecar));
         end if;
         raise;
   end Sign;

   procedure Verify_Content (Artifact, Public_Content : String) is
      Descriptor : Interfaces.C.int := -1;
      Kind : Project_Tools.Files.Unbounded_String;
      Public : Key_Array;
      Signature : Signature_Array;
      Recorded_Digest, Actual_Digest : Digest_Array;
      Status : CryptoLib.Errors.Status;
   begin
      if Content_Value (Public_Content, "format") /= Public_Format then
         raise Signing_Error with "unsupported public key format";
      end if;
      Open_Artifact_Content (Artifact, Descriptor, Kind);
      declare
         Sidecar : constant String :=
           (if To_String (Kind) = Backup_Kind
            then Project_Tools.Files.Join (Artifact, Backup_Signature)
            else Artifact & ".sig");
         Sidecar_Content : constant String :=
           Formatted_Content (Sidecar, Signature_Format);
      begin
         if Content_Value (Sidecar_Content, "algorithm") /= "ed25519-sha256" then
            raise Signing_Error with "unsupported artifact signature algorithm";
         elsif Content_Value (Sidecar_Content, "kind") /= To_String (Kind) then
            raise Signing_Error with "artifact signature kind does not match the artifact";
         end if;
         Decode_Hex (Content_Value (Public_Content, "public"), Public, "public key");
         declare
            Recorded_Id : constant String := Content_Value (Sidecar_Content, "key_id");
         begin
            if Recorded_Id /= "" and then Recorded_Id /= Public_Id (Public) then
               raise Signing_Error with
                 "artifact signature key identity does not match the public key";
            end if;
         end;
         Decode_Hex (Content_Value (Sidecar_Content, "signature"), Signature, "signature");
         Decode_Hex
           (Content_Value (Sidecar_Content, "digest"), Recorded_Digest, "artifact digest");
      end;
      Actual_Digest := Digest (Descriptor, To_String (Kind), Artifact);
      if not Close_Succeeded (Descriptor) then
         raise Signing_Error with "cannot close artifact after verification: " & Artifact;
      end if;
      if Recorded_Digest /= Actual_Digest then
         raise Signing_Error with "artifact digest does not match its signature metadata";
      end if;
      Status := CryptoLib.Ed25519.Verify (Public, Signature, Actual_Digest);
      if Status /= CryptoLib.Errors.Ok then
         raise Signing_Error with "artifact signature verification failed";
      end if;
   exception
      when others =>
         Close (Descriptor);
         raise;
   end Verify_Content;

   procedure Verify (Artifact, Public_Key_Path : String) is
      Public_Content : constant String := Formatted_Content (Public_Key_Path, Public_Format);
   begin
      Verify_Content (Artifact, Public_Content);
   end Verify;
end Ada_Quality.Artifact_Signing;
