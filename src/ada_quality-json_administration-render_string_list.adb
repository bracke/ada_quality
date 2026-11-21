separate (Ada_Quality.JSON_Administration)
function Render_String_List
     (Kind, Member : String; Items : String_Vectors.Vector;
      Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object; Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String (Kind));
      for Item of Items loop Doc.Append (Values, Doc.New_String (To_String (Item))); end loop;
      Doc.Insert (Root, Member, Values); Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_String_List;
