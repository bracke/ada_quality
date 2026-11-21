separate (Ada_Quality_Test_Suite)
procedure Run_JSON_Administrative_Test is
   Doc   : Jsonlib.Documents.Document;
   Error : Jsonlib.Errors.Error_Info;
begin
   declare
      Diagnostics : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Waivers : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
      Retention : Ada_Quality.Storage.History_Vectors.Vector;
      Administrative : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Diagnostics.Append
        (Ada_Quality.Command_Models.Diagnostic_Item'
           (Name => To_Unbounded_String ("fixture"), Passed => False,
            Detail => To_Unbounded_String ("conflict")));
      Administrative := To_Unbounded_String
        (Ada_Quality.JSON_Administration.Render_Doctor (Diagnostics));
      Assert (Ada.Strings.Fixed.Index (To_String (Administrative), "doctor-report") > 0,
        "doctor diagnostics have versioned JSON");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Administrative), """failure_count"":1") > 0 and then
         Ada.Strings.Fixed.Index (To_String (Administrative), """threshold_passed"":false") > 0,
         "doctor JSON exposes the threshold decision used for its exit status");
      Assert_JSON_Contract
        (To_String (Administrative), "doctor-report.schema.json",
         "doctor diagnostics conform to their schema");
      for Status in Ada_Quality.Checks.Waiver_Status loop
         Waivers.Append
           (Ada_Quality.Checks.Waiver_Audit_Item'
              (Rule => To_Unbounded_String ("src-03"), Target => To_Unbounded_String ("fixture"),
               Owner => To_Unbounded_String ("team"), Expires => To_Unbounded_String ("2027-11-21"),
               Justification => To_Unbounded_String ("fixture"),
               Relative_Path => To_Unbounded_String ("src/fixture.adb"), Line => 1,
               Status => Status, Expiring => Status = Ada_Quality.Checks.Waiver_Active));
      end loop;
      Administrative := To_Unbounded_String
        (Ada_Quality.JSON_Administration.Render_Waivers (Waivers));
      Assert (Ada.Strings.Fixed.Index (To_String (Administrative), "waiver-audit") > 0,
        "complete waiver inventory has versioned JSON");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Administrative), """invalid_count"":2") > 0 and then
         Ada.Strings.Fixed.Index (To_String (Administrative), """threshold_passed"":false") > 0,
         "waiver JSON exposes observed counts and the threshold decision");
      Assert_JSON_Contract
        (To_String (Administrative), "waiver-audit.schema.json",
         "waiver inventory conforms to its schema");
      Retention.Append
        (Ada_Quality.Storage.History_Item'
           (Id => 7, Project_Id => 2, Status => To_Unbounded_String ("completed"),
            Summary => Null_Unbounded_String, Source_Fingerprint => Null_Unbounded_String,
            Policy_Fingerprint => Null_Unbounded_String, Toolchain_Fingerprint => Null_Unbounded_String));
      Administrative := To_Unbounded_String
        (Ada_Quality.JSON_Administration.Render_Retention
           (Retention, "2026-01-01T00:00:00Z", 3));
      Assert (Ada.Strings.Fixed.Index (To_String (Administrative), "retention-preview") > 0,
        "retention previews have versioned JSON");
      Assert_JSON_Contract
        (To_String (Administrative), "retention-preview.schema.json",
         "retention preview conforms to its schema");
      Administrative := To_Unbounded_String
        (Ada_Quality.JSON_Administration.Render_Merge
           ("source.db", True, 1, 2, 3, 4, Diagnostics));
      Assert
        (Ada.Strings.Fixed.Index (To_String (Administrative), "database-merge") > 0 and then
         Ada.Strings.Fixed.Index (To_String (Administrative), "conflict") > 0,
         "merge plans and conflicts have versioned JSON");
      Assert_JSON_Contract
        (To_String (Administrative), "database-merge.schema.json",
         "merge plan conforms to its schema");
      declare
         Doctor_Reports : Ada_Quality.Command_Models.Diagnostic_Report_Vectors.Vector;
         Passing_Diagnostics : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
         Waiver_Reports : Ada_Quality.Command_Models.Waiver_Report_Vectors.Vector;
         Strings : Ada_Quality.Command_Models.String_Vectors.Vector;
         Indicators : Ada_Quality.Command_Models.String_Vectors.Vector;
         Impacts : Ada_Quality.Command_Models.Policy_Impact_Vectors.Vector;
         Comparisons : Ada_Quality.Command_Models.Comparison_Vectors.Vector;
         Trusted : Ada_Quality.Artifact_Signing.Trusted_Key_Vectors.Vector;
         Before, After : Ada_Quality.Policy.Quality_Policy;
         Signature : constant Ada_Quality.Artifact_Signing.Signature_Info :=
           (Path => To_Unbounded_String ("fixture.sig"),
            Kind => To_Unbounded_String ("logical-export"),
            Algorithm => To_Unbounded_String ("ed25519-sha256"),
            Digest => To_Unbounded_String ([1 .. 64 => '0']),
            Key => To_Unbounded_String ("ed25519-0000000000000000"));
      begin
         Passing_Diagnostics.Append
           (Ada_Quality.Command_Models.Diagnostic_Item'
              (Name => To_Unbounded_String ("project"), Passed => True,
               Detail => To_Unbounded_String ("/fixture")));
         Doctor_Reports.Append
           (Ada_Quality.Command_Models.Diagnostic_Report'
              (Project_Id => 1, Path => To_Unbounded_String ("/fixture"), Checks => Passing_Diagnostics));
         Waiver_Reports.Append
           (Ada_Quality.Command_Models.Waiver_Report'
              (Project_Id => 1, Path => To_Unbounded_String ("/fixture"), Waivers => Waivers));
         Strings.Append (To_Unbounded_String ("maximum_complexity"));
         Indicators.Append (To_Unbounded_String ("SRC-03"));
         Impacts.Append
           (Ada_Quality.Command_Models.Policy_Impact_Item'
              (Project_Id => 1, Path => To_Unbounded_String ("/fixture"),
             Before_Fingerprint => To_Unbounded_String ("before"),
             After_Fingerprint => To_Unbounded_String ("after"),
             Keys => Strings, Indicators => Indicators));
         Trusted.Append
           (Ada_Quality.Artifact_Signing.Trusted_Key'
              (Id => To_Unbounded_String ("ed25519-0000000000000000"),
             Path => To_Unbounded_String ("fixture.pub")));
         After.Coverage_Minimum_Basis_Points := Before.Coverage_Minimum_Basis_Points + 1;
         After.Maximum_Source_Lines := Before.Maximum_Source_Lines + 1;
         After.Maximum_Complexity := Before.Maximum_Complexity + 1;
         After.Process_Timeout_Seconds := Before.Process_Timeout_Seconds + 1;
         After.Maximum_Output_Bytes := Before.Maximum_Output_Bytes + 1;
         After.Require_Clean_Worktree := not Before.Require_Clean_Worktree;
         Comparisons.Append
           (Ada_Quality.Reporting.Project_Comparison'
              (Project_Id => 1,
               Selection =>
                 (Status => Ada_Quality.History.Comparison_Available,
                  Current_Id => 2, Baseline_Id => 1, Policy_Changed => False),
               Changes => <>));
         Comparisons.Reference (Comparisons.First_Index).Changes.Append
           (Ada_Quality.History.Regression'
              (Indicator => TST_03, Kind => Ada_Quality.History.Worsened_Metric,
               Before => To_Unbounded_String ("9100"),
               After => To_Unbounded_String ("9000")));
         for Rendered of
           Ada_Quality.Command_Models.String_Vectors.Vector'
             [To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Doctor_Batch
                   (Doctor_Reports)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Waiver_Batch
                   (Waiver_Reports)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Error
                   ("usage_error", "bad", "fixture", 2)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Command_Result
                   ("fixture", "done", True)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_String_List
                   ("fixture-list", "values", Strings)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Policy
                   (Before, "fixture")),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Policy_Diff
                   ("before", "after", Before, After)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Policy_Impact
                   ("before", "after", Impacts)),
              To_Unbounded_String
                (Ada_Quality.JSON_Reports.Render_Comparisons (Comparisons)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Signature
                   (Signature, False)),
              To_Unbounded_String
                (Ada_Quality.JSON_Administration.Render_Trusted_Keys (Trusted))]
         loop
            Jsonlib.Parsers.Parse (To_String (Rendered), Doc, Error);
            Assert (not Jsonlib.Errors.Failed (Error),
              "administrative JSON renderers produce strict documents");
         end loop;
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Doctor_Batch (Doctor_Reports),
            "doctor-report.schema.json", "doctor batch conforms to its schema");
         declare
            Threshold_Batch : constant String :=
              Ada_Quality.JSON_Administration.Render_Doctor_Batch
              (Doctor_Reports, Global_Checks => Diagnostics, Maximum_Failures => 1);
         begin
            Assert
              (Ada.Strings.Fixed.Index (Threshold_Batch, """failure_count"":1") > 0 and then
               Ada.Strings.Fixed.Index (Threshold_Batch, """passed"":true") > 0,
               "doctor batch counts each emitted global failure once and applies the root threshold");
            Assert_JSON_Contract
              (Threshold_Batch, "doctor-report.schema.json",
               "doctor batch with global checks conforms to its schema");
         end;
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Waiver_Batch (Waiver_Reports),
            "waiver-audit.schema.json", "waiver batch conforms to its schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Error
              ("usage_error", "bad", "fixture", 2),
            "error.schema.json", "error document conforms to its schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Command_Result
              ("fixture", "done", True),
            "command-result.schema.json", "command result conforms to its schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Policy (Before, "fixture"),
            "policy.schema.json", "policy document conforms to its schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Policy_Diff
              ("before", "after", Before, After),
            "policy-diff.schema.json", "policy diff conforms to its schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Policy_Impact
              ("before", "after", Impacts),
            "policy-impact.schema.json", "policy impact conforms to its schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Reports.Render_Comparisons (Comparisons),
            "regressions.schema.json", "regressions conform to their schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Signature (Signature, False),
            "artifact-signature.schema.json", "signature document conforms to its schema");
         Assert_JSON_Contract
           (Ada_Quality.JSON_Administration.Render_Trusted_Keys (Trusted),
            "trusted-keys.schema.json", "trusted keys conform to their schema");
         declare
            Invalid_Signature : Ada_Quality.Artifact_Signing.Signature_Info := Signature;
            Diagnostic : Ada.Strings.Unbounded.Unbounded_String;
            Valid : Boolean;
            Root : constant String := Project_Tools.Files.Find_Root_Upward
              (Ada.Directories.Current_Directory, "ada_quality.gpr");
         begin
            Invalid_Signature.Digest := To_Unbounded_String ("not-a-digest");
            Valid := Ada_Quality_JSON_Contract_Testing.Conforms
              (Ada_Quality.JSON_Administration.Render_Signature
                 (Invalid_Signature, False),
               Project_Tools.Files.Read_Raw_File
                 (Root & "/docs/artifact-signature.schema.json"), Diagnostic);
            Assert
              (not Valid,
               "contract validation rejects malformed rendered signature metadata: "
               & To_String (Diagnostic));
            Valid := Ada_Quality_JSON_Contract_Testing.Conforms
              ("{""value"":1,""extra"":2}",
               "{""type"":""object"",""properties"":{""value"":{""type"":""integer""}}," &
               """additionalProperties"":{""type"":""string""}}",
               Diagnostic);
            Assert
              (not Valid,
               "contract validation applies schema-valued additionalProperties: " &
               To_String (Diagnostic));
            Valid := Ada_Quality_JSON_Contract_Testing.Conforms
              ("{""value"":1}",
               "{""type"":""object"",""unsupportedKeyword"":true}", Diagnostic);
            Assert
              (not Valid and then Ada.Strings.Fixed.Index
                 (To_String (Diagnostic), "unsupported schema keyword") > 0,
               "contract validation fails closed on unsupported schema keywords");
            Valid := Ada_Quality_JSON_Contract_Testing.Conforms
              ("1",
               "{""$defs"":{""base"":{""type"":""integer""}}," &
               """$ref"":""#/$defs/base"",""const"":2}", Diagnostic);
            Assert
              (not Valid,
               "contract validation applies sibling constraints beside $ref: " &
               To_String (Diagnostic));
            Valid := Ada_Quality_JSON_Contract_Testing.Conforms
              ("2", "{""$ref"":""assessment.schema.json#/properties/schema_version""}",
               Diagnostic, Root & "/docs");
            Assert
              (not Valid,
               "contract validation resolves external reference fragments: " &
               To_String (Diagnostic));
            Valid := Ada_Quality_JSON_Contract_Testing.Conforms
              ("1", "{""$ref"":""#""}", Diagnostic);
            Assert
              (not Valid and then Ada.Strings.Fixed.Index
                 (To_String (Diagnostic), "schema reference depth exceeded") > 0,
               "contract validation rejects cyclic schema references safely");
         end;
      end;
   end;
end Run_JSON_Administrative_Test;
