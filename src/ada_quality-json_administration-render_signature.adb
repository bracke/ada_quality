separate (Ada_Quality.JSON_Administration)
function Render_Signature
     (Item : Ada_Quality.Artifact_Signing.Signature_Info; Verified : Boolean;
      Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("artifact-signature"));
      Doc.Insert (Root, "path", Doc.New_String (To_String (Item.Path)));
      Doc.Insert (Root, "artifact_kind", Doc.New_String (To_String (Item.Kind)));
      Doc.Insert (Root, "algorithm", Doc.New_String (To_String (Item.Algorithm)));
      Doc.Insert (Root, "digest", Doc.New_String (To_String (Item.Digest)));
      Doc.Insert (Root, "key_id", Doc.New_String (To_String (Item.Key)));
      Doc.Insert (Root, "verified", Doc.New_Boolean (Verified));
      Doc.Set_Root (Root); return Serialize (Doc, Pretty);
   end Render_Signature;
