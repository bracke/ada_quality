separate (Ada_Quality.JSON_Reports)
function Render_Discovery
     (Items : Discovery_Vectors.Vector; Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("project-discovery"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert
              (Object, "status", Doc.New_String
                 ((case Item.Status is
                     when Already_Registered => "registered",
                     when Discovered => "found",
                     when Added => "added",
                     when Missing => "missing",
                     when Removed => "removed")));
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "projects", Values);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Discovery;
