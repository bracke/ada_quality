separate (Ada_Quality.JSON_Reports)
function Render_Comparisons
     (Items : Comparison_Vectors.Vector; Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object; Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("regressions"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; Changes : constant Node := Doc.New_Array; begin
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert (Object, "status", Doc.New_String (Ada_Quality.History.Image (Item.Selection.Status)));
            Doc.Insert (Object, "baseline_id", Doc.New_Integer (Long_Long_Integer (Item.Selection.Baseline_Id)));
            Doc.Insert (Object, "current_id", Doc.New_Integer (Long_Long_Integer (Item.Selection.Current_Id)));
            for Change of Item.Changes loop
               declare C : constant Node := Doc.New_Object; begin
                  Doc.Insert (C, "indicator", Doc.New_String (Image (Change.Indicator)));
                  Doc.Insert (C, "change", Doc.New_String (Ada_Quality.History.Image (Change.Kind)));
                  Doc.Insert (C, "before", Doc.New_String (To_String (Change.Before)));
                  Doc.Insert (C, "after", Doc.New_String (To_String (Change.After)));
                  Doc.Append (Changes, C);
               end;
            end loop;
            Doc.Insert (Object, "changes", Changes); Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "projects", Values); Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Comparisons;
