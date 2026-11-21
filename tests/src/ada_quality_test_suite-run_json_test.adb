separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_json_test owner=core expires=2027-11-21 justification=one-component-fixture-matrix
procedure Run_JSON_Test is
begin
declare
   Value : Assessment;
   Text  : Ada.Strings.Unbounded.Unbounded_String;
   Doc   : Jsonlib.Documents.Document;
   Error : Jsonlib.Errors.Error_Info;
begin
   Value.Project_Id := 1;
   Value.Status := Assessment_Completed;
   Value.Toolchain_Fingerprint := To_Unbounded_String ("toolchain");
   Value.Executions.Append
     (Tool_Execution'(Tool => To_Unbounded_String ("fixture"),
      Command => To_Unbounded_String ("/bin/fixture"), Status => Tool_Completed,
      Exit_Code => 0, Output_Digest => To_Unbounded_String ("a430d84680aabd0b"),
      Output_Bytes => 3, Truncated => False));
   for Indicator in Indicator_Id loop
      declare
         Result : Indicator_Result :=
           (Indicator => Indicator, Execution => Succeeded, Compliance => Pass, Applicable => True,
            Summary => To_Unbounded_String
              ((if Indicator = STR_01 then "Grüße" else "pass")),
            Evidence => To_Unbounded_String ("test"),
            Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>);
      begin
         case Indicator is
            when STR_02 =>
               Result.Measurement := (Kind => Integer_Value, Integer_Data => 17);
               Result.Compliance := Violation;
               Result.Summary := To_Unbounded_String ("failed <gate> & check");
               Result.Evidence := To_Unbounded_String ("expected ""safe"" output");
            when STR_03 =>
               Result.Measurement := (Kind => Decimal_Value, Basis_Points => 9_250);
            when STR_04 =>
               Result.Measurement :=
                 (Kind => Text_Value, Text_Data => To_Unbounded_String ("text"));
            when STR_05 =>
               Result.Measurement :=
                 (Kind => Enum_Value, Text_Data => To_Unbounded_String ("enum"));
            when PRF_01 =>
               Result.Execution := Blocked;
               Result.Compliance := Unknown;
               Result.Measurement :=
                 (Kind => Unavailable_Value, Reason => To_Unbounded_String ("not measured"));
            when others => null;
         end case;
         if Indicator = STR_01 then
            Result.Findings.Append
              (Finding'(Indicator => Indicator, Rule => To_Unbounded_String ("fixture"), Level => Low,
                Message => To_Unbounded_String ("finding"),
                Relative_Path => To_Unbounded_String ("src/example file.adb"), Line => 1,
                Fingerprint => To_Unbounded_String ("fixture-fingerprint")));
         end if;
         Value.Results.Append (Result);
      end;
   end loop;
   Text := To_Unbounded_String (Ada_Quality.JSON_Assessments.Render (Value));
   Assert
     (Ada_Quality.JSON.Render (Value) = To_String (Text),
      "legacy JSON facade delegates without changing the domain contract");
   Assert (Ada.Strings.Fixed.Index (To_String (Text), """schema_version"":1") > 0,
     "JSON has a schema version");
   Assert (Value.Results.Length = 33, "JSON fixture represents every indicator");
   Assert (Ada.Strings.Fixed.Index (To_String (Text), """executions""") > 0,
     "JSON includes individual tool executions");
   Assert (Ada.Strings.Fixed.Index (To_String (Text), """measurement""") > 0,
     "JSON includes typed measurements");
   Assert (Ada.Strings.Fixed.Index (To_String (Text), "Grüße") > 0,
     "JSON preserves valid UTF-8 without forced ASCII escaping");
   Assert (Ada.Strings.Fixed.Index (To_String (Text), Character'Val (27) & "[") = 0,
     "JSON output never contains ANSI styling");
   Jsonlib.Parsers.Parse (To_String (Text), Doc, Error);
   Assert (not Jsonlib.Errors.Failed (Error), "rendered report is strict RFC 8259 JSON");
   Assert_JSON_Contract
     (To_String (Text), "assessment.schema.json",
      "assessment report conforms to its schema");
   Assert
     (Jsonlib.Documents.Length
        (Doc, Jsonlib.Documents.Member (Doc, Jsonlib.Documents.Root (Doc), "results")) = 33,
      "parsed JSON contains every result");
   declare
      Outcomes : Ada_Quality.Command_Models.Batch_Outcome_Vectors.Vector;
      Batch    : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Outcomes.Append
        (Ada_Quality.Command_Models.Batch_Outcome'
           (Project_Id => 1, Assessment_Id => 1,
            Status => Ada_Quality.Command_Models.Batch_Completed,
            Diagnostic => Null_Unbounded_String, Value => Value));
      Outcomes.Append
        (Ada_Quality.Command_Models.Batch_Outcome'
           (Project_Id => 2, Assessment_Id => 2,
            Status => Ada_Quality.Command_Models.Batch_Interrupted,
            Diagnostic => To_Unbounded_String ("fixture interruption"), Value => <>));
      Outcomes.Append
        (Ada_Quality.Command_Models.Batch_Outcome'
           (Project_Id => 3, Assessment_Id => 3,
            Status => Ada_Quality.Command_Models.Batch_Reused,
            Diagnostic => Null_Unbounded_String, Value => <>));
      Outcomes.Append
        (Ada_Quality.Command_Models.Batch_Outcome'
           (Project_Id => 4, Assessment_Id => 4,
            Status => Ada_Quality.Command_Models.Batch_Completed,
            Diagnostic => Null_Unbounded_String, Value => Value));
      Batch := To_Unbounded_String
        (Ada_Quality.JSON_Assessments.Render_Batch (Outcomes));
      Jsonlib.Parsers.Parse (To_String (Batch), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error),
        "a multi-project assessment is one strict JSON document");
      Assert_JSON_Contract
        (To_String (Batch), "assessment-batch.schema.json",
         "assessment batch conforms to its schema");
      Assert
        (Jsonlib.Documents.Length
           (Doc, Jsonlib.Documents.Member (Doc, Jsonlib.Documents.Root (Doc), "outcomes")) = 4 and then
         Ada.Strings.Fixed.Index (To_String (Batch), """status"":""reused""") > 0,
         "batch JSON retains completed, reused, and interrupted project outcomes");
      declare
         Reuse : constant String :=
           Ada_Quality.JSON_Assessments.Render_Reuse (3, 3);
      begin
         Jsonlib.Parsers.Parse (Reuse, Doc, Error);
         Assert_JSON_Contract
           (Reuse, "assessment-reuse.schema.json",
            "assessment reuse conforms to its schema");
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index (Reuse, """kind"":""assessment-reuse""") > 0,
            "single-project unchanged reuse has strict versioned JSON output");
      end;
      declare
         Plan : Ada_Quality.Command_Models.Check_Plan_Vectors.Vector;
      begin
         Plan.Append
           (Ada_Quality.Command_Models.Check_Plan_Item'
              (Project_Id => 3, Path => To_Unbounded_String ("/tmp/project"),
               Source_Fingerprint => To_Unbounded_String ("source"),
               Policy_Fingerprint => To_Unbounded_String ("policy"),
               Toolchain_Fingerprint => To_Unbounded_String ("toolchain"),
               Reusable_Assessment => 3, Will_Reuse => True));
         declare Text : constant String :=
           Ada_Quality.JSON_Assessments.Render_Check_Plan (Plan); begin
            Jsonlib.Parsers.Parse (Text, Doc, Error);
            Assert_JSON_Contract
              (Text, "check-plan.schema.json",
               "check plan conforms to its schema");
            Assert
              (not Jsonlib.Errors.Failed (Error) and then
               Ada.Strings.Fixed.Index (Text, """kind"":""check-plan""") > 0,
               "no-write check plans have strict versioned JSON output");
         end;
      end;
   end;
   declare
      SARIF : constant String := Ada_Quality.CI_Formats.Render_SARIF (Value);
      JUnit : constant String := Ada_Quality.CI_Formats.Render_JUnit (Value);
      Catalog : constant String := Ada_Quality.JSON_Reports.Render_Indicators;
      Points : Ada_Quality.History.Trend_Vectors.Vector;
      Trend  : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Jsonlib.Parsers.Parse (SARIF, Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "SARIF output is strict JSON");
      Assert
        (Ada.Strings.Fixed.Index (SARIF, """version"":""2.1.0""") > 0 and then
         Ada.Strings.Fixed.Index (SARIF, """ruleId"":""STR-01/fixture""") > 0 and then
         Ada.Strings.Fixed.Index (SARIF, """adaQuality/v1""") > 0 and then
         Ada.Strings.Fixed.Index (SARIF, "src/example%20file.adb") > 0,
         "SARIF retains its contract, finding identity, and URI-encoded source location");
      declare
         Metrics : Ada_Quality.Checks.Source_Analysis;
         Scan_JSON : Ada.Strings.Unbounded.Unbounded_String;
         Scan_SARIF : Ada.Strings.Unbounded.Unbounded_String;
         Findings_JSON : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Metrics.File_Count := 1;
         Metrics.Long_Lines := 1;
         Metrics.Findings.Append
           (Value.Results.First_Element.Findings.First_Element);
         Scan_JSON := To_Unbounded_String
           (Ada_Quality.JSON_Reports.Render_Scan (1, Metrics));
         Scan_SARIF := To_Unbounded_String
           (Ada_Quality.CI_Formats.Render_SARIF (Metrics.Findings));
         Findings_JSON := To_Unbounded_String
           (Ada_Quality.JSON_Reports.Render_Findings (Metrics.Findings));
         Jsonlib.Parsers.Parse (To_String (Scan_JSON), Doc, Error);
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index (To_String (Scan_JSON),
              """kind"":""changed-source-scan""") > 0,
            "changed-source scans have versioned strict JSON output");
         Assert_JSON_Contract
           (To_String (Scan_JSON), "changed-source-scan.schema.json",
            "changed-source scan conforms to its schema");
         Jsonlib.Parsers.Parse (To_String (Scan_SARIF), Doc, Error);
         Assert (not Jsonlib.Errors.Failed (Error),
           "arbitrary changed-source findings have strict SARIF output");
         Jsonlib.Parsers.Parse (To_String (Findings_JSON), Doc, Error);
         Assert_JSON_Contract
           (To_String (Findings_JSON), "findings.schema.json",
            "findings conform to their schema");
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index (To_String (Findings_JSON), """kind"":""findings""") > 0,
            "filtered findings have versioned strict JSON output");
         Assert
           (Ada.Strings.Fixed.Index
              (Ada_Quality.HTML.Render_Assessment (Value), "<!doctype html>") = 1,
            "assessments have a self-contained HTML representation");
      end;
      Assert
        (Ada.Strings.Fixed.Index (JUnit, "tests=""33""") > 0 and then
         Ada.Strings.Fixed.Index (JUnit, "failures=""1""") > 0 and then
         Ada.Strings.Fixed.Index (JUnit, "errors=""1""") > 0 and then
         Ada.Strings.Fixed.Index (JUnit, "failed &lt;gate&gt; &amp; check") > 0,
         "JUnit maps every indicator and escapes failure diagnostics");
      Jsonlib.Parsers.Parse (Catalog, Doc, Error);
      Assert_JSON_Contract
        (Catalog, "indicator-catalog.schema.json",
         "indicator catalog conforms to its schema");
      Assert
        (not Jsonlib.Errors.Failed (Error) and then
         Ada.Strings.Fixed.Index (Catalog, """kind"":""indicator-catalog""") > 0 and then
         Jsonlib.Documents.Length
           (Doc, Jsonlib.Documents.Member (Doc, Jsonlib.Documents.Root (Doc), "indicators")) = 33,
         "indicator catalog JSON exposes the complete versioned registry");
      Points.Append (Ada_Quality.History.Trend_Point'(Run_Id => 7, Value => 9_000));
      Points.Append (Ada_Quality.History.Trend_Point'(Run_Id => 9, Value => 9_250));
      Trend := To_Unbounded_String
        (Ada_Quality.JSON_Reports.Render_Trend
           (1, TST_03, "basis_points", Points));
      Jsonlib.Parsers.Parse (To_String (Trend), Doc, Error);
      Assert_JSON_Contract
        (To_String (Trend), "metric-trend.schema.json",
         "metric trend conforms to its schema");
      Assert
        (not Jsonlib.Errors.Failed (Error) and then
         Ada.Strings.Fixed.Index (To_String (Trend), """kind"":""metric-trend""") > 0 and then
         Ada.Strings.Fixed.Index (To_String (Trend), """run_id"":9") > 0,
         "metric trends have a versioned deterministic JSON representation");
      declare
         Series : Ada_Quality.Command_Models.Metric_Series_Vectors.Vector;
         Runs   : Ada_Quality.Reporting.Run_Vectors.Vector;
         Comparison : Ada_Quality.Reporting.Project_Comparison :=
           (Project_Id => 1,
            Selection =>
              (Status => Ada_Quality.History.Comparison_Available,
               Current_Id => 9, Baseline_Id => 7, Policy_Changed => False),
            Changes => <>);
         Multi, History_JSON, Comparison_JSON : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Series.Append
           (Ada_Quality.Command_Models.Metric_Series'
              (Indicator => TST_03, Unit_Name => To_Unbounded_String ("basis_points"), Points => Points));
         Series.Append
           (Ada_Quality.Command_Models.Metric_Series'
              (Indicator => SRC_03, Unit_Name => To_Unbounded_String ("decision_points"), Points => <>));
         Multi := To_Unbounded_String
           (Ada_Quality.JSON_Reports.Render_Trends (1, Series));
         Jsonlib.Parsers.Parse (To_String (Multi), Doc, Error);
         Assert_JSON_Contract
           (To_String (Multi), "metric-trends.schema.json",
            "metric trends conform to their schema");
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index (To_String (Multi), """kind"":""metric-trends""") > 0 and then
            Ada.Strings.Fixed.Index (To_String (Multi), """indicator"":""SRC-03""") > 0,
            "multi-metric trends retain ordered series including empty compatible ranges");

         Runs.Append
           (Ada_Quality.Reporting.Run_Record'
              (Id => 9, Project_Id => 1, State => Assessment_Completed,
               Source_Id => To_Unbounded_String ("source"), Policy_Id => To_Unbounded_String ("policy"),
               Toolchain_Id => To_Unbounded_String ("toolchain"),
               Started_At => (Present => False), Finished_At => (Present => False),
               Format => Ada_Quality.Reporting.Lossless_Evidence));
         History_JSON := To_Unbounded_String
           (Ada_Quality.JSON_Reports.Render_History
              (Runs,
               (Present => True, Total => 2, Offset => 0, Limit => 1,
                Next_Cursor => To_Unbounded_String ("v1:1"), Snapshot => 0)));
         Jsonlib.Parsers.Parse (To_String (History_JSON), Doc, Error);
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index (To_String (History_JSON), """kind"":""assessment-history""") > 0 and then
            Ada.Strings.Fixed.Index (To_String (History_JSON), """assessment_id"":9") > 0 and then
            Ada.Strings.Fixed.Index (To_String (History_JSON), """next_cursor"":""v1:1""") > 0,
            "filtered history has deterministic cursor and total-count metadata");
         Assert_JSON_Contract
           (To_String (History_JSON), "assessment-history.schema.json",
            "assessment history conforms to its schema");

         Comparison.Changes.Append
           (Ada_Quality.History.Regression'
              (Indicator => TST_03, Kind => Ada_Quality.History.Worsened_Metric,
               Before => To_Unbounded_String ("9250"), After => To_Unbounded_String ("9000")));
         Comparison_JSON := To_Unbounded_String
           (Ada_Quality.JSON_Assessments.Render_Comparison (Comparison));
         Jsonlib.Parsers.Parse (To_String (Comparison_JSON), Doc, Error);
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index
              (To_String (Comparison_JSON), """kind"":""assessment-comparison""") > 0 and then
            Ada.Strings.Fixed.Index (To_String (Comparison_JSON), """baseline_id"":7") > 0,
            "explicit comparisons have a versioned deterministic JSON representation");
         Assert_JSON_Contract
           (To_String (Comparison_JSON), "assessment-comparison.schema.json",
            "assessment comparison conforms to its schema");
      end;
   end;
   declare
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
      Discoveries : Ada_Quality.Command_Models.Discovery_Vectors.Vector;
      Aliases : Ada_Quality.Reporting.Alias_Vectors.Vector;
      Stats : Ada_Quality.Reporting.Snapshot_Statistics;
      DB_Path : constant String := Fixture_Root & "/json-contract.db";
      Store : Ada_Quality.Storage.Store;
      Session : Ada_Quality.Reporting.Session;
   begin
      Projects.Append
        (Ada_Quality.Reporting.Project_Record'
           (Id => 1, Path => To_Unbounded_String ("/fixture"),
            Tags => To_Unbounded_String ("core,release"), Enabled => True, Removed => False));
      Discoveries.Append
        (Ada_Quality.Command_Models.Discovery_Item'
           (Path => To_Unbounded_String ("/fixture"), Project_Id => 1,
            Status => Ada_Quality.Command_Models.Discovered));
      Aliases.Append
        (Ada_Quality.Reporting.Assessment_Alias'
           (Name => To_Unbounded_String ("release"), Run_Id => 1, Event_Id => 1));
      Assert_JSON_Contract
        (Ada_Quality.JSON_Reports.Render_Projects (Projects), "project-list.schema.json",
         "project list conforms to its schema");
      Assert_JSON_Contract
        (Ada_Quality.JSON_Reports.Render_Discovery
           (Discoveries), "project-discovery.schema.json",
         "project discovery conforms to its schema");
      Assert_JSON_Contract
        (Ada_Quality.JSON_Assessments.Render_Aliases
           (Aliases), "assessment-aliases.schema.json",
         "assessment aliases conform to their schema");
      Assert_JSON_Contract
        (Ada_Quality.JSON_Reports.Render_Statistics
           (Stats), "database-statistics.schema.json",
         "database statistics conform to their schema");

      Project_Tools.Files.Delete_File_If_Present (DB_Path);
      Project_Tools.Files.Delete_File_If_Present (DB_Path & ".wal");
      Project_Tools.Files.Delete_File_If_Present (DB_Path & ".lock");
      Ada_Quality.Storage.Open (Store, DB_Path);
      Ada_Quality.Storage.Integrity.Check (Store);
      Ada_Quality.Storage.Close (Store);
      Ada_Quality.Reporting.Open (Session, DB_Path);
      Assert_JSON_Contract
        (Ada_Quality.JSON_Reports.Render_Status
           (Session), "portfolio-status.schema.json",
         "portfolio status conforms to its schema");
      Assert_JSON_Contract
        (Ada_Quality.JSON_Reports.Render_Archive (Session), "archive.schema.json",
         "archive conforms to its schema");
   end;
end;
end Run_JSON_Test;
