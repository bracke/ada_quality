separate (Ada_Quality.JSON_Assessments)
function Render_Aliases
     (Items : Ada_Quality.Reporting.Alias_Vectors.Vector;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-aliases"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "name", Doc.New_String (To_String (Item.Name)));
            Doc.Insert (Object, "assessment_id", Doc.New_Integer (Long_Long_Integer (Item.Run_Id)));
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "aliases", Values);
      Populate_Page (Doc, Root, Page);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Aliases;
