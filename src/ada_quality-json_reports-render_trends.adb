separate (Ada_Quality.JSON_Reports)
function Render_Trends
     (Project_Id : Positive;
      Series     : Metric_Series_Vectors.Vector;
      Pretty     : Boolean := False) return String
   is
      Doc   : Document;
      Root  : constant Node := Doc.New_Object;
      Items : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("metric-trends"));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Project_Id)));
      for Series_Item of Series loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "indicator", Doc.New_String (Image (Series_Item.Indicator)));
            Doc.Insert (Item, "unit", Doc.New_String (To_String (Series_Item.Unit_Name)));
            Populate_Trend_Points (Doc, Item, Series_Item.Points);
            Doc.Append (Items, Item);
         end;
      end loop;
      Doc.Insert (Root, "series", Items);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Trends;
