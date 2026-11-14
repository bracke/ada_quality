with Ada.Strings.Fixed;
with Ada_Quality.History;
with Jsonlib.Documents;
with Jsonlib.Serializers;

package body Ada_Quality.JSON is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use Jsonlib.Documents;
   use type Ada_Quality.History.Comparison_Status;

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
         Doc.Insert (Object, "output_bytes", Doc.New_Integer (Long_Long_Integer (E.Output_Bytes)));
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
     (Store : in out Ada_Quality.Storage.Store; Pretty : Boolean := False) return String
   is
      Doc         : Document;
      Root        : constant Node := Doc.New_Object;
      Projects    : constant Node := Doc.New_Array;
      Assessments : constant Node := Doc.New_Array;
      Results     : constant Node := Doc.New_Array;
      Findings    : constant Node := Doc.New_Array;
      Measurements : constant Node := Doc.New_Array;
      Executions   : constant Node := Doc.New_Array;
      Events       : constant Node := Doc.New_Array;
      Comparisons  : constant Node := Doc.New_Array;
      Regressions  : constant Node := Doc.New_Array;
      Settings    : constant Jsonlib.Serializers.Options :=
        (Form => (if Pretty then Jsonlib.Serializers.Pretty else Jsonlib.Serializers.Compact),
         Indent => 2, Escape_Non_Ascii => False, Sort_Members => True);

      procedure Append_Project_Comparison (P : Ada_Quality.Storage.Project_Info) is
         Runs : constant Ada_Quality.Storage.History_Vectors.Vector :=
           Ada_Quality.Storage.History (Store, P.Id);
         Selection : constant Ada_Quality.History.Comparison_Selection :=
           Ada_Quality.History.Select_Comparison (Runs);

         function Find_Run (Id : Positive) return Ada_Quality.Storage.History_Item is
         begin
            for Run of Runs loop
               if Run.Id = Id then return Run; end if;
            end loop;
            raise Constraint_Error with "selected assessment is absent from project history";
         end Find_Run;

         function Findings_Before
           (Baseline, Current : Ada_Quality.Storage.History_Item)
            return Ada_Quality.Storage.Detail_Vectors.Vector
         is
            Result : Ada_Quality.Storage.Detail_Vectors.Vector;
         begin
            for Run of Runs loop
               exit when Run.Id = Baseline.Id;
               if Ada_Quality.History.Compatible (Run, Current) then
                  Result.Append_Vector (Ada_Quality.Storage.Findings (Store, Run.Id));
               end if;
            end loop;
            return Result;
         end Findings_Before;
      begin
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (P.Id)));
            Doc.Insert
              (Object, "status", Doc.New_String (Ada_Quality.History.Image (Selection.Status)));
            Doc.Insert
              (Object, "current_id", Doc.New_Integer (Long_Long_Integer (Selection.Current_Id)));
            Doc.Insert
              (Object, "baseline_id", Doc.New_Integer (Long_Long_Integer (Selection.Baseline_Id)));
            Doc.Insert (Object, "policy_changed", Doc.New_Boolean (Selection.Policy_Changed));
            Doc.Append (Comparisons, Object);
         end;
         if Selection.Status /= Ada_Quality.History.Comparison_Available then return; end if;
         declare
            Current : constant Ada_Quality.Storage.History_Item :=
              Find_Run (Positive (Selection.Current_Id));
            Baseline : constant Ada_Quality.Storage.History_Item :=
              Find_Run (Positive (Selection.Baseline_Id));
         begin
            declare
               Changes : constant Ada_Quality.History.Regression_Vectors.Vector :=
                 Ada_Quality.History.Compare
                   (Baseline, Current,
                    Ada_Quality.Storage.Results (Store, Baseline.Id),
                    Ada_Quality.Storage.Results (Store, Current.Id),
                    Ada_Quality.Storage.Measurements (Store, Baseline.Id),
                    Ada_Quality.Storage.Measurements (Store, Current.Id),
                    Ada_Quality.Storage.Findings (Store, Baseline.Id),
                    Ada_Quality.Storage.Findings (Store, Current.Id),
                    Findings_Before (Baseline, Current));
            begin
               for Change of Changes loop
                  declare
                     Object : constant Node := Doc.New_Object;
                  begin
                     Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (P.Id)));
                     Doc.Insert (Object, "baseline_id", Doc.New_Integer (Long_Long_Integer (Baseline.Id)));
                     Doc.Insert (Object, "current_id", Doc.New_Integer (Long_Long_Integer (Current.Id)));
                     Doc.Insert (Object, "indicator", Doc.New_String (Image (Change.Indicator)));
                     Doc.Insert (Object, "kind", Doc.New_String (Ada_Quality.History.Image (Change.Kind)));
                     Doc.Insert (Object, "before", Doc.New_String (To_String (Change.Before)));
                     Doc.Insert (Object, "after", Doc.New_String (To_String (Change.After)));
                     Doc.Append (Regressions, Object);
                  end;
               end loop;
            end;
         end;
      end Append_Project_Comparison;

      procedure Append_All_Comparisons is
      begin
         for P of Ada_Quality.Storage.Projects (Store, Include_Removed => True) loop
            Append_Project_Comparison (P);
         end loop;
      end Append_All_Comparisons;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (2));
      for P of Ada_Quality.Storage.Projects (Store, Include_Removed => True) loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (P.Id)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (P.Path)));
            Doc.Insert (Object, "enabled", Doc.New_Boolean (P.Enabled));
            Doc.Insert (Object, "removed", Doc.New_Boolean (P.Removed));
            Doc.Append (Projects, Object);
         end;
      end loop;
      for H of Ada_Quality.Storage.History (Store) loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (H.Id)));
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (H.Project_Id)));
            Doc.Insert (Object, "status", Doc.New_String (To_String (H.Status)));
            Doc.Insert (Object, "summary", Doc.New_String (To_String (H.Summary)));
            Doc.Insert (Object, "source_fingerprint", Doc.New_String (To_String (H.Source_Fingerprint)));
            Doc.Insert (Object, "policy_fingerprint", Doc.New_String (To_String (H.Policy_Fingerprint)));
            Doc.Insert
              (Object, "toolchain_fingerprint", Doc.New_String (To_String (H.Toolchain_Fingerprint)));
            Doc.Append (Assessments, Object);
         end;
      end loop;
      for M of Ada_Quality.Storage.Measurements (Store) loop
         declare
            Object : constant Node := Doc.New_Object;
            State : constant String := To_String (M.State);
            Separator : constant Natural := Ada.Strings.Fixed.Index (State, ";");
            Kind : constant String :=
              (if Separator = 0 then State else State (State'First .. Separator - 1));
         begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (M.Id)));
            Doc.Insert (Object, "assessment_id", Doc.New_Integer (Long_Long_Integer (M.Run_Id)));
            Doc.Insert (Object, "indicator", Doc.New_String (To_String (M.Kind)));
            Doc.Insert (Object, "kind", Doc.New_String (Kind));
            Doc.Insert (Object, "semantics", Doc.New_String (State));
            Doc.Insert (Object, "value", Doc.New_String (To_String (M.Summary)));
            Doc.Append (Measurements, Object);
         end;
      end loop;
      for R of Ada_Quality.Storage.Results (Store) loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (R.Id)));
            Doc.Insert (Object, "assessment_id", Doc.New_Integer (Long_Long_Integer (R.Run_Id)));
            Doc.Insert (Object, "indicator", Doc.New_String (To_String (R.Kind)));
            Doc.Insert (Object, "state", Doc.New_String (To_String (R.State)));
            Doc.Insert (Object, "summary", Doc.New_String (To_String (R.Summary)));
            Doc.Append (Results, Object);
         end;
      end loop;
      for E of Ada_Quality.Storage.Executions (Store) loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (E.Id)));
            Doc.Insert (Object, "assessment_id", Doc.New_Integer (Long_Long_Integer (E.Run_Id)));
            Doc.Insert (Object, "tool", Doc.New_String (To_String (E.Kind)));
            Doc.Insert (Object, "status", Doc.New_String (To_String (E.State)));
            Doc.Insert (Object, "evidence", Doc.New_String (To_String (E.Summary)));
            Doc.Append (Executions, Object);
         end;
      end loop;
      for E of Ada_Quality.Storage.Events (Store) loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (E.Id)));
            Doc.Insert (Object, "assessment_id", Doc.New_Integer (Long_Long_Integer (E.Run_Id)));
            Doc.Insert (Object, "kind", Doc.New_String (To_String (E.Kind)));
            Doc.Insert (Object, "state", Doc.New_String (To_String (E.State)));
            Doc.Insert (Object, "summary", Doc.New_String (To_String (E.Summary)));
            Doc.Append (Events, Object);
         end;
      end loop;
      for F of Ada_Quality.Storage.Findings (Store) loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "id", Doc.New_Integer (Long_Long_Integer (F.Id)));
            Doc.Insert (Object, "assessment_id", Doc.New_Integer (Long_Long_Integer (F.Run_Id)));
            Doc.Insert (Object, "fingerprint", Doc.New_String (To_String (F.Kind)));
            Doc.Insert (Object, "severity", Doc.New_String (To_String (F.State)));
            Doc.Insert (Object, "summary", Doc.New_String (To_String (F.Summary)));
            Doc.Append (Findings, Object);
         end;
      end loop;
      Append_All_Comparisons;
      Doc.Insert (Root, "projects", Projects);
      Doc.Insert (Root, "assessments", Assessments);
      Doc.Insert (Root, "results", Results);
      Doc.Insert (Root, "measurements", Measurements);
      Doc.Insert (Root, "findings", Findings);
      Doc.Insert (Root, "executions", Executions);
      Doc.Insert (Root, "events", Events);
      Doc.Insert (Root, "comparisons", Comparisons);
      Doc.Insert (Root, "regressions", Regressions);
      Doc.Set_Root (Root);
      return Jsonlib.Serializers.To_String (Doc, Settings);
   end Render_Archive;
end Ada_Quality.JSON;
