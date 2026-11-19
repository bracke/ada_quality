with Ada.Containers;
with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Streams;
with Ada.Streams.Stream_IO;
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
with Ada_Quality.CI_Formats;
with Ada_Quality.Evaluation;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Checks;
with Ada_Quality.Coverage;
with Ada_Quality.History;
with Ada_Quality.HTML;
with Ada_Quality.Indicators;
with Ada_Quality.JSON;
with Ada_Quality.Policy;
with Ada_Quality.Project_Inventory;
with Ada_Quality.Presentation;
with Ada_Quality.Reporting;
with Ada_Quality.Resource_Limits;
with Ada_Quality.Storage;
with Ada_Quality.Storage.Testing;
with Ada_Quality.Types;
with Ada_Quality.Tools;
with Ada_Quality.Temporary_Directories;
with Ada_Quality.Workspaces;

package body Ada_Quality_Test_Suite is
   use Ada.Strings.Unbounded;
   use AUnit.Assertions;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Execution.Run_Status;
   use type Ada_Quality.Checks.Metadata_Evidence_Status;
   use type Ada_Quality.Checks.Proof_Applicability_Status;
   use type Ada_Quality.Checks.Dependency_Evidence_Status;
   use type Ada_Quality.Checks.Waiver_Status;
   use type Ada_Quality.History.Finding_Lifecycle;
   use type Ada_Quality.History.Comparison_Status;
   use type Ada_Quality.History.Regression_Kind;
   use type Ada_Quality.Indicators.Metric_Direction;
   use type Ada_Quality.Tools.Tool_Id;

   Test_Area : Ada_Quality.Temporary_Directories.Temporary_Directory;

   function Fixture_Root return String is
   begin
      if not Ada_Quality.Temporary_Directories.Is_Active (Test_Area) then
         Ada_Quality.Temporary_Directories.Create (Test_Area, "ada-quality-tests");
      end if;
      return Ada_Quality.Temporary_Directories.Path (Test_Area);
   end Fixture_Root;

   type Test_Kind is
     (Registry_Test, Coverage_Test, Status_Test, Policy_Test, JSON_Test, Storage_Test, Execution_Test,
      Applicability_Test, Source_Analysis_Test, Integrity_Test, Symlink_Test, History_Test,
      Finding_Identity_Test, Artifact_Signing_Test);
   type Quality_Test (Kind : Test_Kind) is new AUnit.Simple_Test_Cases.Test_Case with null record;
   overriding function Name (Item : Quality_Test) return AUnit.Message_String;
   overriding procedure Run_Test (Item : in out Quality_Test);

   overriding function Name (Item : Quality_Test) return AUnit.Message_String is
   begin
      return AUnit.Format (Test_Kind'Image (Item.Kind));
   end Name;

   procedure Run_Registry_Test is separate;
   procedure Run_Coverage_Test is separate;
   procedure Run_Status_Test is separate;
   procedure Run_Policy_Test is separate;
   procedure Run_JSON_Test is separate;
   procedure Run_Storage_Test is separate;
   procedure Run_Execution_Test is separate;
   procedure Run_Applicability_Test is separate;
   procedure Run_Source_Analysis_Test is separate;
   procedure Run_Integrity_Test is separate;
   procedure Run_Symlink_Test is separate;
   procedure Run_History_Test is separate;
   procedure Run_Finding_Identity_Test is separate;
   procedure Run_Artifact_Signing_Test is separate;

   type Test_Runner is access procedure;
   Test_Runners : constant array (Test_Kind) of Test_Runner :=
     [Registry_Test => Run_Registry_Test'Access,
      Coverage_Test => Run_Coverage_Test'Access,
      Status_Test => Run_Status_Test'Access,
      Policy_Test => Run_Policy_Test'Access,
      JSON_Test => Run_JSON_Test'Access,
      Storage_Test => Run_Storage_Test'Access,
      Execution_Test => Run_Execution_Test'Access,
      Applicability_Test => Run_Applicability_Test'Access,
      Source_Analysis_Test => Run_Source_Analysis_Test'Access,
      Integrity_Test => Run_Integrity_Test'Access,
      Symlink_Test => Run_Symlink_Test'Access,
      History_Test => Run_History_Test'Access,
      Finding_Identity_Test => Run_Finding_Identity_Test'Access,
      Artifact_Signing_Test => Run_Artifact_Signing_Test'Access];

   --  AQ-WAIVER: SRC-03 target=run_test owner=aq expires=2099-12-31 justification=aunit-dispatch-table
   overriding procedure Run_Test (Item : in out Quality_Test) is
   begin
      Test_Runners (Item.Kind).all;
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
