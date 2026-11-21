with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Ed25519 authentication and local trust management for database artifacts.
package Ada_Quality.Artifact_Signing is
   Signing_Error : exception;
   --  Raised for malformed keys, missing signatures, invalid signatures, or cryptographic failures.

   procedure Generate_Keypair (Private_Key_Path, Public_Key_Path : String);
   --  Generate an Ed25519 keypair. Existing destinations are never overwritten.
   --  The private key is created with owner-only permissions.

   procedure Sign (Artifact, Private_Key_Path : String);
   --  Authenticate a physical backup directory or logical export file.
   --  The signature is written inside a backup or beside an export.

   procedure Verify (Artifact, Public_Key_Path : String);
   --  Verify an artifact signature using a trusted Ed25519 public key.

   function Key_Id (Public_Key_Path : String) return String;
   --  Return the stable SHA-256-derived identity of a public key.

   type Signature_Info is record
      Path      : Ada.Strings.Unbounded.Unbounded_String;
      Kind      : Ada.Strings.Unbounded.Unbounded_String;
      Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      Digest    : Ada.Strings.Unbounded.Unbounded_String;
      Key       : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Inspect (Artifact : String) return Signature_Info;
   --  Parse signature metadata without treating it as verified evidence.

   type Trusted_Key is record
      Id   : Ada.Strings.Unbounded.Unbounded_String;
      Path : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   package Trusted_Key_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Trusted_Key);

   function Add_Trusted_Key (Store, Public_Key_Path : String) return String;
   --  Add a public key to Store under its stable identity; identical repeats are accepted.

   procedure Remove_Trusted_Key (Store, Id : String);
   --  Revoke local trust by removing Id from Store.

   function Trusted_Keys (Store : String) return Trusted_Key_Vectors.Vector;
   --  List valid trusted keys in identity order.

   procedure Verify_Trusted (Artifact, Store : String);
   --  Resolve the signature key identity in Store and verify the artifact.

   function Signature_Path (Artifact : String) return String;
   --  Return the signature sidecar location for Artifact.
end Ada_Quality.Artifact_Signing;
