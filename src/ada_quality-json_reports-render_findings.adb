separate (Ada_Quality.JSON_Reports)
function Render_Findings
     (Items : Finding_Vectors.Vector;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("findings"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "indicator", Doc.New_String (Image (Item.Indicator)));
            Doc.Insert (Object, "rule", Doc.New_String (To_String (Item.Rule)));
            Doc.Insert (Object, "severity", Doc.New_String (Severity'Image (Item.Level)));
            Doc.Insert (Object, "message", Doc.New_String (To_String (Item.Message)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Relative_Path)));
            Doc.Insert (Object, "line", Doc.New_Integer (Long_Long_Integer (Item.Line)));
            Doc.Insert (Object, "fingerprint", Doc.New_String (To_String (Item.Fingerprint)));
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "findings", Values);
      Populate_Page (Doc, Root, Page);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Findings;
