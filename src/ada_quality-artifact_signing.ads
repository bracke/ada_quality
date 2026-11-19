--  Ed25519 authentication for physical backups and logical exports.
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

   function Signature_Path (Artifact : String) return String;
   --  Return the signature sidecar location for Artifact.
end Ada_Quality.Artifact_Signing;
