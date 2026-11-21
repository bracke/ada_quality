separate (Ada_Quality.JSON_Administration)
function Render_Policy
     (Item : Ada_Quality.Policy.Quality_Policy; Source : String := "";
      Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object; Values : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("policy"));
      Doc.Insert (Root, "source", Doc.New_String (Source));
      Doc.Insert (Root, "fingerprint", Doc.New_String (Ada_Quality.Policy.Fingerprint (Item)));
      Populate_Policy (Doc, Values, Item);
      Doc.Insert (Root, "values", Values);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Policy;
