with Ada.Containers;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding;
with Ada.Text_IO;
with AUnit;
with AUnit.Assertions;
with AUnit.Simple_Test_Cases;
with Jsonlib.Documents;
with Jsonlib.Errors;
with Jsonlib.Parsers;
with Project_Tools.Processes;
with Project_Tools.Files;
with Ada_Quality.Execution;
with Ada_Quality.Evaluation;
with Ada_Quality.Checks;
with Ada_Quality.Coverage;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.JSON;
with Ada_Quality.Policy;
with Ada_Quality.Presentation;
with Ada_Quality.Storage;
with Ada_Quality.Types;
with Ada_Quality.Tools;
with Ada_Quality.Workspaces;

--  AQ: complexity-reviewed -- one registry intentionally presents the complete cross-component test matrix.
--  AQ: size-reviewed -- keeping the test registry together makes coverage and fixture ownership auditable.
package body Ada_Quality_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Execution.Run_Status;
   use type Ada_Quality.History.Finding_Lifecycle;
   use type Ada_Quality.History.Regression_Kind;
   use type Ada_Quality.Tools.Tool_Id;

   type Test_Kind is
     (Registry_Test, Coverage_Test, Status_Test, Policy_Test, JSON_Test, Storage_Test, Execution_Test,
      Applicability_Test, Source_Analysis_Test, Integrity_Test, Symlink_Test, History_Test);
   type Quality_Test (Kind : Test_Kind) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   overriding function Name (Item : Quality_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Quality_Test);

   overriding function Name (Item : Quality_Test) return AUnit.Message_String is
   begin
      return AUnit.Format (Test_Kind'Image (Item.Kind));
   end Name;

   overriding procedure Run_Test (Item : in out Quality_Test) is
      Id : Indicator_Id;
   begin
      case Item.Kind is
         when Registry_Test =>
            Assert (Ada_Quality.Indicators.Count = 33, "registry contains exactly 33 indicators");
            declare
               Registry : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
               Tool_Registry : constant Ada_Quality.Tools.Tool_Descriptor_Array := Ada_Quality.Tools.Registry;
            begin
               for Expected in Indicator_Id loop
                  Assert (Registry (Expected).Id = Expected and then Registry (Expected).Version = 1,
                    "registry descriptors preserve strong IDs and versions");
               end loop;
               for Tool in Ada_Quality.Tools.Tool_Id loop
                  Assert (Tool_Registry (Tool).Id = Tool and then Tool_Registry (Tool).Program.all'Length > 0,
                    "tool descriptors preserve registered program identities");
               end loop;
            end;
            for Expected in Indicator_Id loop
               Assert (Ada_Quality.Indicators.Parse (Image (Expected), Id), "indicator image parses");
               Assert (Id = Expected, "indicator parse round trip");
            end loop;
            Assert (not Ada_Quality.Indicators.Parse ("not-an-indicator", Id),
              "invalid indicator names are rejected without raising");
            Assert (Ada_Quality.Indicators.Validate_Acyclic, "indicator prerequisite graph is acyclic");
            for Tool in Ada_Quality.Tools.Tool_Id loop
               Assert (Ada_Quality.Tools.Program (Tool)'Length > 0, "tool registry programs are explicit");
            end loop;
            Assert (Ada_Quality.Presentation.Result_Line ("+", "STR-01", "pass") = "+ STR-01 pass",
              "human result lines are rendered through the message catalog");
            Assert (Image (Execution_Status'(Not_Applicable)) = "not-applicable" and then
              Image (Compliance_Status'(Not_Applicable)) = "not-applicable" and then
              Image (Tool_Spawn_Error) = "tool-spawn-error",
              "status images normalize compound enumeration names");
            Assert (Image (Measurement_Value'(Kind => Unavailable_Value,
              Reason => To_Unbounded_String ("missing"))) = "missing" and then
              Image (Measurement_Value'(Kind => Integer_Value, Integer_Data => 17)) = " 17" and then
              Image (Measurement_Value'(Kind => Decimal_Value, Basis_Points => 9_250)) = " 9250" and then
              Image (Measurement_Value'(Kind => Text_Value,
                Text_Data => To_Unbounded_String ("text"))) = "text" and then
              Image (Measurement_Value'(Kind => Enum_Value,
                Text_Data => To_Unbounded_String ("enum"))) = "enum",
              "all measurement variants have stable persisted images");

         when Coverage_Test =>
            Assert (not Coverage_Passes (8_999, 10_000), "89.99 percent fails");
            Assert (Coverage_Passes (9_000, 10_000), "90 percent passes");
            Assert (Coverage_Passes (9_001, 10_000), "above 90 percent passes");
            Assert (not Coverage_Passes (0, 0), "zero eligible lines cannot pass");
            Assert
              (Coverage_Passes (Natural'Last, Natural'Last), "multiplication uses overflow-safe wide arithmetic");
            declare
               Root    : constant String := "/tmp/ada_quality_coverage_inventory_test";
               Objects : constant String := Root & "/objects";
            begin
               Project_Tools.Files.Delete_Tree (Root);
               Ada.Directories.Create_Path (Root & "/src");
               Ada.Directories.Create_Path (Objects);
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/alpha.ads", "package Alpha is end Alpha;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/alpha.adb", "package body Alpha is end Alpha;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/beta.ads", "package Beta is end Beta;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File (Objects & "/alpha.gcno", "fixture");
               declare
                  Units : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
                    Ada_Quality.Coverage.Production_Units (Root);
                  Missing : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
                    Ada_Quality.Coverage.Missing_Objects (Units, Objects);
               begin
                  Assert (Units.Length = 2 and then Missing.Length = 1 and then
                    To_String (Missing.First_Element.Stem) = "beta",
                    "coverage inventory independently detects an uninstrumented production unit");
                  Project_Tools.Files.Write_Text_File (Objects & "/beta.gcno", "fixture");
                  Assert (Ada_Quality.Coverage.Missing_Objects (Units, Objects).Is_Empty,
                    "coverage inventory is complete only when every production unit has instrumentation");
                  Assert
                    (Ada_Quality.Coverage.Has_Source_Record
                       ("File '" & Root & "/src/alpha.adb'" & ASCII.LF &
                        "Lines executed:100.00% of 0" & ASCII.CR & ASCII.LF,
                        Root & "/src/alpha.adb") and then
                     not Ada_Quality.Coverage.Has_Source_Record
                       ("File '" & Root & "/src/alpha.adb'" & ASCII.LF,
                        Root & "/src/alpha.adb") and then
                     Ada_Quality.Coverage.Has_Source_Record
                       ("File '" & Root & "/src/alpha.ads'" & ASCII.LF &
                        "No executable lines" & ASCII.LF,
                        Root & "/src/alpha.ads") and then
                     not Ada_Quality.Coverage.Has_Source_Record
                       ("File '" & Root & "/src/alpha.adb'" & ASCII.LF &
                        "Lines executed:malformed" & ASCII.LF,
                        Root & "/src/alpha.adb") and then
                     not Ada_Quality.Coverage.Has_Source_Record
                       ("File '" & Root & "/src/alpha.adb'" & ASCII.LF &
                        "Lines executed:100.00% of 0" & ASCII.LF,
                        Root & "/src/alpha.ads"),
                     "coverage completeness requires a parsed summary and distinguishes zero-line evidence");
               end;
               Ada.Directories.Create_Path (Root & "/src/nested");
               declare
                  Rejected : Boolean := False;
               begin
                  Project_Tools.Files.Write_Text_File
                    (Root & "/src/nested/alpha.adb", "package body Alpha is end Alpha;" & ASCII.LF);
                  begin
                     declare
                        Duplicate_Units : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
                          Ada_Quality.Coverage.Production_Units (Root);
                     begin
                        Rejected := Duplicate_Units.Is_Empty;
                     end;
                  exception
                     when Constraint_Error => Rejected := True;
                  end;
                  Assert (Rejected, "coverage inventory rejects duplicate production body stems");
                  Ada.Directories.Delete_File (Root & "/src/nested/alpha.adb");
                  Rejected := False;
                  Project_Tools.Files.Write_Text_File
                    (Root & "/src/nested/alpha.ads", "package Alpha is end Alpha;" & ASCII.LF);
                  begin
                     declare
                        Duplicate_Units : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
                          Ada_Quality.Coverage.Production_Units (Root);
                     begin
                        Rejected := Duplicate_Units.Is_Empty;
                     end;
                  exception
                     when Constraint_Error => Rejected := True;
                  end;
                  Assert (Rejected, "coverage inventory rejects duplicate production specification stems");
               end;
               Project_Tools.Files.Delete_Tree (Root);
               declare
                  Project_Root : constant String :=
                    Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
                  Project_Policy  : constant Ada_Quality.Policy.Quality_Policy := Ada_Quality.Policy.Default;
                  Project_Metrics : constant Ada_Quality.Checks.Source_Analysis :=
                    Ada_Quality.Checks.Analyze_Source (Project_Root, Project_Policy);

                  function Complexity_Evidence return String is
                  begin
                     for Finding of Project_Metrics.Findings loop
                        if Finding.Indicator = SRC_03 then
                           return " in " & To_String (Finding.Relative_Path) &
                             ":" & Natural'Image (Finding.Line);
                        end if;
                     end loop;
                     return "";
                  end Complexity_Evidence;
               begin
                  Assert (Project_Metrics.Maximum_Complexity <= Project_Policy.Maximum_Complexity,
                    "the integrated source tree remains within the declared complexity contract; measured" &
                    Natural'Image (Project_Metrics.Maximum_Complexity) & Complexity_Evidence);
                  Assert (Ada_Quality.Checks.Project_State_Fingerprint (Project_Root)'Length > 0,
                    "project-state fingerprinting streams large generated artifacts without exhausting the stack");
               end;
            end;

         when Status_Test =>
            Assert
              (Is_Valid
                 ((Indicator => STR_01, Execution => Succeeded, Compliance => Pass, Applicable => True,
                   Summary => Null_Unbounded_String, Evidence => Null_Unbounded_String,
                   Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>)),
               "succeeded/pass combination is valid");
            Assert
              (not Is_Valid
                 ((Indicator => STR_01, Execution => Blocked, Compliance => Pass, Applicable => True,
                   Summary => Null_Unbounded_String, Evidence => Null_Unbounded_String,
                   Measurement => (Kind => Unavailable_Value, Reason => Null_Unbounded_String), Findings => <>)),
               "blocked evidence cannot pass");
            declare
               Evaluated : constant Indicator_Result := Ada_Quality.Evaluation.Evaluate
                 (STR_01, Succeeded, True, False, "present", "missing", "fixture");
            begin
               Assert (Evaluated.Compliance = Violation and then Is_Valid (Evaluated),
                 "the evaluator maps successful negative evidence to a valid violation");
            end;
            declare
               Value : Assessment;
            begin
               Value.Project_Id := 1;
               Value.Status := Assessment_Completed;
               for Indicator in Indicator_Id loop
                  Value.Results.Append
                    (Indicator_Result'(Indicator => Indicator, Execution => Succeeded, Compliance => Pass,
                      Applicable => True, Summary => To_Unbounded_String ("pass"),
                      Evidence => To_Unbounded_String ("evidence"),
                      Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>));
               end loop;
               Assert (Is_Publishable (Value), "complete unique terminal results are publishable");
               Value.Results.Delete_Last;
               Assert (not Is_Publishable (Value), "partial assessments are not publishable");
            end;

         when Policy_Test =>
            declare
               Path : constant String := "/tmp/ada_quality_policy_test.toml";
               File : Ada.Text_IO.File_Type;
               Loaded : Ada_Quality.Policy.Load_Result;
            begin
               if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (not Loaded.Success, "a missing policy returns a structured load failure");
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
               Ada.Text_IO.Put_Line (File, "# resource policy");
               Ada.Text_IO.Put_Line (File, "coverage_minimum_basis_points = 9000");
               Ada.Text_IO.Put_Line (File, "maximum_source_lines = 800");
               Ada.Text_IO.Put_Line (File, "maximum_complexity = 12");
               Ada.Text_IO.Put_Line (File, "process_timeout_seconds = 30");
               Ada.Text_IO.Put_Line (File, "maximum_output_bytes = 4096");
               Ada.Text_IO.Put_Line (File, "require_clean_worktree = true");
               Ada.Text_IO.Close (File);
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (Loaded.Success, "valid policy loads");
               Assert (Loaded.Value.Maximum_Source_Lines = 800, "policy values are decoded");
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
               Ada.Text_IO.Put_Line (File, "maximum_source_lines = 700 # bounded source size");
               Ada.Text_IO.Put_Line (File, "require_clean_worktree = false # explicit TOML boolean");
               Ada.Text_IO.Close (File);
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (Loaded.Success and then Loaded.Value.Maximum_Source_Lines = 700 and then
                 not Loaded.Value.Require_Clean_Worktree,
                 "policy parsing accepts TOML inline comments without weakening value validation");
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
               Ada.Text_IO.Put_Line (File, "[unsupported]");
               Ada.Text_IO.Put_Line (File, "maximum_complexity = 12");
               Ada.Text_IO.Close (File);
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (not Loaded.Success, "unsupported TOML sections are rejected instead of ignored");
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
               Ada.Text_IO.Put_Line (File, "maximum_complexity = 12");
               Ada.Text_IO.Put_Line (File, "maximum_complexity = 13");
               Ada.Text_IO.Close (File);
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (not Loaded.Success, "duplicate policy keys are rejected");
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
               Ada.Text_IO.Put_Line (File, "not an assignment");
               Ada.Text_IO.Close (File);
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (not Loaded.Success, "malformed policy lines are rejected");
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
               Ada.Text_IO.Put_Line (File, "unknown_setting = 1");
               Ada.Text_IO.Close (File);
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (not Loaded.Success, "unknown policy keys are rejected");
               Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
               Ada.Text_IO.Put_Line (File, "maximum_output_bytes = 16777217");
               Ada.Text_IO.Close (File);
               Loaded := Ada_Quality.Policy.Load (Path);
               Assert (not Loaded.Success, "unsafe policy resource limits are rejected");
               Ada.Directories.Delete_File (Path);
            end;

         when JSON_Test =>
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
                  Exit_Code => 0, Output_Digest => To_Unbounded_String ("digest"),
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
                            Relative_Path => To_Unbounded_String ("src/example.adb"), Line => 1,
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
                  Root : constant String :=
                    Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
               begin
                  Jsonlib.Parsers.Parse
                    (Project_Tools.Files.Read_Raw_File (Root & "/docs/assessment.schema.json"), Doc, Error);
                  Assert (not Jsonlib.Errors.Failed (Error), "assessment JSON schema is valid JSON");
                  Jsonlib.Parsers.Parse
                    (Project_Tools.Files.Read_Raw_File (Root & "/docs/archive.schema.json"), Doc, Error);
                  Assert (not Jsonlib.Errors.Failed (Error), "archive JSON schema is valid JSON");
               end;
            end;

         when Storage_Test =>
            declare
               Path  : constant String := "/tmp/ada_quality_storage_test.db";
               Root  : constant String :=
                 Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
               Store : Ada_Quality.Storage.Store;
               Pid   : Positive;
               Run_Id : Positive;
               Count  : Natural;
               Value  : Assessment;
               Raised : Boolean := False;
            begin
               if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
               Ada_Quality.Storage.Open (Store, Path);
               Ada_Quality.Storage.Check (Store);
               Assert (Ada_Quality.Storage.Schema_Version (Store) = 3,
                 "new databases use the current migrated schema version");
               Pid := Ada_Quality.Storage.Add_Project (Store, Root);
               Assert (Pid = 1, "first persisted project ID is one");
               Ada_Quality.Storage.Close (Store);
               Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
               Assert (Ada_Quality.Storage.Project (Store, 1).Enabled, "project survives close and reopen");
               Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source", "policy");
               Assert (Run_Id = 1, "first assessment ID is one");
               Ada_Quality.Storage.Close (Store);
               Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
               Ada_Quality.Storage.Recover (Store, Count);
               Assert (Count = 1, "recovery marks one abandoned running assessment");
               Assert (To_String (Ada_Quality.Storage.History (Store).Last_Element.Status) = "interrupted",
                 "recovered assessment is interrupted");
               Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source-2", "policy");
               Value.Id := Run_Id;
               Value.Project_Id := Pid;
               Value.Status := Assessment_Completed;
               Value.Source_Fingerprint := To_Unbounded_String ("source-2");
               Value.Policy_Fingerprint := To_Unbounded_String ("policy");
               Value.Toolchain_Fingerprint := To_Unbounded_String ("toolchain");
               Value.Executions.Append
                 (Tool_Execution'(Tool => To_Unbounded_String ("fixture"),
                  Command => To_Unbounded_String ("/bin/fixture"), Status => Tool_Completed,
                  Exit_Code => 0, Output_Digest => To_Unbounded_String ("digest"),
                  Output_Bytes => 4, Truncated => False));
               for Indicator in Indicator_Id loop
                  Value.Results.Append
                    (Indicator_Result'(Indicator => Indicator, Execution => Succeeded, Compliance => Pass,
                      Applicable => True, Summary => To_Unbounded_String ("pass"),
                      Evidence => To_Unbounded_String ("test"),
                      Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>));
               end loop;
               declare
                  First_Result : Indicator_Result := Value.Results.First_Element;
               begin
                  First_Result.Findings.Append
                    (Finding'(Indicator => STR_01, Rule => To_Unbounded_String ("storage-fixture"), Level => Low,
                      Message => To_Unbounded_String ("persisted finding"),
                      Relative_Path => To_Unbounded_String ("src/fixture.adb"), Line => 1,
                      Fingerprint => To_Unbounded_String ("STR-01:storage-fixture:src/fixture.adb")));
                  Value.Results.Replace_Element (Value.Results.First_Index, First_Result);
               end;
               Assert (Ada_Quality.Storage.Publish (Store, Value) = Run_Id,
                 "publication finalizes the pre-created running assessment");
               Assert (Ada_Quality.Storage.Measurements (Store, Run_Id).Length = 33,
                 "typed measurement rows are persisted for every indicator");
               Assert (Ada_Quality.Storage.Executions (Store, Run_Id).Length = 1,
                 "individual tool execution rows are persisted");
               Value.Id := 0;
               Value.Status := Assessment_Completed;
               declare
                  Regressed : Indicator_Result := Value.Results.First_Element;
                  Escalated : Finding := Regressed.Findings.First_Element;
               begin
                  Regressed.Compliance := Violation;
                  Regressed.Summary := To_Unbounded_String ("regressed");
                  Escalated.Level := High;
                  Regressed.Findings.Replace_Element (Regressed.Findings.First_Index, Escalated);
                  Value.Results.Replace_Element (Value.Results.First_Index, Regressed);
               end;
               Assert (Ada_Quality.Storage.Publish (Store, Value) = 3,
                 "direct publication remains available for imported terminal assessments");
               declare
                  Archive : constant String := Ada_Quality.JSON.Render_Archive (Store);
               begin
                  Assert (Ada.Strings.Fixed.Index (Archive, """new-violation""") > 0 and then
                    Ada.Strings.Fixed.Index (Archive, """increased-severity""") > 0 and then
                    Ada.Strings.Fixed.Index (Archive, """measurements""") > 0 and then
                    Ada.Strings.Fixed.Index (Archive, """executions""") > 0,
                    "archive JSON exports persisted evidence and derived regressions");
               end;
               Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "interrupt-source", "policy");
               Ada_Quality.Storage.Testing_Inject_Next_Fault
                 (Ada_Quality.Storage.Assessment_Interruption_Commit);
               Raised := False;
               begin
                  Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, "faulted interruption");
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then
                 To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "running" and then
                 Ada_Quality.Storage.Events (Store, Run_Id).Length = 1,
                 "an interruption commit fault rolls back both state and event");
               Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, "controlled test interruption");
               Assert (To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "interrupted",
                 "explicit interruption atomically closes a running assessment");
               Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
                 "explicit interruption records its terminal event");
               Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, "duplicate interruption");
               Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
                 "interrupting an already terminal assessment is idempotent");
               Ada_Quality.Storage.Close (Store);
               Ada.Directories.Delete_File (Path);
            end;

         when Execution_Test =>
            declare
               Hostile_Root : constant String := "/tmp/ada quality ; hostile";
               Signal_Path  : constant String := Hostile_Root & "/signal fixture.sh";
               Slow : constant Ada_Quality.Execution.Run_Result :=
                 Ada_Quality.Execution.Run
                   (Directory => Ada.Directories.Current_Directory,
                    Program => "sleep",
                    Arguments => Project_Tools.Processes.Arguments
                      ([Project_Tools.Processes.Argument ("2")]),
                    Timeout_Seconds => 1,
                    Maximum_Bytes => 128);
               Loud : constant Ada_Quality.Execution.Run_Result :=
                 Ada_Quality.Execution.Run
                   (Directory => Ada.Directories.Current_Directory,
                    Program => "printf",
                    Arguments => Project_Tools.Processes.Arguments
                      ([Project_Tools.Processes.Argument ("0123456789")]),
                    Timeout_Seconds => 2,
                    Maximum_Bytes => 5);
               Flood : constant Ada_Quality.Execution.Run_Result :=
                 Ada_Quality.Execution.Run
                   (Directory => Ada.Directories.Current_Directory,
                    Program => "seq",
                    Arguments => Project_Tools.Processes.Arguments
                      ([Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("5000")]),
                    Timeout_Seconds => 2,
                    Maximum_Bytes => 5);
               Missing : constant Ada_Quality.Execution.Run_Result :=
                 Ada_Quality.Execution.Run
                   (Directory => Ada.Directories.Current_Directory,
                    Program => "ada-quality-command-that-does-not-exist",
                    Arguments => Project_Tools.Processes.No_Arguments,
                    Timeout_Seconds => 1,
                    Maximum_Bytes => 32);
            begin
               Project_Tools.Files.Delete_Tree (Hostile_Root);
               Ada.Directories.Create_Path (Hostile_Root);
               Project_Tools.Files.Write_Text_File
                 (Signal_Path,
                  "#!/bin/sh" & ASCII.LF & "printf 'stderr-evidence\n' >&2" & ASCII.LF &
                  "kill -TERM $$" & ASCII.LF);
               declare
                  Chmod : constant Ada_Quality.Execution.Run_Result :=
                    Ada_Quality.Execution.Run
                      (Hostile_Root, "chmod",
                       Project_Tools.Processes.Arguments
                         ([Project_Tools.Processes.Argument ("+x"),
                           Project_Tools.Processes.Argument (Signal_Path)]), 2, 128);
                  Hostile_Argument : constant String := "$(touch /tmp/ada_quality_injected) ; literal";
                  Literal : constant Ada_Quality.Execution.Run_Result :=
                    Ada_Quality.Execution.Run
                      (Hostile_Root, "printf",
                       Project_Tools.Processes.Arguments
                         ([Project_Tools.Processes.Argument (Hostile_Argument)]), 2, 256);
                  Signalled : constant Ada_Quality.Execution.Run_Result :=
                    Ada_Quality.Execution.Run
                      (Hostile_Root, Signal_Path, Project_Tools.Processes.No_Arguments, 2, 256);
               begin
                  Assert (Chmod.Status = Ada_Quality.Execution.Completed and then Chmod.Exit_Code = 0,
                    "hostile-path signal fixture is executable");
                  Assert (Literal.Status = Ada_Quality.Execution.Completed and then
                    To_String (Literal.Output) = Hostile_Argument and then
                    not Project_Tools.Files.Exists ("/tmp/ada_quality_injected"),
                    "arguments and hostile working-directory characters are never shell-interpolated");
                  Assert (Signalled.Status = Ada_Quality.Execution.Completed and then
                    Signalled.Exit_Code /= 0 and then
                    Ada.Strings.Fixed.Index (To_String (Signalled.Output), "stderr-evidence") > 0,
                    "signal termination is non-passing and stderr is captured as bounded evidence");
               end;
               Assert (Slow.Status = Ada_Quality.Execution.Timed_Out, "process timeout is enforced");
               Assert (Loud.Status = Ada_Quality.Execution.Completed and then Loud.Truncated,
                 "captured process output is bounded");
               Assert (Length (Loud.Output) = 5, "bounded output has the configured maximum length");
               Assert (Flood.Status = Ada_Quality.Execution.Completed and then Flood.Truncated,
                 "output larger than the internal process buffer completes with bounded capture");
               Assert (Length (Flood.Output) = 5, "large streamed output retains only the configured byte limit");
               Assert (Missing.Status = Ada_Quality.Execution.Spawn_Error, "missing executable is a spawn error");
               Ada.Environment_Variables.Set ("ADA_QUALITY_TEST_SECRET", "must-not-reach-child");
               declare
                  Child_Environment : constant Ada_Quality.Execution.Run_Result :=
                    Ada_Quality.Execution.Run
                      (Directory => Ada.Directories.Current_Directory, Program => "env",
                       Arguments => Project_Tools.Processes.No_Arguments,
                       Timeout_Seconds => 2, Maximum_Bytes => 4_096);
               begin
                  Ada.Environment_Variables.Clear ("ADA_QUALITY_TEST_SECRET");
                  Assert (Child_Environment.Status = Ada_Quality.Execution.Completed,
                    "allowlisted child environment can execute");
                  Assert
                    (Ada.Strings.Fixed.Index (To_String (Child_Environment.Output), "ADA_QUALITY_TEST_SECRET") = 0,
                     "non-allowlisted environment variables do not reach child tools");
               exception
                  when others =>  --  AQ: audited exception boundary
                     Ada.Environment_Variables.Clear ("ADA_QUALITY_TEST_SECRET");
                     raise;
               end;
               declare
                  Home_Root          : constant String := Hostile_Root & "/home";
                  Settings_Directory : constant String := Home_Root & "/.config/alire";
                  Data_Directory     : constant String := Home_Root & "/.local/share/alire";
                  Had_Home           : constant Boolean := Ada.Environment_Variables.Exists ("HOME");
                  Saved_Home         : constant String :=
                    (if Had_Home then Ada.Environment_Variables.Value ("HOME") else "");
                  Had_Settings       : constant Boolean :=
                    Ada.Environment_Variables.Exists ("ALIRE_SETTINGS_DIR");
                  Saved_Settings     : constant String :=
                    (if Had_Settings then Ada.Environment_Variables.Value ("ALIRE_SETTINGS_DIR") else "");
                  Had_Config         : constant Boolean :=
                    Ada.Environment_Variables.Exists ("XDG_CONFIG_HOME");
                  Saved_Config       : constant String :=
                    (if Had_Config then Ada.Environment_Variables.Value ("XDG_CONFIG_HOME") else "");
                  Had_Data           : constant Boolean :=
                    Ada.Environment_Variables.Exists ("XDG_DATA_HOME");
                  Saved_Data         : constant String :=
                    (if Had_Data then Ada.Environment_Variables.Value ("XDG_DATA_HOME") else "");

                  procedure Restore_Environment is
                  begin
                     if Had_Home then
                        Ada.Environment_Variables.Set ("HOME", Saved_Home);
                     else
                        Ada.Environment_Variables.Clear ("HOME");
                     end if;
                     if Had_Settings then
                        Ada.Environment_Variables.Set ("ALIRE_SETTINGS_DIR", Saved_Settings);
                     else
                        Ada.Environment_Variables.Clear ("ALIRE_SETTINGS_DIR");
                     end if;
                     if Had_Config then
                        Ada.Environment_Variables.Set ("XDG_CONFIG_HOME", Saved_Config);
                     else
                        Ada.Environment_Variables.Clear ("XDG_CONFIG_HOME");
                     end if;
                     if Had_Data then
                        Ada.Environment_Variables.Set ("XDG_DATA_HOME", Saved_Data);
                     else
                        Ada.Environment_Variables.Clear ("XDG_DATA_HOME");
                     end if;
                  end Restore_Environment;
               begin
                  Ada.Directories.Create_Path (Settings_Directory);
                  Ada.Directories.Create_Path (Data_Directory);
                  Ada.Environment_Variables.Set ("HOME", Home_Root);
                  Ada.Environment_Variables.Clear ("ALIRE_SETTINGS_DIR");
                  Ada.Environment_Variables.Clear ("XDG_CONFIG_HOME");
                  Ada.Environment_Variables.Clear ("XDG_DATA_HOME");
                  declare
                     Child_Environment : constant Ada_Quality.Execution.Run_Result :=
                       Ada_Quality.Execution.Run
                         (Directory => Ada.Directories.Current_Directory, Program => "env",
                          Arguments => Project_Tools.Processes.No_Arguments,
                          Timeout_Seconds => 2, Maximum_Bytes => 4_096);
                  begin
                     Restore_Environment;
                     Assert
                       (Ada.Strings.Fixed.Index
                          (To_String (Child_Environment.Output),
                           "XDG_CONFIG_HOME=" & Home_Root & "/.config") > 0 and then
                        Ada.Strings.Fixed.Index
                          (To_String (Child_Environment.Output),
                           "XDG_DATA_HOME=" & Home_Root & "/.local/share") > 0,
                        "conventional user config and data directories reach the clean environment");
                  end;
               exception
                  when others =>  --  AQ: audited exception boundary
                     Restore_Environment;
                     raise;
               end;
               Project_Tools.Files.Write_Text_File
                 (Hostile_Root & "/warning_fixture.adb",
                  "with Ada.Text_IO;" & ASCII.LF &
                  "procedure Warning_Fixture is" & ASCII.LF &
                  "begin" & ASCII.LF & "   null;" & ASCII.LF &
                  "end Warning_Fixture;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Hostile_Root & "/warning_fixture.gpr",
                  "project Warning_Fixture is" & ASCII.LF &
                  "   for Source_Dirs use (""."");" & ASCII.LF &
                  "   for Object_Dir use ""warning-obj"";" & ASCII.LF &
                  "   for Main use (""warning_fixture.adb"");" & ASCII.LF &
                  "   package Compiler is" & ASCII.LF &
                  "      for Default_Switches (""Ada"") use " &
                  "(""-gnat2022"", ""-gnatwa"", ""-gnatVa"");" & ASCII.LF &
                  "   end Compiler;" & ASCII.LF &
                  "end Warning_Fixture;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Hostile_Root & "/warning_gate.gpr",
                  "project Warning_Gate extends ""warning_fixture.gpr"" is" & ASCII.LF &
                  "   package Compiler is" & ASCII.LF &
                  "      for Default_Switches (""Ada"") use " &
                  "Warning_Fixture.Compiler'Default_Switches (""Ada"") & " &
                  "(""-gnatwa"", ""-gnatwe"");" & ASCII.LF &
                  "   end Compiler;" & ASCII.LF &
                  "end Warning_Gate;" & ASCII.LF);
               declare
                  Warning_Build : constant Ada_Quality.Execution.Run_Result :=
                    Ada_Quality.Execution.Run
                      (Hostile_Root, "gprbuild",
                       Project_Tools.Processes.Arguments
                         ([Project_Tools.Processes.Argument ("-P"),
                           Project_Tools.Processes.Argument ("warning_gate.gpr"),
                           Project_Tools.Processes.Argument ("-f"),
                           Project_Tools.Processes.Argument ("-p"),
                           Project_Tools.Processes.Argument ("-v")]),
                       Timeout_Seconds => 20, Maximum_Bytes => 4_096);
                  Warning_Output : constant String :=
                    Ada.Characters.Handling.To_Lower (To_String (Warning_Build.Output));
               begin
                  Assert (Warning_Build.Status = Ada_Quality.Execution.Completed and then
                    Warning_Build.Exit_Code /= 0 and then
                    Ada.Strings.Fixed.Index (Warning_Output, "ada.text_io") > 0 and then
                    Ada.Strings.Fixed.Index (Warning_Output, "not referenced") > 0,
                    "BLD-03 wrapper rejects the target warning while extending inherited switches" &
                    ASCII.LF & To_String (Warning_Build.Output));
               end;
               Project_Tools.Files.Delete_Tree (Hostile_Root);
            end;

         when Applicability_Test =>
            declare
               Root : constant String := "/tmp/ada_quality_spark_test";
               Path : constant String := Root & "/src/example.ads";
            begin
               if Project_Tools.Files.Exists (Root) then Project_Tools.Files.Delete_Tree (Root); end if;
               Ada.Directories.Create_Path (Root & "/src");
               Project_Tools.Files.Write_Text_File
                 (Path,
                  "--  SPARK_Mode in a comment" & ASCII.LF &
                  "package Example is" & ASCII.LF &
                  "   Label : constant String := ""SPARK_Mode"";" & ASCII.LF &
                  "end Example;" & ASCII.LF);
               Assert (not Ada_Quality.Checks.Declares_SPARK (Root),
                 "comments and string literals do not declare SPARK");
               Project_Tools.Files.Write_Text_File
                 (Path,
                  "package Example is" & ASCII.LF &
                  "   Not_SPARK_Mode : constant Boolean := False;" & ASCII.LF &
                  "end Example;" & ASCII.LF);
               Assert (not Ada_Quality.Checks.Declares_SPARK (Root),
                 "SPARK applicability requires an exact language token");
               Project_Tools.Files.Write_Text_File
                 (Path,
                  "pragma SPARK_Mode (On);" & ASCII.LF &
                  "package Example is end Example;" & ASCII.LF);
               Assert (Ada_Quality.Checks.Declares_SPARK (Root), "SPARK pragma is detected in Ada code");
               Project_Tools.Files.Write_Text_File (Path, "package Example is end Example;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/spark.adc", "pragma SPARK_Mode (On);" & ASCII.LF);
               Assert (Ada_Quality.Checks.Declares_SPARK (Root),
                 "project configuration pragmas make SPARK proof applicable");
               Assert (Ada_Quality.Checks.Test_Project_File (Root) = "" and then
                 Ada_Quality.Checks.Test_Suite_Executable (Root) = "",
                 "a project without a tests crate has no test suite");
               Ada.Directories.Create_Path (Root & "/tests");
               Project_Tools.Files.Write_Text_File
                 (Root & "/tests/alire.toml",
                  "name = ""example_tests""" & ASCII.LF &
                  "executables = [""example_suite"", ""example_tool""]  # the suite comes first" & ASCII.LF);
               Assert (Ada_Quality.Checks.Test_Project_File (Root) = Root & "/tests/example_tests.gpr",
                 "the tests project defaults to the tests crate's name");
               Assert (Ada_Quality.Checks.Test_Suite_Executable (Root) = Root & "/tests/bin/example_suite",
                 "the suite is the tests crate's first executable");
               Project_Tools.Files.Write_Text_File
                 (Root & "/tests/suite.gpr", "project Suite is end Suite;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/tests/alire.toml",
                  "name = ""example_tests""" & ASCII.LF & "project-files = [""suite.gpr""]" & ASCII.LF);
               Assert (Ada_Quality.Checks.Test_Project_File (Root) = Root & "/tests/suite.gpr",
                 "a listed project file names the tests project");
               Assert (Ada_Quality.Checks.Test_Suite_Executable (Root) = Root & "/tests/bin/example_tests",
                 "without executables the suite is named after the tests crate");
               Assert (Ada_Quality.Checks.Dedicated_Proof_Projects (Root)'Length = 0,
                 "a project without spark*.gpr files proves its main project");
               Project_Tools.Files.Write_Text_File
                 (Root & "/spark_b.gpr", "project Spark_B is end Spark_B;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/spark_a.gpr", "project Spark_A is end Spark_A;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/example.gpr", "project Example is end Example;" & ASCII.LF);
               declare
                  Proofs : constant Project_Tools.Files.Path_List := Ada_Quality.Checks.Dedicated_Proof_Projects (Root);
               begin
                  Assert (Proofs'Length = 2 and then
                    Ada.Strings.Unbounded.To_String (Proofs (Proofs'First)) = Root & "/spark_a.gpr" and then
                    Ada.Strings.Unbounded.To_String (Proofs (Proofs'Last)) = Root & "/spark_b.gpr",
                    "dedicated proof projects are found in name order");
               end;
               Ada.Directories.Create_Path (Root & "/bin");
               declare
                  Chunk : constant String (1 .. 1_024 * 1_024) := [others => 'x'];
                  Large : Ada.Text_IO.File_Type;
               begin
                  Ada.Text_IO.Create (Large, Ada.Text_IO.Out_File, Root & "/bin/large");
                  for Megabyte in 1 .. 65 loop
                     Ada.Text_IO.Put (Large, Chunk);
                  end loop;
                  Ada.Text_IO.Close (Large);
               end;
               Assert (Ada_Quality.Checks.Project_State_Fingerprint (Root)'Length = 16 + 1 + 16,
                 "artifacts larger than the source-file limit are hashed as a stream");
               Project_Tools.Files.Delete_Tree (Root);
            end;

         when Source_Analysis_Test =>
            declare
               Root   : constant String := "/tmp/ada_quality_source_analysis_test";
               Policy : Ada_Quality.Policy.Quality_Policy;
               Metrics : Ada_Quality.Checks.Source_Analysis;
               Long_Line : constant String := "   Value : constant String := """ &
                 [1 .. 121 => 'x'] & """;";
            begin
               Project_Tools.Files.Delete_Tree (Root);
               Ada.Directories.Create_Path (Root & "/src");
               Ada.Directories.Create_Path (Root & "/tests/src");
               Ada.Directories.Create_Path (Root & "/config");
               Policy.Maximum_Source_Lines := 5;
               Policy.Maximum_Complexity := 3;
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/Documented.ads",
                  "--  Public package documentation." & ASCII.LF &
                  "package Documented is" & ASCII.LF &
                  "end Documented;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/undocumented.ads",
                  "package Undocumented is" & ASCII.LF &
                  "end Undocumented;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/example.adb",
                  "procedure Example is" & ASCII.LF &
                  "begin" & ASCII.LF &
                  "   if Ready and then Enabled then" & ASCII.LF &
                  "      null;" & ASCII.LF &
                  "   elsif Waiting then" & ASCII.LF &
                  "      null;" & ASCII.LF &
                  "   end if;" & ASCII.LF &
                  "   Label := ""password := Run_Shell"";" & ASCII.LF &
                  "   -- Password := and Run_Shell are inert in comments." & ASCII.LF &
                  "   Password := ""redacted"";" & ASCII.LF &
                  "   Run_Shell;" & ASCII.LF &
                  "   Register_Routine;" & ASCII.LF &
                  Long_Line & ASCII.LF &
                  "exception" & ASCII.LF &
                  "   when others => null;" & ASCII.LF &
                  "end Example;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/tests/src/example_tests.adb",
                  "procedure Example_Tests is begin Register_Routine; end Example_Tests;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/nested.adb",
                  "--  AQ: size-reviewed" & ASCII.LF &
                  "procedure Nested is" & ASCII.LF &
                  "   function Expression (Flag : Boolean) return Boolean is (Flag and then Ready);" & ASCII.LF &
                  "   procedure Inner is" & ASCII.LF &
                  "   begin" & ASCII.LF &
                  "      case Value is" & ASCII.LF &
                  "         when One => null;" & ASCII.LF &
                  "         when others => null;" & ASCII.LF &
                  "      end case;" & ASCII.LF &
                  "   end Inner;" & ASCII.LF &
                  "begin" & ASCII.LF &
                  "   while Ready loop exit; end loop;" & ASCII.LF &
                  "end Nested;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/config/example_config.ads", "package Example_Config is end Example_Config;" & ASCII.LF);
               Metrics := Ada_Quality.Checks.Analyze_Source (Root, Policy);
               Assert (Metrics.File_Count = 5 and then Metrics.Spec_Count = 2 and then
                 Metrics.Production_Files = 4 and then Metrics.Test_Files = 1 and then
                 Metrics.Generated_Files = 1,
                 "native inventory distinguishes production, test, and generated Ada sources");
               Assert (Metrics.Naming_Errors = 1, "non-lowercase Ada file names are findings");
               Assert (Metrics.Undocumented_Specs = 1,
                 "a standalone package documentation comment is required");
               Assert (Metrics.Maximum_Complexity = 5,
                 "defined complexity covers conditionals, short circuits, alternatives, loops, " &
                 "nested declarations, and expression functions");
               Assert (Metrics.Long_Lines = 1 and then Metrics.Oversized_Files = 1,
                 "line and file-size policy violations are measured");
               Assert (Metrics.Secret_Matches = 1 and then Metrics.Unsafe_Processes = 1,
                 "credential and shell patterns are detected without comment/string false positives");
               Assert (Metrics.Broad_Handlers = 1 and then Metrics.Test_Registrations = 2,
                 "broad handlers and test registrations use Ada-aware source scans");
               Assert (Metrics.Findings.Length >= 7, "native violations carry structured findings");
               Policy.Require_Clean_Worktree := False;
               --  A SPARK unit with a dedicated proof project: PRF-01 proves that project, which cannot pass here.
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/proved.ads",
                  "pragma SPARK_Mode (On);" & ASCII.LF & "package Proved is end Proved;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/spark_example.gpr", "project Spark_Example is end Spark_Example;" & ASCII.LF);
               declare
                  Incomplete : constant Assessment := Ada_Quality.Checks.Assess (98_765, Root, Policy);
                  Proof      : Indicator_Result;
               begin
                  Assert (Incomplete.Results.Length = 33 and then
                    Incomplete.Status = Assessment_Completed,
                    "an incomplete project still produces all 33 explicit pass, violation, or blocked results");
                  for Item of Incomplete.Results loop
                     if Item.Indicator = PRF_01 then
                        Proof := Item;
                     end if;
                  end loop;
                  Assert (Proof.Indicator = PRF_01 and then Proof.Applicable and then Proof.Compliance /= Pass,
                    "a dedicated proof project is proved, and a failed proof cannot pass");
               end;
               Project_Tools.Files.Delete_Tree (Root);
            end;

         when Integrity_Test =>
            declare
               Path   : constant String := "/tmp/ada_quality_integrity_test.db";
               Fault_Path : constant String := "/tmp/ada_quality_creation_fault.db";
               Bad_Root : constant String := "/tmp/ada_quality_bad_manifest";
               Link_Root : constant String := "/tmp/ada_quality_project_link";
               Unicode_Root : constant String := "/tmp/ada_quality_ünicode_project";
               Root   : constant String :=
                 Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
               Store  : Ada_Quality.Storage.Store;
               Locked_Store : Ada_Quality.Storage.Store;
               Missing_Store : Ada_Quality.Storage.Store;
               Value  : Assessment;
               Pid    : Positive;
               Run_Id : Positive;
               Count  : Natural;
               Raised : Boolean := False;
            begin
               Project_Tools.Files.Delete_File_If_Present (Path);
               Project_Tools.Files.Delete_File_If_Present (Fault_Path);
               Ada_Quality.Storage.Testing_Inject_Next_Fault
                 (Ada_Quality.Storage.Schema_Creation_Commit);
               Raised := False;
               begin
                  Ada_Quality.Storage.Open (Missing_Store, Fault_Path);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then not Ada_Quality.Storage.Is_Open (Missing_Store),
                 "a schema-creation commit fault closes the incomplete store");
               Project_Tools.Files.Delete_File_If_Present (Fault_Path);
               Raised := False;
               begin
                  Ada_Quality.Storage.Open
                    (Missing_Store, "/tmp/ada_quality_missing_storage.db", Create_If_Missing => False);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then not Ada_Quality.Storage.Is_Open (Missing_Store),
                 "opening a missing database without creation fails closed");
               Raised := False;
               begin
                  Ada_Quality.Storage.Check (Missing_Store);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "integrity checking a closed database is rejected");
               Raised := False;
               begin
                  Run_Id := Ada_Quality.Storage.Schema_Version (Missing_Store);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "reading a schema version from a closed database fails safely");
               Raised := False;
               begin
                  Ada_Quality.Storage.Testing_Set_Schema_Version (Missing_Store, 2);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "writing a schema version to a closed database fails safely");
               Ada_Quality.Storage.Open (Store, Path);
               Assert (Ada_Quality.Storage.Is_Open (Store), "created database reports open");
               Raised := False;
               begin
                  Pid := Ada_Quality.Storage.Project (Store, 999).Id;
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "loading a missing project fails without leaking a read transaction");
               Raised := False;
               begin
                  Pid := Ada_Quality.Storage.Add_Project (Store, "/tmp/ada_quality_missing_project_root");
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "a missing project root cannot be registered");
               Project_Tools.Files.Delete_Tree (Link_Root);
               declare
                  Link_Run : constant Ada_Quality.Execution.Run_Result := Ada_Quality.Execution.Run
                    (Ada.Directories.Current_Directory, "ln",
                     Project_Tools.Processes.Arguments
                       ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Root),
                         Project_Tools.Processes.Argument (Link_Root)]),
                     Timeout_Seconds => 2, Maximum_Bytes => 128);
               begin
                  Assert (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
                    "project-root symlink fixture is created");
               end;
               Raised := False;
               begin
                  Pid := Ada_Quality.Storage.Add_Project (Store, Link_Root);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "a symbolic-link project root cannot be registered");
               Project_Tools.Files.Delete_Tree (Link_Root);
               Raised := False;
               begin
                  Ada_Quality.Storage.Open (Locked_Store, Path, Create_If_Missing => False);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "a second process-style handle observes the persistent lock conflict");
               Project_Tools.Files.Delete_Tree (Bad_Root);
               Ada.Directories.Create_Path (Bad_Root);
               Project_Tools.Files.Write_Text_File (Bad_Root & "/alire.toml", "name = ""broken""" & ASCII.LF);
               Raised := False;
               begin
                  Pid := Ada_Quality.Storage.Add_Project (Store, Bad_Root);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "malformed Alire manifests are rejected by the registry");
               Project_Tools.Files.Delete_Tree (Bad_Root);
               Project_Tools.Files.Delete_Tree (Unicode_Root);
               Ada.Directories.Create_Path (Unicode_Root);
               Project_Tools.Files.Write_Text_File
                 (Unicode_Root & "/alire.toml", "name = ""unicode_project""" & ASCII.LF &
                  "version = ""0.1.0""" & ASCII.LF);
               declare
                  Unicode_Id : constant Positive := Ada_Quality.Storage.Add_Project (Store, Unicode_Root);
               begin
                  Assert (To_String (Ada_Quality.Storage.Project (Store, Unicode_Id).Path) = Unicode_Root,
                    "canonical project paths round-trip valid UTF-8");
                  Ada_Quality.Storage.Remove_Project (Store, Unicode_Id);
               end;
               Project_Tools.Files.Delete_Tree (Unicode_Root);
               Pid := Ada_Quality.Storage.Add_Project (Store, Root);
               Raised := False;
               begin
                  Pid := Ada_Quality.Storage.Add_Project (Store, Root);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "duplicate active project registration is rejected");
               Raised := False;
               begin
                  Ada_Quality.Storage.Set_Enabled (Store, 999, True);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "updating a missing project is rejected");
               Ada_Quality.Storage.Set_Enabled (Store, Pid, False);
               Raised := False;
               begin
                  Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "disabled", "policy");
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "disabled projects cannot start assessments");
               Ada_Quality.Storage.Set_Enabled (Store, Pid, True);
               Ada_Quality.Storage.Testing_Inject_Next_Fault
                 (Ada_Quality.Storage.Assessment_Start_Commit);
               Raised := False;
               begin
                  Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "faulted-source", "policy");
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then Ada_Quality.Storage.History (Store, Pid).Is_Empty,
                 "an assessment-start commit fault rolls back both run and event");
               Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source", "policy");
               Value.Id := Run_Id;
               Value.Project_Id := Pid;
               Value.Status := Assessment_Completed;
               Value.Source_Fingerprint := To_Unbounded_String ([1 => Character'Val (255)]);
               Value.Policy_Fingerprint := To_Unbounded_String ("policy");
               for Indicator in Indicator_Id loop
                  Value.Results.Append
                    (Indicator_Result'(Indicator => Indicator, Execution => Succeeded, Compliance => Pass,
                      Applicable => True, Summary => To_Unbounded_String ("pass"),
                      Evidence => To_Unbounded_String ("test"),
                      Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>));
               end loop;
               Value.Status := Assessment_Running;
               Raised := False;
               begin
                  Run_Id := Ada_Quality.Storage.Publish (Store, Value);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "running assessments cannot be published as terminal evidence");
               Value.Status := Assessment_Completed;
               declare
                  Saved : constant Indicator_Result := Value.Results.Last_Element;
               begin
                  Value.Results.Delete_Last;
                  Raised := False;
                  begin
                     Run_Id := Ada_Quality.Storage.Publish (Store, Value);
                  exception
                     when Ada_Quality.Storage.Storage_Error => Raised := True;
                  end;
                  Assert (Raised, "partial result sets cannot be published");
                  Value.Results.Append (Saved);
               end;
               declare
                  Saved : constant Indicator_Result := Value.Results.Last_Element;
               begin
                  Value.Results.Replace_Element (Value.Results.Last_Index, Value.Results.First_Element);
                  Raised := False;
                  begin
                     Run_Id := Ada_Quality.Storage.Publish (Store, Value);
                  exception
                     when Ada_Quality.Storage.Storage_Error => Raised := True;
                  end;
                  Assert (Raised, "duplicate indicator results cannot be published");
                  Value.Results.Replace_Element (Value.Results.Last_Index, Saved);
               end;
               declare
                  Saved : constant Indicator_Result := Value.Results.First_Element;
                  Bad   : Indicator_Result := Saved;
               begin
                  Bad.Execution := Blocked;
                  Value.Results.Replace_Element (Value.Results.First_Index, Bad);
                  Raised := False;
                  begin
                     Run_Id := Ada_Quality.Storage.Publish (Store, Value);
                  exception
                     when Ada_Quality.Storage.Storage_Error => Raised := True;
                  end;
                  Assert (Raised, "internally inconsistent indicator results cannot be published");
                  Value.Results.Replace_Element (Value.Results.First_Index, Saved);
               end;
               begin
                  Run_Id := Ada_Quality.Storage.Publish (Store, Value);
               exception
                  when Ada_Quality.Storage.Storage_Error | Ada.Strings.UTF_Encoding.Encoding_Error =>
                     Raised := True;
               end;
               Assert (Raised, "invalid encoded evidence injects a publication failure");
               Assert (To_String (Ada_Quality.Storage.History (Store).Last_Element.Status) = "running",
                 "failed publication rolls back the assessment state");
               Assert (Ada_Quality.Storage.Results (Store, Run_Id).Length = 0,
                 "failed publication leaves no partial results");
               Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 1,
                 "failed publication leaves only the committed start event");
               Value.Source_Fingerprint := To_Unbounded_String ("source");
               Ada_Quality.Storage.Testing_Inject_Next_Fault
                 (Ada_Quality.Storage.Assessment_Publication_Commit);
               Raised := False;
               begin
                  Run_Id := Ada_Quality.Storage.Publish (Store, Value);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then Ada_Quality.Storage.Results (Store, Run_Id).Is_Empty and then
                 To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "running",
                 "a publication commit fault preserves the running record without partial evidence");
               Assert (Ada_Quality.Storage.Publish (Store, Value) = Run_Id,
                 "a valid publication succeeds after rollback");
               Raised := False;
               begin
                  Run_Id := Ada_Quality.Storage.Publish (Store, Value);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "terminal assessments are immutable");
               Assert (Ada_Quality.Storage.Results (Store, Run_Id).Length = 33,
                 "immutable assessment retains its complete result set");
               Value.Id := 0;
               Value.Status := Assessment_Interrupted;
               Run_Id := Ada_Quality.Storage.Publish (Store, Value);
               Assert (To_String (Ada_Quality.Storage.History (Store).Last_Element.Status) = "interrupted",
                 "imported interrupted assessments retain terminal status");
               Run_Id := Ada_Quality.Storage.Start_Assessment (Store, Pid, "source-2", "policy");
               Ada_Quality.Storage.Testing_Inject_Next_Fault
                 (Ada_Quality.Storage.Assessment_Recovery_Commit);
               Raised := False;
               begin
                  Ada_Quality.Storage.Recover (Store, Count);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then Ada_Quality.Storage.Events (Store, Run_Id).Length = 1 and then
                 To_String (Ada_Quality.Storage.History (Store, Pid).Last_Element.Status) = "running",
                 "a recovery commit fault rolls back state and recovery event together");
               Ada_Quality.Storage.Recover (Store, Count);
               Assert (Count = 1, "recovery handles the abandoned running assessment");
               Assert (Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
                 "recovery atomically records an event");
               Ada_Quality.Storage.Recover (Store, Count);
               Assert (Count = 0 and then Ada_Quality.Storage.Events (Store, Run_Id).Length = 2,
                 "recovery is idempotent");
               Ada_Quality.Storage.Testing_Set_Schema_Version (Store, 1);
               Ada_Quality.Storage.Close (Store);
               Ada_Quality.Storage.Testing_Inject_Next_Fault
                 (Ada_Quality.Storage.Schema_Migration_Commit);
               Raised := False;
               begin
                  Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then not Ada_Quality.Storage.Is_Open (Store),
                 "a migration commit fault leaves the database closed at its prior version");
               Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
               Assert (Ada_Quality.Storage.Schema_Version (Store) = 3,
                 "opening a version-1 database runs the explicit migration to version 3");
               Ada_Quality.Storage.Testing_Set_Schema_Version (Store, 99);
               Raised := False;
               begin
                  Ada_Quality.Storage.Check (Store);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised, "integrity checking rejects an unsupported schema version");
               Ada_Quality.Storage.Close (Store);
               Raised := False;
               begin
                  Ada_Quality.Storage.Open (Store, Path, Create_If_Missing => False);
               exception
                  when Ada_Quality.Storage.Storage_Error => Raised := True;
               end;
               Assert (Raised and then not Ada_Quality.Storage.Is_Open (Store),
                 "unsupported schema versions fail closed");
               Project_Tools.Files.Delete_File_If_Present (Path);
            end;

         when Symlink_Test =>
            declare
               Root       : constant String := "/tmp/ada_quality_symlink_test";
               Outside    : constant String := "/tmp/ada_quality_symlink_outside";
               Before     : Ada.Strings.Unbounded.Unbounded_String;
               With_Links : Ada.Strings.Unbounded.Unbounded_String;
               State_Before : Ada.Strings.Unbounded.Unbounded_String;
               Link_Run   : Ada_Quality.Execution.Run_Result;
               Stage      : Ada_Quality.Workspaces.Workspace;
               Other_Stage : Ada_Quality.Workspaces.Workspace;
               First_Scratch : Ada.Strings.Unbounded.Unbounded_String;
               Second_Scratch : Ada.Strings.Unbounded.Unbounded_String;
               Raised     : Boolean := False;
               Deep_Root  : constant String := "/tmp/ada_quality_deep_tree_test";
               Deep_Path  : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String (Deep_Root);
            begin
               Project_Tools.Files.Delete_Tree (Root);
               Project_Tools.Files.Delete_Tree (Outside);
               Ada.Directories.Create_Path (Root & "/src");
               Ada.Directories.Create_Path (Root & "/alire");
               Ada.Directories.Create_Path (Outside);
               Project_Tools.Files.Write_Text_File
                 (Root & "/src/local.adb", "procedure Local is begin null; end Local;" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Outside & "/outside.ads", "pragma SPARK_Mode (On);" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/alire.toml",
                  "name = ""local""" & ASCII.LF & "version = ""0.1.0""" & ASCII.LF &
                  "# path = ""../../../comment-is-not-a-pin""" & ASCII.LF &
                  "description = """"""an unrelated multiline value" & ASCII.LF &
                  "path = '../../../multiline-is-not-a-pin'""""""" & ASCII.LF &
                  "[[pins]]" & ASCII.LF &
                  "dependency = { ""\u0070ath"" = ""../\u0061da_quality_symlink_outside"" }" & ASCII.LF &
                  "[configuration.values]" & ASCII.LF &
                  "path = ""../../../unrelated-key-is-not-a-pin""" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Outside & "/alire.toml", "name = ""dependency""" & ASCII.LF &
                  "version = ""0.1.0""" & ASCII.LF);
               Ada_Quality.Workspaces.Prepare (Stage, Root, "toml-pin-test");
               Assert (Project_Tools.Files.File_Exists
                 (Ada_Quality.Workspaces.Path (Stage) & "/../ada_quality_symlink_outside/outside.ads"),
                 "staging accepts quoted path keys and Unicode escapes in TOML basic strings");
               Ada_Quality.Workspaces.Cleanup (Stage);
               Project_Tools.Files.Write_Text_File
                 (Root & "/alire/alire.lock",
                  "[solution.state.link]" & ASCII.LF &
                  "path = '../ada_quality_symlink_outside'" & ASCII.LF &
                  "[solution.state.release.configuration]" & ASCII.LF &
                  "path = '../../../unrelated-key-is-not-a-pin'" & ASCII.LF);
               Project_Tools.Files.Write_Text_File
                 (Root & "/alire/build_hash_inputs", "generated and stale" & ASCII.LF);
               Before := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Root));
               Link_Run := Ada_Quality.Execution.Run
                 (Root, "ln",
                  Project_Tools.Processes.Arguments
                    ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Outside),
                      Project_Tools.Processes.Argument (Root & "/src/outside")]),
                  Timeout_Seconds => 2, Maximum_Bytes => 128);
               Assert (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
                 "external-directory symlink fixture is created");
               Link_Run := Ada_Quality.Execution.Run
                 (Root, "ln",
                  Project_Tools.Processes.Arguments
                    ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Root),
                      Project_Tools.Processes.Argument (Root & "/src/cycle")]),
                  Timeout_Seconds => 2, Maximum_Bytes => 128);
               Assert (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
                 "cyclic symlink fixture is created");
               With_Links := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Root));
               Assert (Before /= With_Links, "symbolic-link paths participate in the source identity");
               Assert (not Ada_Quality.Checks.Declares_SPARK (Root),
                 "source discovery does not follow an external symbolic link");
               Project_Tools.Files.Write_Text_File
                 (Outside & "/outside.ads", "pragma SPARK_Mode (Off);" & ASCII.LF);
               Assert (To_String (With_Links) = Ada_Quality.Checks.Source_Fingerprint (Root),
                 "external link-target content cannot change the project fingerprint");
               begin
                  Ada_Quality.Workspaces.Prepare (Stage, Root, "symlink-test");
               exception
                  when Ada_Quality.Workspaces.Workspace_Error => Raised := True;
               end;
               Assert (Raised, "staging rejects symbolic links instead of following them");
               Project_Tools.Files.Delete_Tree (Root & "/src/outside");
               Project_Tools.Files.Delete_Tree (Root & "/src/cycle");
               State_Before := To_Unbounded_String (Ada_Quality.Checks.Project_State_Fingerprint (Root));
               Ada.Directories.Create_Path (Root & "/obj");
               Project_Tools.Files.Write_Text_File (Root & "/obj/generated.o", "generated");
               Assert
                 (State_Before /= To_Unbounded_String (Ada_Quality.Checks.Project_State_Fingerprint (Root)),
                  "generated build artifacts participate in the deterministic project-state fingerprint");
               Ada_Quality.Workspaces.Prepare (Stage, Root, "safe/test");
               Assert (Project_Tools.Files.File_Exists
                 (Ada_Quality.Workspaces.Path (Stage) & "/src/local.adb"), "staging copies source files");
               Assert (Project_Tools.Files.File_Exists
                 (Ada_Quality.Workspaces.Path (Stage) & "/../ada_quality_symlink_outside/outside.ads"),
                 "staging recursively copies local pin targets without using the original dependency tree");
               Assert (not Project_Tools.Files.Exists (Ada_Quality.Workspaces.Path (Stage) & "/obj"),
                 "staging excludes generated build trees");
               Assert (Project_Tools.Files.File_Exists
                 (Ada_Quality.Workspaces.Path (Stage) & "/alire/alire.lock") and then
                 not Project_Tools.Files.File_Exists
                   (Ada_Quality.Workspaces.Path (Stage) & "/alire/build_hash_inputs"),
                 "staging retains the dependency lock but omits mutable Alire build state");
               Ada_Quality.Workspaces.Prepare (Other_Stage, Root, "safe/test");
               First_Scratch := To_Unbounded_String (Ada_Quality.Workspaces.Scratch_Path (Stage, "marker"));
               Second_Scratch := To_Unbounded_String (Ada_Quality.Workspaces.Scratch_Path (Other_Stage, "marker"));
               Assert (Ada_Quality.Workspaces.Path (Stage) /= Ada_Quality.Workspaces.Path (Other_Stage) and then
                 First_Scratch /= Second_Scratch,
                 "same-identity assessments receive distinct private workspaces");
               Project_Tools.Files.Write_Text_File (To_String (First_Scratch), "first");
               Project_Tools.Files.Write_Text_File (To_String (Second_Scratch), "second");
               declare
                  Permissions : constant Ada_Quality.Execution.Run_Result := Ada_Quality.Execution.Run
                    (Root, "stat",
                     Project_Tools.Processes.Arguments
                       ([Project_Tools.Processes.Argument ("-c"), Project_Tools.Processes.Argument ("%a"),
                         Project_Tools.Processes.Argument
                           (Ada_Quality.Workspaces.Scratch_Path (Stage, "."))]),
                     Timeout_Seconds => 2, Maximum_Bytes => 32);
               begin
                  Assert (Permissions.Status = Ada_Quality.Execution.Completed and then
                    Permissions.Exit_Code = 0 and then
                    Ada.Strings.Fixed.Index (To_String (Permissions.Output), "700") > 0,
                    "assessment workspaces are owner-only; observed=" & To_String (Permissions.Output));
               end;
               Ada_Quality.Workspaces.Cleanup (Stage);
               Assert (Project_Tools.Files.File_Exists (To_String (Second_Scratch)) and then
                 Ada_Quality.Workspaces.Is_Active (Other_Stage),
                 "cleaning one assessment cannot remove another assessment workspace");
               Ada_Quality.Workspaces.Cleanup (Other_Stage);
               Assert (not Project_Tools.Files.Exists (To_String (First_Scratch)) and then
                 not Project_Tools.Files.Exists (To_String (Second_Scratch)),
                 "private workspaces are removed after use");
               Project_Tools.Files.Write_Text_File
                 (Root & "/alire.toml",
                  "name = ""local""" & ASCII.LF & "version = ""0.1.0""" & ASCII.LF &
                  "[[pins]]" & ASCII.LF &
                  "dependency = { path = ""../../../etc"" }" & ASCII.LF);
               Raised := False;
               begin
                  Ada_Quality.Workspaces.Prepare (Stage, Root, "escape-test");
               exception
                  when Ada_Quality.Workspaces.Workspace_Error => Raised := True;
               end;
               Assert (Raised, "staging rejects local pins that escape its isolated container");
               Project_Tools.Files.Delete_Tree (Root);
               Project_Tools.Files.Delete_Tree (Outside);
               Project_Tools.Files.Delete_Tree (Deep_Root);
               for J in 1 .. 129 loop
                  Append (Deep_Path, "/d" & Natural'Image (J));
               end loop;
               Ada.Directories.Create_Path (To_String (Deep_Path));
               Project_Tools.Files.Write_Text_File
                 (To_String (Deep_Path) & "/leaf.adb", "procedure Leaf is begin null; end Leaf;" & ASCII.LF);
               Raised := False;
               begin
                  Before := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Deep_Root));
               exception
                  when Constraint_Error => Raised := True;
               end;
               Assert (Raised, "source inventory rejects trees beyond the configured depth bound");
               Project_Tools.Files.Delete_Tree (Deep_Root);
            end;

         when History_Test =>
            declare
               Baseline : constant Ada_Quality.Storage.History_Item :=
                 (Id => 1, Project_Id => 1, Status => To_Unbounded_String ("completed"),
                  Summary => Null_Unbounded_String, Source_Fingerprint => To_Unbounded_String ("source-a"),
                  Policy_Fingerprint => To_Unbounded_String ("policy"),
                  Toolchain_Fingerprint => To_Unbounded_String ("toolchain"));
               Current : Ada_Quality.Storage.History_Item := Baseline;
               Policy_Changed, Interrupted : Ada_Quality.Storage.History_Item := Baseline;
               Old_Results, New_Results : Ada_Quality.Storage.Detail_Vectors.Vector;
               Old_Measures, New_Measures : Ada_Quality.Storage.Detail_Vectors.Vector;
               Empty, Older, Renamed : Ada_Quality.Storage.Detail_Vectors.Vector;
               Changes : Ada_Quality.History.Regression_Vectors.Vector;
               Runs : Ada_Quality.Storage.History_Vectors.Vector;
               Fingerprint : constant Ada.Strings.Unbounded.Unbounded_String :=
                 To_Unbounded_String ("SRC-01:rule:file:message");

               function Has_Kind (Kind : Ada_Quality.History.Regression_Kind) return Boolean is
                 (for some Change of Changes => Change.Kind = Kind);
            begin
               declare
                  No_Runs : Ada_Quality.Storage.History_Vectors.Vector;
               begin
                  Assert (Ada_Quality.History.Baseline_Id (No_Runs, 1) = 0,
                    "an empty history has no baseline");
               end;
               Current.Id := 2;
               Current.Source_Fingerprint := To_Unbounded_String ("source-b");
               Policy_Changed.Id := 2;
               Policy_Changed.Source_Fingerprint := To_Unbounded_String ("source-b");
               Policy_Changed.Policy_Fingerprint := To_Unbounded_String ("policy-new");
               Interrupted.Policy_Fingerprint := To_Unbounded_String ("policy-old");
               Interrupted.Status := To_Unbounded_String ("interrupted");
               Assert (Ada_Quality.History.Policy_Comparable (Baseline, Policy_Changed),
                 "completed assessments with changed policy and stable toolchain are comparable");
               Assert (not Ada_Quality.History.Policy_Comparable (Interrupted, Policy_Changed),
                 "an interrupted assessment cannot become a clean policy comparison");
               Old_Results.Append
                 (Ada_Quality.Storage.Detail_Info'(Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                   State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("96%")));
               New_Results.Append
                 (Ada_Quality.Storage.Detail_Info'(Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                   State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("92%")));
               Old_Measures.Append
                 (Ada_Quality.Storage.Detail_Info'(Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                   State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String ("9600")));
               New_Measures.Append
                 (Ada_Quality.Storage.Detail_Info'(Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                   State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String ("9200")));
               Runs.Append (Baseline);
               Runs.Append (Current);
               Assert (Ada_Quality.History.Baseline_Id (Runs, 999) = 0,
                 "a missing current assessment has no baseline");
               declare
                  All_Measures : Ada_Quality.Storage.Detail_Vectors.Vector := Old_Measures;
                  Trend : Ada_Quality.History.Trend_Vectors.Vector;
               begin
                  All_Measures.Append_Vector (New_Measures);
                  Trend := Ada_Quality.History.Metric_Trend (Runs, All_Measures, TST_03);
                  Assert (Trend.Length = 2 and then Trend.First_Element.Value = 9_600 and then
                    Trend.Last_Element.Value = 9_200,
                    "metric trends retain compatible typed measurements in run order");
               end;
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (Changes.Length = 1 and then Changes.First_Element.Kind =
                 Ada_Quality.History.Worsened_Metric, "coverage drop above the gate is a metric regression");
               Old_Results.Replace_Element
                 (Old_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-02"),
                     State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("5")));
               New_Results.Replace_Element
                 (New_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-02"),
                     State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("6")));
               Old_Measures.Replace_Element
                 (Old_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-02"),
                     State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String ("5")));
               New_Measures.Replace_Element
                 (New_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-02"),
                     State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String ("6")));
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (not Has_Kind (Ada_Quality.History.Worsened_Metric),
                 "increased test registration evidence is an improvement, not a regression");
               New_Measures.Replace_Element
                 (New_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-02"),
                     State => To_Unbounded_String ("INTEGER_VALUE"), Summary => To_Unbounded_String ("4")));
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (Has_Kind (Ada_Quality.History.Worsened_Metric),
                 "decreased test registration evidence is a metric deterioration");
               Old_Results.Replace_Element
                 (Old_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("96%")));
               New_Results.Replace_Element
                 (New_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("92%")));
               Old_Measures.Replace_Element
                 (Old_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String ("9600")));
               New_Measures.Replace_Element
                 (New_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String ("9200")));
               New_Results.Replace_Element
                 (New_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("87%")));
               New_Measures.Replace_Element
                 (New_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String ("8700")));
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (Has_Kind (Ada_Quality.History.Failed_Gate) and then
                 Has_Kind (Ada_Quality.History.Worsened_Metric),
                 "a coverage fall below policy is both a failed gate and worsened metric");
               Old_Results.Replace_Element
                 (Old_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("88%")));
               Old_Measures.Replace_Element
                 (Old_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String ("8800")));
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (Has_Kind (Ada_Quality.History.Worsened_Metric) and then
                 not Has_Kind (Ada_Quality.History.Failed_Gate),
                 "a metric can deteriorate while the indicator remains in violation");
               Old_Results.Replace_Element
                 (Old_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("succeeded/pass"), Summary => To_Unbounded_String ("96%")));
               Old_Measures.Replace_Element
                 (Old_Measures.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("DECIMAL_VALUE"), Summary => To_Unbounded_String ("9600")));
               New_Results.Replace_Element
                 (New_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                     State => To_Unbounded_String ("blocked/unknown"), Summary => To_Unbounded_String ("missing")));
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (Has_Kind (Ada_Quality.History.Lost_Evidence),
                 "a formerly passing gate becoming blocked loses evidence");
               Current.Policy_Fingerprint := To_Unbounded_String ("new-policy");
               New_Results.Replace_Element
                 (New_Results.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("TST-03"),
                   State => To_Unbounded_String ("succeeded/violation"), Summary => To_Unbounded_String ("87%")));
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (not Changes.Is_Empty and then Changes.First_Element.Kind =
                 Ada_Quality.History.Policy_Induced_Change, "policy changes are classified separately");
               Current.Toolchain_Fingerprint := To_Unbounded_String ("different-toolchain");
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (Changes.Is_Empty, "different toolchains are not compared as quality regressions");
               Current.Toolchain_Fingerprint := Baseline.Toolchain_Fingerprint;
               Current.Status := To_Unbounded_String ("interrupted");
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Old_Results, New_Results, Old_Measures, New_Measures, Empty, Empty);
               Assert (Changes.Is_Empty, "incomplete assessments are not compared as quality regressions");
               Current.Status := To_Unbounded_String ("completed");
               Older.Append
                 (Ada_Quality.Storage.Detail_Info'(Id => 1, Run_Id => 1, Kind => Fingerprint,
                   State => To_Unbounded_String ("HIGH"),
                   Summary => To_Unbounded_String ("finding")));
               Renamed.Append
                 (Ada_Quality.Storage.Detail_Info'
                    (Id => 2, Run_Id => 2, Kind => To_Unbounded_String ("SRC-01:rule:renamed:message"),
                     State => To_Unbounded_String ("HIGH"), Summary => To_Unbounded_String ("finding")));
               Assert
                 (Ada_Quality.History.Classify_Finding
                    (To_Unbounded_String ("SRC-01:rule:renamed:message"), Renamed, Empty, Older, True) =
                    Ada_Quality.History.Reintroduced,
                  "a stable finding returning after absence is reintroduced despite line shifts");
               Older.Replace_Element
                 (Older.First_Index,
                  Ada_Quality.Storage.Detail_Info'
                    (Id => 1, Run_Id => 1, Kind => Fingerprint,
                     State => To_Unbounded_String ("LOW"), Summary => To_Unbounded_String ("finding")));
               Current.Policy_Fingerprint := Baseline.Policy_Fingerprint;
               Changes := Ada_Quality.History.Compare
                 (Baseline, Current, Empty, Empty, Empty, Empty, Older, Renamed);
               Assert (Has_Kind (Ada_Quality.History.Increased_Severity),
                 "severity increases retain identity across a renamed path");
               Assert
                 (Ada_Quality.History.Classify_Finding
                    (Fingerprint, Older, Older, Empty, True) = Ada_Quality.History.Persistent,
                  "a finding present in adjacent completed runs is persistent");
               Assert
                 (Ada_Quality.History.Classify_Finding
                    (Fingerprint, Empty, Older, Empty, True) = Ada_Quality.History.Resolved,
                  "a finding absent from a completed run is resolved");
               Assert
                 (Ada_Quality.History.Classify_Finding
                    (Fingerprint, Empty, Older, Empty, False) = Ada_Quality.History.Unconfirmed,
                  "an incomplete current run cannot confirm resolution");
               Assert
                 (Ada_Quality.History.Classify_Finding
                    (Fingerprint, Empty, Empty, Empty, True) = Ada_Quality.History.Unconfirmed,
                  "an unknown finding identity remains unconfirmed");
               Assert (Ada_Quality.History.Image (Ada_Quality.History.Failed_Gate) = "failed-gate",
                 "regression classifications have stable external images");
               Assert (Ada_Quality.History.Image (Ada_Quality.History.New_Finding) = "new-finding",
                 "finding lifecycle classifications have stable external images");
               declare
                  Missing_Changes : constant Ada_Quality.History.Regression_Vectors.Vector :=
                    Ada_Quality.History.Compare
                      (Baseline, Current, Empty, New_Results, Empty, New_Measures, Empty, Empty);
                  Bad_Measures : Ada_Quality.Storage.Detail_Vectors.Vector := Old_Measures;
               begin
                  Assert (Missing_Changes.Is_Empty, "missing baseline details cannot invent regressions");
                  Bad_Measures.Replace_Element
                    (Bad_Measures.First_Index,
                     Ada_Quality.Storage.Detail_Info'
                       (Id => 1, Run_Id => 1, Kind => To_Unbounded_String ("TST-03"),
                        State => To_Unbounded_String ("DECIMAL_VALUE"),
                        Summary => To_Unbounded_String ("not-a-number")));
                  Changes := Ada_Quality.History.Compare
                    (Baseline, Current, Old_Results, New_Results, Bad_Measures, New_Measures, Empty, Empty);
                  Assert (not Has_Kind (Ada_Quality.History.Worsened_Metric),
                    "malformed historical numeric values cannot become regressions");
               end;
               declare
                  Large_Runs : Ada_Quality.Storage.History_Vectors.Vector;
                  Large_Measures : Ada_Quality.Storage.Detail_Vectors.Vector;
                  Trend : Ada_Quality.History.Trend_Vectors.Vector;
               begin
                  for J in 1 .. 1_000 loop
                     Large_Runs.Append
                       (Ada_Quality.Storage.History_Item'
                          (Id => J, Project_Id => 1, Status => To_Unbounded_String ("completed"),
                           Summary => Null_Unbounded_String,
                           Source_Fingerprint => To_Unbounded_String ("source-" & Natural'Image (J)),
                           Policy_Fingerprint => To_Unbounded_String ("policy"),
                           Toolchain_Fingerprint => To_Unbounded_String ("toolchain")));
                     Large_Measures.Append
                       (Ada_Quality.Storage.Detail_Info'
                          (Id => J, Run_Id => J, Kind => To_Unbounded_String ("TST-03"),
                           State => To_Unbounded_String ("DECIMAL_VALUE"),
                           Summary => To_Unbounded_String (Natural'Image (8_999 + J))));
                  end loop;
                  Trend := Ada_Quality.History.Metric_Trend (Large_Runs, Large_Measures, TST_03);
                  Assert (Trend.Length = 1_000 and then Trend.Last_Element.Run_Id = 1_000,
                    "large compatible histories retain deterministic trend ordering");
               end;
            end;
      end case;
   end Run_Test;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      type Test_Access is access all AUnit.Simple_Test_Cases.Test_Case'Class;
      Result : constant AUnit.Test_Suites.Access_Test_Suite := AUnit.Test_Suites.New_Suite;
   begin
      for Kind in Test_Kind loop
         Result.Add_Test (Test_Access'(new Quality_Test (Kind => Kind)));
      end loop;
      return Result;
   end Suite;
end Ada_Quality_Test_Suite;
