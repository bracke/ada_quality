separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_json_test justification=one-component-fixture-matrix
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
   Text := To_Unbounded_String (Ada_Quality.JSON.Render (Value));
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
   Assert
     (Jsonlib.Documents.Length
        (Doc, Jsonlib.Documents.Member (Doc, Jsonlib.Documents.Root (Doc), "results")) = 33,
      "parsed JSON contains every result");
   declare
      Outcomes : Ada_Quality.JSON.Batch_Outcome_Vectors.Vector;
      Batch    : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Outcomes.Append
        (Ada_Quality.JSON.Batch_Outcome'
           (Project_Id => 1, Assessment_Id => 1,
            Status => Ada_Quality.JSON.Batch_Completed,
            Diagnostic => Null_Unbounded_String, Value => Value));
      Outcomes.Append
        (Ada_Quality.JSON.Batch_Outcome'
           (Project_Id => 2, Assessment_Id => 2,
            Status => Ada_Quality.JSON.Batch_Interrupted,
            Diagnostic => To_Unbounded_String ("fixture interruption"), Value => <>));
      Outcomes.Append
        (Ada_Quality.JSON.Batch_Outcome'
           (Project_Id => 3, Assessment_Id => 3,
            Status => Ada_Quality.JSON.Batch_Completed,
            Diagnostic => Null_Unbounded_String, Value => Value));
      Batch := To_Unbounded_String (Ada_Quality.JSON.Render_Batch (Outcomes));
      Jsonlib.Parsers.Parse (To_String (Batch), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error),
        "a multi-project assessment is one strict JSON document");
      Assert
        (Jsonlib.Documents.Length
           (Doc, Jsonlib.Documents.Member (Doc, Jsonlib.Documents.Root (Doc), "outcomes")) = 3,
         "batch JSON retains completed and interrupted project outcomes");
   end;
   declare
      SARIF : constant String := Ada_Quality.CI_Formats.Render_SARIF (Value);
      JUnit : constant String := Ada_Quality.CI_Formats.Render_JUnit (Value);
      Catalog : constant String := Ada_Quality.JSON.Render_Indicators;
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
      begin
         Metrics.File_Count := 1;
         Metrics.Long_Lines := 1;
         Metrics.Findings.Append
           (Value.Results.First_Element.Findings.First_Element);
         Scan_JSON := To_Unbounded_String (Ada_Quality.JSON.Render_Scan (1, Metrics));
         Scan_SARIF := To_Unbounded_String
           (Ada_Quality.CI_Formats.Render_SARIF (Metrics.Findings));
         Jsonlib.Parsers.Parse (To_String (Scan_JSON), Doc, Error);
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index (To_String (Scan_JSON),
              """kind"":""changed-source-scan""") > 0,
            "changed-source scans have versioned strict JSON output");
         Jsonlib.Parsers.Parse (To_String (Scan_SARIF), Doc, Error);
         Assert (not Jsonlib.Errors.Failed (Error),
           "arbitrary changed-source findings have strict SARIF output");
      end;
      Assert
        (Ada.Strings.Fixed.Index (JUnit, "tests=""33""") > 0 and then
         Ada.Strings.Fixed.Index (JUnit, "failures=""1""") > 0 and then
         Ada.Strings.Fixed.Index (JUnit, "errors=""1""") > 0 and then
         Ada.Strings.Fixed.Index (JUnit, "failed &lt;gate&gt; &amp; check") > 0,
         "JUnit maps every indicator and escapes failure diagnostics");
      Jsonlib.Parsers.Parse (Catalog, Doc, Error);
      Assert
        (not Jsonlib.Errors.Failed (Error) and then
         Ada.Strings.Fixed.Index (Catalog, """kind"":""indicator-catalog""") > 0 and then
         Jsonlib.Documents.Length
           (Doc, Jsonlib.Documents.Member (Doc, Jsonlib.Documents.Root (Doc), "indicators")) = 33,
         "indicator catalog JSON exposes the complete versioned registry");
      Points.Append (Ada_Quality.History.Trend_Point'(Run_Id => 7, Value => 9_000));
      Points.Append (Ada_Quality.History.Trend_Point'(Run_Id => 9, Value => 9_250));
      Trend := To_Unbounded_String
        (Ada_Quality.JSON.Render_Trend (1, TST_03, "basis_points", Points));
      Jsonlib.Parsers.Parse (To_String (Trend), Doc, Error);
      Assert
        (not Jsonlib.Errors.Failed (Error) and then
         Ada.Strings.Fixed.Index (To_String (Trend), """kind"":""metric-trend""") > 0 and then
         Ada.Strings.Fixed.Index (To_String (Trend), """run_id"":9") > 0,
         "metric trends have a versioned deterministic JSON representation");
      declare
         Series : Ada_Quality.JSON.Metric_Series_Vectors.Vector;
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
           (Ada_Quality.JSON.Metric_Series'
              (Indicator => TST_03, Unit_Name => To_Unbounded_String ("basis_points"), Points => Points));
         Series.Append
           (Ada_Quality.JSON.Metric_Series'
              (Indicator => SRC_03, Unit_Name => To_Unbounded_String ("decision_points"), Points => <>));
         Multi := To_Unbounded_String (Ada_Quality.JSON.Render_Trends (1, Series));
         Jsonlib.Parsers.Parse (To_String (Multi), Doc, Error);
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
         History_JSON := To_Unbounded_String (Ada_Quality.JSON.Render_History (Runs));
         Jsonlib.Parsers.Parse (To_String (History_JSON), Doc, Error);
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index (To_String (History_JSON), """kind"":""assessment-history""") > 0 and then
            Ada.Strings.Fixed.Index (To_String (History_JSON), """assessment_id"":9") > 0,
            "filtered history has a versioned deterministic JSON representation");

         Comparison.Changes.Append
           (Ada_Quality.History.Regression'
              (Indicator => TST_03, Kind => Ada_Quality.History.Worsened_Metric,
               Before => To_Unbounded_String ("9250"), After => To_Unbounded_String ("9000")));
         Comparison_JSON := To_Unbounded_String (Ada_Quality.JSON.Render_Comparison (Comparison));
         Jsonlib.Parsers.Parse (To_String (Comparison_JSON), Doc, Error);
         Assert
           (not Jsonlib.Errors.Failed (Error) and then
            Ada.Strings.Fixed.Index
              (To_String (Comparison_JSON), """kind"":""assessment-comparison""") > 0 and then
            Ada.Strings.Fixed.Index (To_String (Comparison_JSON), """baseline_id"":7") > 0,
            "explicit comparisons have a versioned deterministic JSON representation");
      end;
   end;
   declare
      Root : constant String :=
        Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
   begin
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/assessment.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "assessment JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/archive.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "archive JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/assessment-batch.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "batch assessment JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/metric-trend.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "metric trend JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/metric-trends.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "multi-metric trend JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/assessment-history.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "assessment history JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/assessment-comparison.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "assessment comparison JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/portfolio-status.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "portfolio status JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/indicator-catalog.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "indicator catalog JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/changed-source-scan.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "changed-source scan JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/project-list.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "project list JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/project-discovery.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "project discovery JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/assessment-aliases.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "assessment alias JSON schema is valid JSON");
      Jsonlib.Parsers.Parse
        (Project_Tools.Files.Read_Raw_File (Root & "/docs/database-statistics.schema.json"), Doc, Error);
      Assert (not Jsonlib.Errors.Failed (Error), "database statistics JSON schema is valid JSON");
   end;
end;
end Run_JSON_Test;
