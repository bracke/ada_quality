separate (Ada_Quality.JSON_Reports)
function Render_Projects
     (Items : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("project-list"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (Item.Id)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
            declare
               Tags : constant Node := Doc.New_Array;
               Text : constant String := To_String (Item.Tags);
               Start : Natural := (if Text'Length = 0 then 0 else Text'First);
            begin
               while Start /= 0 and then Start <= Text'Last loop
                  declare Stop : Natural := Ada.Strings.Fixed.Index (Text, ",", From => Start); begin
                     if Stop = 0 then Stop := Text'Last + 1; end if;
                     Doc.Append (Tags, Doc.New_String (Text (Start .. Stop - 1)));
                     Start := Stop + 1;
                  end;
               end loop;
               Doc.Insert (Object, "tags", Tags);
            end;
            Doc.Insert (Object, "enabled", Doc.New_Boolean (Item.Enabled));
            Doc.Insert (Object, "removed", Doc.New_Boolean (Item.Removed));
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "projects", Values);
      Populate_Page (Doc, Root, Page);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Projects;
