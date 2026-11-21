separate (Ada_Quality.JSON_Administration)
function Render_Trusted_Keys
     (Items : Ada_Quality.Artifact_Signing.Trusted_Key_Vectors.Vector;
      Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object; Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("trusted-keys"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "id", Doc.New_String (To_String (Item.Id)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "keys", Values); Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Trusted_Keys;
