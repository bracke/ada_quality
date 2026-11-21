separate (Ada_Quality.JSON_Reports)
function Render_Trend
     (Project_Id : Positive;
      Indicator  : Ada_Quality.Types.Indicator_Id;
      Unit_Name  : String;
      Points     : Ada_Quality.History.Trend_Vectors.Vector;
      Pretty     : Boolean := False) return String
   is
      Doc   : Document;
      Root  : constant Node := Doc.New_Object;
      Items : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("metric-trend"));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Project_Id)));
      Doc.Insert (Root, "indicator", Doc.New_String (Image (Indicator)));
      Doc.Insert (Root, "unit", Doc.New_String (Unit_Name));
      for Point of Points loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "run_id", Doc.New_Integer (Long_Long_Integer (Point.Run_Id)));
            Doc.Insert (Item, "value", Doc.New_Integer (Point.Value));
            Doc.Append (Items, Item);
         end;
      end loop;
      Doc.Insert (Root, "points", Items);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Trend;
