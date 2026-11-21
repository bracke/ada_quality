separate (Ada_Quality.JSON_Administration)
function Render_Retention
     (Items : Ada_Quality.Storage.History_Vectors.Vector;
      Before : String; Keep : Natural; Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("retention-preview"));
      Doc.Insert (Root, "before", Doc.New_String (Before));
      Doc.Insert (Root, "keep", Doc.New_Integer (Long_Long_Integer (Keep)));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "assessment_id", Doc.New_Integer (Long_Long_Integer (Item.Id)));
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert (Object, "status", Doc.New_String (To_String (Item.Status)));
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "candidates", Values);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Retention;
