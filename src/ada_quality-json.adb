with Ada_Quality.Archive_JSON;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Ada_Quality.JSON is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Jsonlib.Documents;

   procedure Populate_Assessment
     (Doc : in out Document; Root : Node; Item : Assessment)
   is
      Results : constant Node := Doc.New_Array;
      Executions : constant Node := Doc.New_Array;

      procedure Append_Result (R : Indicator_Result) is
         Object   : constant Node := Doc.New_Object;
         Findings : constant Node := Doc.New_Array;
         Measurement : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Object, "indicator", Doc.New_String (Image (R.Indicator)));
         Doc.Insert (Object, "execution", Doc.New_String (Image (R.Execution)));
         Doc.Insert (Object, "compliance", Doc.New_String (Image (R.Compliance)));
         Doc.Insert (Object, "applicable", Doc.New_Boolean (R.Applicable));
         Doc.Insert (Object, "summary", Doc.New_String (To_String (R.Summary)));
         Doc.Insert (Object, "evidence", Doc.New_String (To_String (R.Evidence)));
         Doc.Insert
           (Measurement, "kind", Doc.New_String (Ada_Quality.Types.Value_Kind'Image (R.Measurement.Kind)));
         case R.Measurement.Kind is
            when Unavailable_Value =>
               Doc.Insert (Measurement, "reason", Doc.New_String (To_String (R.Measurement.Reason)));
            when Boolean_Value =>
               Doc.Insert (Measurement, "value", Doc.New_Boolean (R.Measurement.Boolean_Data));
            when Integer_Value =>
               Doc.Insert (Measurement, "value", Doc.New_Integer (R.Measurement.Integer_Data));
            when Decimal_Value =>
               Doc.Insert (Measurement, "basis_points", Doc.New_Integer (R.Measurement.Basis_Points));
            when Text_Value | Enum_Value =>
               Doc.Insert (Measurement, "value", Doc.New_String (To_String (R.Measurement.Text_Data)));
         end case;
         Doc.Insert (Object, "measurement", Measurement);
         for F of R.Findings loop
            declare
               Finding : constant Node := Doc.New_Object;
            begin
               Doc.Insert (Finding, "rule", Doc.New_String (To_String (F.Rule)));
               Doc.Insert (Finding, "severity", Doc.New_String (Severity'Image (F.Level)));
               Doc.Insert (Finding, "message", Doc.New_String (To_String (F.Message)));
               Doc.Insert (Finding, "path", Doc.New_String (To_String (F.Relative_Path)));
               Doc.Insert (Finding, "line", Doc.New_Integer (Long_Long_Integer (F.Line)));
               Doc.Insert (Finding, "fingerprint", Doc.New_String (To_String (F.Fingerprint)));
               Doc.Append (Findings, Finding);
            end;
         end loop;
         Doc.Insert (Object, "findings", Findings);
         Doc.Append (Results, Object);
      end Append_Result;

      procedure Append_Execution (E : Tool_Execution) is
         Object : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Object, "tool", Doc.New_String (To_String (E.Tool)));
         Doc.Insert (Object, "command", Doc.New_String (To_String (E.Command)));
         Doc.Insert (Object, "status", Doc.New_String (Image (E.Status)));
         Doc.Insert (Object, "exit_code", Doc.New_Integer (Long_Long_Integer (E.Exit_Code)));
         Doc.Insert (Object, "output_digest", Doc.New_String (To_String (E.Output_Digest)));
         Doc.Insert (Object, "output_bytes", Doc.New_Integer (E.Output_Bytes));
         Doc.Insert (Object, "truncated", Doc.New_Boolean (E.Truncated));
         Doc.Append (Executions, Object);
      end Append_Execution;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "assessment_id", Doc.New_Integer (Long_Long_Integer (Item.Id)));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
      Doc.Insert (Root, "project_path", Doc.New_String (To_String (Item.Project_Path)));
      Doc.Insert (Root, "source_fingerprint", Doc.New_String (To_String (Item.Source_Fingerprint)));
      Doc.Insert (Root, "policy_fingerprint", Doc.New_String (To_String (Item.Policy_Fingerprint)));
      Doc.Insert (Root, "toolchain_fingerprint", Doc.New_String (To_String (Item.Toolchain_Fingerprint)));
      Doc.Insert (Root, "status", Doc.New_String (Assessment_Status'Image (Item.Status)));
      for R of Item.Results loop
         Append_Result (R);
      end loop;
      for E of Item.Executions loop
         Append_Execution (E);
      end loop;
      Doc.Insert (Root, "results", Results);
      Doc.Insert (Root, "executions", Executions);
   end Populate_Assessment;

   function Serialize
     (Doc : Document; Pretty : Boolean) return String is
     (Jsonlib.Serializers.To_String
        (Doc,
         (Form => (if Pretty then Jsonlib.Serializers.Pretty else Jsonlib.Serializers.Compact),
          Indent => 2, Escape_Non_Ascii => False, Sort_Members => True)));

   function Render (Item : Assessment; Pretty : Boolean := False) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
   begin
      Populate_Assessment (Doc, Root, Item);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render;

   function Render_Batch
     (Items : Batch_Outcome_Vectors.Vector; Pretty : Boolean := False) return String
   is
      Doc      : Document;
      Root     : constant Node := Doc.New_Object;
      Outcomes : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-batch"));
      for Item of Items loop
         declare
            Outcome : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Outcome, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert
              (Outcome, "assessment_id", Doc.New_Integer (Long_Long_Integer (Item.Assessment_Id)));
            Doc.Insert
              (Outcome, "status",
               Doc.New_String
                 ((if Item.Status = Batch_Completed then "completed" else "interrupted")));
            Doc.Insert (Outcome, "diagnostic", Doc.New_String (To_String (Item.Diagnostic)));
            if Item.Status = Batch_Completed then
               declare
                  Assessment_Object : constant Node := Doc.New_Object;
               begin
                  Populate_Assessment (Doc, Assessment_Object, Item.Value);
                  Doc.Insert (Outcome, "assessment", Assessment_Object);
               end;
            end if;
            Doc.Append (Outcomes, Outcome);
         end;
      end loop;
      Doc.Insert (Root, "outcomes", Outcomes);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Batch;

   function Render_Archive
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean := False;
      Max_Output_Bytes : Positive := 268_435_456) return String
   is
   begin
      return Ada_Quality.Archive_JSON.Render (Item, Pretty, Max_Output_Bytes);
   end Render_Archive;

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

   procedure Populate_Trend_Points
     (Doc : in out Document;
      Parent : Node;
      Points : Ada_Quality.History.Trend_Vectors.Vector)
   is
      Items : constant Node := Doc.New_Array;
   begin
      for Point of Points loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "run_id", Doc.New_Integer (Long_Long_Integer (Point.Run_Id)));
            Doc.Insert (Item, "value", Doc.New_Integer (Point.Value));
            Doc.Append (Items, Item);
         end;
      end loop;
      Doc.Insert (Parent, "points", Items);
   end Populate_Trend_Points;

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

   function Status_Image (Value : Assessment_Status) return String is
     (case Value is
         when Assessment_Running => "running",
         when Assessment_Completed => "completed",
         when Assessment_Invalid => "invalid",
         when Assessment_Interrupted => "interrupted");

   function Render_History
     (Items : Ada_Quality.Reporting.Run_Vectors.Vector;
      Pretty : Boolean := False) return String
   is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Runs : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-history"));
      for Run of Items loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "assessment_id", Doc.New_Integer (Long_Long_Integer (Run.Id)));
            Doc.Insert (Item, "project_id", Doc.New_Integer (Long_Long_Integer (Run.Project_Id)));
            Doc.Insert (Item, "status", Doc.New_String (Status_Image (Run.State)));
            Doc.Insert (Item, "started_at", Doc.New_String (Ada_Quality.Reporting.Image (Run.Started_At)));
            Doc.Insert (Item, "finished_at", Doc.New_String (Ada_Quality.Reporting.Image (Run.Finished_At)));
            Doc.Insert (Item, "source_fingerprint", Doc.New_String (To_String (Run.Source_Id)));
            Doc.Insert (Item, "policy_fingerprint", Doc.New_String (To_String (Run.Policy_Id)));
            Doc.Insert (Item, "toolchain_fingerprint", Doc.New_String (To_String (Run.Toolchain_Id)));
            Doc.Append (Runs, Item);
         end;
      end loop;
      Doc.Insert (Root, "runs", Runs);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_History;

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
end Ada_Quality.JSON;
