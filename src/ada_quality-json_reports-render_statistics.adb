separate (Ada_Quality.JSON_Reports)
function Render_Statistics
     (Item : Ada_Quality.Reporting.Snapshot_Statistics;
      Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      procedure Add (Name : String; Value : Long_Long_Integer) is
      begin
         Doc.Insert (Root, Name, Doc.New_Integer (Value));
      end Add;
   begin
      Add ("schema_version", 1);
      Doc.Insert (Root, "kind", Doc.New_String ("database-statistics"));
      Add ("projects", Long_Long_Integer (Item.Projects));
      Add ("assessments", Long_Long_Integer (Item.Assessments));
      Add ("results", Long_Long_Integer (Item.Results));
      Add ("measurements", Long_Long_Integer (Item.Measurements));
      Add ("findings", Long_Long_Integer (Item.Findings));
      Add ("executions", Long_Long_Integer (Item.Executions));
      Add ("events", Long_Long_Integer (Item.Events));
      Add ("total_rows", Long_Long_Integer (Item.Total_Rows));
      Add ("text_bytes", Item.Text_Bytes);
      Add ("row_limit", Long_Long_Integer (Item.Row_Limit));
      Add ("text_limit", Long_Long_Integer (Item.Text_Limit));
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Statistics;
