with Ada_Quality.History;

separate (Ada_Quality.JSON_Assessments)
function Render_Comparison
     (Item : Ada_Quality.Reporting.Project_Comparison;
      Pretty : Boolean := False) return String
   is
      Doc     : Document;
      Root    : constant Node := Doc.New_Object;
      Changes : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-comparison"));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
      Doc.Insert
        (Root, "status", Doc.New_String (Ada_Quality.History.Image (Item.Selection.Status)));
      Doc.Insert (Root, "baseline_id", Doc.New_Integer (Long_Long_Integer (Item.Selection.Baseline_Id)));
      Doc.Insert (Root, "current_id", Doc.New_Integer (Long_Long_Integer (Item.Selection.Current_Id)));
      Doc.Insert (Root, "policy_changed", Doc.New_Boolean (Item.Selection.Policy_Changed));
      for Change of Item.Changes loop
         declare
            Change_Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Change_Item, "indicator", Doc.New_String (Image (Change.Indicator)));
            Doc.Insert (Change_Item, "change", Doc.New_String (Ada_Quality.History.Image (Change.Kind)));
            Doc.Insert (Change_Item, "before", Doc.New_String (To_String (Change.Before)));
            Doc.Insert (Change_Item, "after", Doc.New_String (To_String (Change.After)));
            Doc.Append (Changes, Change_Item);
         end;
      end loop;
      Doc.Insert (Root, "changes", Changes);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Comparison;
