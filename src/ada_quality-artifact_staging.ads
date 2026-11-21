--  Secure staging of signed database artifacts before verification and use.
package Ada_Quality.Artifact_Staging is
   procedure Copy (Source, Destination : String);
   --  Copy one logical export (and its signature sidecar) or one physical
   --  backup tree into a new private destination without following links.
   --  Files, directories, depth, and bytes are bounded; exceptional exits
   --  clean up the private partial destination before propagating the error.
end Ada_Quality.Artifact_Staging;
