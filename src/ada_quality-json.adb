with Ada.Strings.Fixed;
with Ada_Quality.Archive_JSON;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Ada_Quality.JSON is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Ada_Quality.Indicators.Indicator_Category;
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
                 ((case Item.Status is
                     when Batch_Completed => "completed",
                     when Batch_Reused => "reused",
                     when Batch_Interrupted => "interrupted")));
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

   function Render_Reuse
     (Project_Id, Assessment_Id : Positive; Pretty : Boolean := False) return String
   is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-reuse"));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Project_Id)));
      Doc.Insert (Root, "assessment_id", Doc.New_Integer (Long_Long_Integer (Assessment_Id)));
      Doc.Insert (Root, "status", Doc.New_String ("reused"));
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Reuse;

   function Render_Check_Plan
     (Items : Check_Plan_Vectors.Vector; Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("check-plan"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
            Doc.Insert
              (Object, "source_fingerprint", Doc.New_String (To_String (Item.Source_Fingerprint)));
            Doc.Insert
              (Object, "policy_fingerprint", Doc.New_String (To_String (Item.Policy_Fingerprint)));
            Doc.Insert
              (Object, "toolchain_fingerprint", Doc.New_String (To_String (Item.Toolchain_Fingerprint)));
            Doc.Insert
              (Object, "reuse_eligible", Doc.New_Boolean (Item.Reusable_Assessment > 0));
            if Item.Will_Reuse then
               Doc.Insert (Object, "action", Doc.New_String ("reuse"));
            else
               Doc.Insert (Object, "action", Doc.New_String ("assess"));
            end if;
            if Item.Reusable_Assessment > 0 then
               Doc.Insert
                 (Object, "assessment_id",
                  Doc.New_Integer (Long_Long_Integer (Item.Reusable_Assessment)));
            end if;
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "projects", Values);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Check_Plan;

   function Render_Archive
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean := False;
      Max_Output_Bytes : Positive := 268_435_456;
      Project_Id       : Natural := 0;
      Project_Tag      : String := "";
      Since_Time       : Ada_Quality.Reporting.Optional_Timestamp := (Present => False);
      Until_Time       : Ada_Quality.Reporting.Optional_Timestamp := (Present => False)) return String
   is
   begin
      return Ada_Quality.Archive_JSON.Render
        (Item, Pretty, Max_Output_Bytes, Project_Id, Project_Tag, Since_Time, Until_Time);
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

   function Render_Status
     (Item     : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
      Pretty   : Boolean := False) return String
   is
      Doc      : Document;
      Root     : constant Node := Doc.New_Object;
      Nodes    : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("portfolio-status"));
      for Project of Projects loop
         declare
            Object     : constant Node := Doc.New_Object;
            Runs       : constant Ada_Quality.Reporting.Run_Vectors.Vector :=
              Ada_Quality.Reporting.Runs (Item, Project.Id);
            Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
              Ada_Quality.Reporting.Compare_Project (Item, Project.Id);
         begin
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Project.Id)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Project.Path)));
            Doc.Insert (Object, "enabled", Doc.New_Boolean (Project.Enabled));
            if Runs.Is_Empty then
               Doc.Insert (Object, "latest_assessment_id", Doc.New_Integer (0));
               Doc.Insert (Object, "latest_status", Doc.New_String ("never"));
               Doc.Insert (Object, "started_at", Doc.New_String (""));
            else
               declare
                  Run : constant Ada_Quality.Reporting.Run_Record := Runs.Last_Element;
               begin
                  Doc.Insert
                    (Object, "latest_assessment_id", Doc.New_Integer (Long_Long_Integer (Run.Id)));
                  Doc.Insert (Object, "latest_status", Doc.New_String (Status_Image (Run.State)));
                  Doc.Insert
                    (Object, "started_at", Doc.New_String (Ada_Quality.Reporting.Image (Run.Started_At)));
               end;
            end if;
            Doc.Insert
              (Object, "comparison_status",
               Doc.New_String (Ada_Quality.History.Image (Comparison.Selection.Status)));
            Doc.Insert
              (Object, "regression_count",
               Doc.New_Integer (Long_Long_Integer (Comparison.Changes.Length)));
            Doc.Append (Nodes, Object);
         end;
      end loop;
      Doc.Insert (Root, "projects", Nodes);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Status;

   function Render_Status
     (Item : Ada_Quality.Reporting.Session; Pretty : Boolean := False) return String is
   begin
      return Render_Status
        (Item, Ada_Quality.Reporting.Projects (Item), Pretty);
   end Render_Status;

   function Render_Scan
     (Project_Id : Positive;
      Metrics    : Ada_Quality.Checks.Source_Analysis;
      Pretty     : Boolean := False) return String
   is
      Doc      : Document;
      Root     : constant Node := Doc.New_Object;
      Counts   : constant Node := Doc.New_Object;
      Findings : constant Node := Doc.New_Array;
      Violations : constant Natural :=
        Metrics.Long_Lines + Metrics.Hygiene_Errors + Metrics.Naming_Errors +
        Metrics.Oversized_Files + Metrics.Undocumented_Specs + Metrics.Broad_Handlers +
        Metrics.Complexity_Violations + Metrics.Secret_Matches + Metrics.Unsafe_Processes;

      procedure Count (Name : String; Value : Natural) is
      begin
         Doc.Insert (Counts, Name, Doc.New_Integer (Long_Long_Integer (Value)));
      end Count;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("changed-source-scan"));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Project_Id)));
      Count ("files", Metrics.File_Count);
      Count ("lines", Metrics.Lines);
      Count ("long_lines", Metrics.Long_Lines);
      Count ("hygiene_errors", Metrics.Hygiene_Errors);
      Count ("naming_errors", Metrics.Naming_Errors);
      Count ("oversized_files", Metrics.Oversized_Files);
      Count ("undocumented_specs", Metrics.Undocumented_Specs);
      Count ("broad_handlers", Metrics.Broad_Handlers);
      Count ("complexity_violations", Metrics.Complexity_Violations);
      Count ("secret_matches", Metrics.Secret_Matches);
      Count ("unsafe_processes", Metrics.Unsafe_Processes);
      Count ("violations", Violations);
      Doc.Insert (Root, "counts", Counts);
      for Finding of Metrics.Findings loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "indicator", Doc.New_String (Image (Finding.Indicator)));
            Doc.Insert (Object, "rule", Doc.New_String (To_String (Finding.Rule)));
            Doc.Insert (Object, "severity", Doc.New_String (Severity'Image (Finding.Level)));
            Doc.Insert (Object, "message", Doc.New_String (To_String (Finding.Message)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Finding.Relative_Path)));
            Doc.Insert (Object, "line", Doc.New_Integer (Long_Long_Integer (Finding.Line)));
            Doc.Insert (Object, "fingerprint", Doc.New_String (To_String (Finding.Fingerprint)));
            Doc.Append (Findings, Object);
         end;
      end loop;
      Doc.Insert (Root, "findings", Findings);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Scan;

   function Render_Findings
     (Items : Finding_Vectors.Vector;
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
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Findings;

   function Render_Projects
     (Items : Ada_Quality.Reporting.Project_Vectors.Vector;
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
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Projects;

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

   function Render_Aliases
     (Items : Ada_Quality.Reporting.Alias_Vectors.Vector;
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
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Aliases;

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

   function Render_Indicators
     (Filter_Category : Boolean := False;
      Category        : Ada_Quality.Indicators.Indicator_Category := Ada_Quality.Indicators.Structure;
      Pretty          : Boolean := False) return String
   is
      Doc      : Document;
      Root     : constant Node := Doc.New_Object;
      Items    : constant Node := Doc.New_Array;
      Registry : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("indicator-catalog"));
      for Id in Indicator_Id loop
         declare
            Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Registry (Id);
         begin
            if not Filter_Category or else Descriptor.Category = Category then
               declare
                  Object       : constant Node := Doc.New_Object;
                  Prerequisites : constant Node := Doc.New_Array;
               begin
                  Doc.Insert (Object, "id", Doc.New_String (Image (Id)));
                  Doc.Insert (Object, "name", Doc.New_String (Descriptor.Name.all));
                  Doc.Insert
                    (Object, "category",
                     Doc.New_String (Ada_Quality.Indicators.Indicator_Category'Image (Descriptor.Category)));
                  Doc.Insert (Object, "version", Doc.New_Integer (Long_Long_Integer (Descriptor.Version)));
                  Doc.Insert
                    (Object, "measurement_version",
                     Doc.New_Integer (Long_Long_Integer (Descriptor.Measurement_Version)));
                  Doc.Insert (Object, "unit", Doc.New_String (Descriptor.Unit_Name.all));
                  Doc.Insert (Object, "gate", Doc.New_Boolean (Descriptor.Gate));
                  Doc.Insert
                    (Object, "trend",
                     Doc.New_String (Ada_Quality.Indicators.Metric_Direction'Image (Descriptor.Trend)));
                  for Dependency in Indicator_Id loop
                     if Descriptor.Prerequisites (Dependency) then
                        Doc.Append (Prerequisites, Doc.New_String (Image (Dependency)));
                     end if;
                  end loop;
                  Doc.Insert (Object, "prerequisites", Prerequisites);
                  Doc.Insert
                    (Object, "remediation", Doc.New_String (Ada_Quality.Indicators.Remediation (Id)));
                  Doc.Append (Items, Object);
               end;
            end if;
         end;
      end loop;
      Doc.Insert (Root, "indicators", Items);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Indicators;
end Ada_Quality.JSON;
