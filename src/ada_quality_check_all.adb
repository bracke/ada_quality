with Ada.Command_Line;
with Ada.Containers;
with Ada.Directories;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Project_Tools.Files;
with Project_Tools.Release_Checks;
with Ada_Quality.Indicators;

procedure Ada_Quality_Check_All is
   --  Release-checker entry point for required files, registry cardinality, and AUnit execution.
   use type Ada.Containers.Count_Type;
   type String_Access is access constant String;
   type Document_List is array (Positive range <>) of String_Access;
   Required_Phase_Documents : constant Document_List :=
     [new String'("dependency-matrix.md"), new String'("indicator-implementation-matrix.md"),
      new String'("database-design.md"), new String'("process-execution.md"),
      new String'("coverage-and-proof.md"), new String'("architecture.md"),
      new String'("implementation-plan.md"), new String'("phase-0-verification.md"),
      new String'("domain-model.md"), new String'("indicator-registry.md"),
      new String'("quality-policy.md"), new String'("measurement-semantics.md"),
      new String'("json-contracts.md"), new String'("invariants.md"),
      new String'("phase-1-verification.md"), new String'("database-schema.md"),
      new String'("database-transactions.md"), new String'("database-migrations.md"),
      new String'("project-registry.md"), new String'("persistence-invariants.md"),
      new String'("phase-2-verification.md"), new String'("native-measurement-engine.md"),
      new String'("source-inventory.md"), new String'("source-analysis.md"),
      new String'("native-indicators.md"), new String'("security-scanning.md"),
      new String'("indicator-evidence.md"), new String'("phase-3-verification.md"),
      new String'("external-execution.md"), new String'("process-safety.md"),
      new String'("execution-environment.md"), new String'("workspace-isolation.md"),
      new String'("tool-registry.md"), new String'("build-indicators.md"),
      new String'("test-indicators.md"), new String'("dependency-indicators.md"),
      new String'("documentation-indicators.md"), new String'("phase-4-verification.md"),
      new String'("coverage.md"), new String'("spark-verification.md"),
      new String'("release-verification.md"), new String'("reproducibility.md"),
      new String'("full-assessment.md"), new String'("assessment-compliance.md"),
      new String'("phase-5-verification.md"), new String'("historical-assessments.md"),
      new String'("baseline-selection.md"), new String'("finding-identity.md"),
      new String'("finding-lifecycle.md"), new String'("regression-detection.md"),
      new String'("metric-trends.md"), new String'("recovery.md"),
      new String'("history-invariants.md"), new String'("phase-6-verification.md"),
      new String'("cli-reference.md"), new String'("json-reporting.md"),
      new String'("json-schemas.md"), new String'("end-to-end-testing.md"),
      new String'("assessment-workflows.md"), new String'("error-codes.md"),
      new String'("operational-limits.md"), new String'("phase-7-verification.md")];
   Root  : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Check : constant Project_Tools.Release_Checks.Checker := Project_Tools.Release_Checks.Create (Root);
begin
   if Root'Length = 0 then
      Project_Tools.Release_Checks.Fail ("cannot locate ada_quality project root");
   end if;
   Check.Require_File ("alire.toml");
   Check.Require_File ("ada_quality.gpr");
   Check.Require_File ("quality-policy.toml");
   Check.Require_File ("README.md");
   Check.Require_File ("LICENSE");
   Check.Require_File ("docs/ARCHITECTURE.md");
   Check.Require_File ("docs/DATABASE.md");
   Check.Require_File ("docs/CLI.md");
   Check.Require_File ("docs/ASSESSMENT.md");
   Check.Require_File ("docs/assessment.schema.json");
   Check.Require_File ("docs/archive.schema.json");
   for Name of Required_Phase_Documents loop
      Check.Require_File ("docs/" & Name.all);
   end loop;
   Check.Require_File ("docs/implementation-audit.md");
   Check.Require_File ("docs/requirements-traceability.md");
   Check.Require_File ("docs/indicator-audit.md");
   Check.Require_File ("docs/database-integrity.md");
   Check.Require_File ("docs/fault-injection.md");
   Check.Require_File ("docs/security-review.md");
   Check.Require_File ("docs/reliability-testing.md");
   Check.Require_File ("docs/resource-limits.md");
   Check.Require_File ("docs/release-readiness.md");
   Check.Require_File ("docs/phase-8-verification.md");
   Check.Require_File ("coverage/gcov-summary.txt");
   Check.Require_File ("tests/alire.toml");
   Check.Require_Directory ("src");
   Check.Require_Directory ("tests/src");
   Check.Require_File ("tests/bin/ada_quality_tests");
   if Ada_Quality.Indicators.Count /= 33 then
      Project_Tools.Release_Checks.Fail ("indicator registry must contain exactly 33 entries");
   end if;
   declare
      No_Arguments : GNAT.OS_Lib.Argument_List (1 .. 0);
   begin
      Project_Tools.Release_Checks.Run
        (Label => "AUnit tests", Dir => Root, Program => Root & "/tests/bin/ada_quality_tests",
         Args => No_Arguments);
   end;
   Ada.Text_IO.Put_Line ("ada_quality release structure: OK");
exception
   when Program_Error =>
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Ada_Quality_Check_All;
