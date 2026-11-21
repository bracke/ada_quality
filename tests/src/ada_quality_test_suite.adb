with Ada.Containers;
with Ada.Containers.Vectors;
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
with Terminal_Styles;
with Ada_Quality.Execution;
with Ada_Quality.Artifact_Signing;
with Ada_Quality.Bounded_Files;
with Ada_Quality.CI_Formats;
with Ada_Quality.Evaluation;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Checks;
with Ada_Quality.CLI;
with Ada_Quality.CLI_Arguments;
with Ada_Quality.CLI_Changed_Files;
with Ada_Quality.CLI_Cursors;
with Ada_Quality.CLI_Metadata;
with Ada_Quality.CLI_Pagination;
with Ada_Quality.Command_Models;
with Ada_Quality.Coverage;
with Ada_Quality.History;
with Ada_Quality.HTML;
with Ada_Quality.Indicators;
with Ada_Quality.JSON;
with Ada_Quality.JSON_Administration;
with Ada_Quality.JSON_Assessments;
with Ada_Quality.JSON_Reports;
with Ada_Quality.Pagination;
with Ada_Quality.Policy;
with Ada_Quality.Project_Inventory;
with Ada_Quality.Presentation;
with Ada_Quality.Reporting;
with Ada_Quality.Resource_Limits;
with Ada_Quality.Schema_Catalog;
with Ada_Quality.Storage;
with Ada_Quality.Storage.Assessments;
with Ada_Quality.Storage.Integrity;
with Ada_Quality.Storage.Registry;
with Ada_Quality.Storage.Testing;
with Ada_Quality.Storage.Transfer;
with Ada_Quality.Types;
with Ada_Quality.Tools;
with Ada_Quality.Temporary_Directories;
with Ada_Quality.Workspaces;
with Ada_Quality_JSON_Contract_Testing;

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
   use type Ada_Quality.Pagination.Page_Direction;
   use type Ada_Quality.Tools.Tool_Id;
   use type Ada_Quality.CLI_Metadata.Option_Kind;
   use type Ada_Quality.CLI_Metadata.Command_Id;
   use type Ada_Quality.CLI_Metadata.Subcommand_Id;
   use type Ada_Quality.Reporting.Evidence_Format;
   use type Terminal_Styles.Color_Policy;

   Test_Area : Ada_Quality.Temporary_Directories.Temporary_Directory;

   function Fixture_Root return String is
   begin
      if not Ada_Quality.Temporary_Directories.Is_Active (Test_Area) then
         Ada_Quality.Temporary_Directories.Create (Test_Area, "ada-quality-tests");
      end if;
      return Ada_Quality.Temporary_Directories.Path (Test_Area);
   end Fixture_Root;

   procedure Assert_JSON_Contract
     (Instance, Schema_Name, Label : String)
   is
      Root : constant String :=
        Project_Tools.Files.Find_Root_Upward
          (Ada.Directories.Current_Directory, "ada_quality.gpr");
      Diagnostic : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Assert
        (Ada_Quality_JSON_Contract_Testing.Conforms
           (Instance,
            Project_Tools.Files.Read_Raw_File (Root & "/docs/" & Schema_Name),
            Diagnostic, Schema_Directory => Root & "/docs"),
         Label & ": " & To_String (Diagnostic));
   end Assert_JSON_Contract;

   type Test_Kind is
     (Registry_Test, Coverage_Test, Status_Test, Policy_Test, JSON_Test,
      JSON_Administrative_Test, JSON_Schema_Test,
      Storage_Test, Storage_Transfer_Test, Storage_Merge_Test, Execution_Test,
      Applicability_Test, Source_Analysis_Test, Integrity_Test, Symlink_Test,
      History_Selection_Test, History_Trend_Test, History_Test,
      Finding_Identity_Test, Pagination_Test, Cursor_Test,
      Artifact_Staging_Test, Artifact_Signing_Test);
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
   procedure Run_JSON_Administrative_Test is separate;
   procedure Run_JSON_Schema_Test is separate;
   procedure Run_Storage_Test is separate;
   procedure Run_Storage_Transfer_Test is separate;
   procedure Run_Storage_Merge_Test is separate;
   procedure Run_Execution_Test is separate;
   procedure Run_Applicability_Test is separate;
   procedure Run_Source_Analysis_Test is separate;
   procedure Run_Integrity_Test is separate;
   procedure Run_Symlink_Test is separate;
   procedure Run_History_Test is separate;
   procedure Run_History_Selection_Test is separate;
   procedure Run_History_Trend_Test is separate;
   procedure Run_Finding_Identity_Test is separate;
   procedure Run_Pagination_Test is separate;
   procedure Run_Cursor_Test is separate;
   procedure Run_Artifact_Staging_Test is separate;
   procedure Run_Artifact_Signing_Test is separate;

   type Test_Runner is access procedure;
   Test_Runners : constant array (Test_Kind) of Test_Runner :=
     [Registry_Test => Run_Registry_Test'Access,
      Coverage_Test => Run_Coverage_Test'Access,
      Status_Test => Run_Status_Test'Access,
      Policy_Test => Run_Policy_Test'Access,
      JSON_Test => Run_JSON_Test'Access,
      JSON_Administrative_Test => Run_JSON_Administrative_Test'Access,
      JSON_Schema_Test => Run_JSON_Schema_Test'Access,
      Storage_Test => Run_Storage_Test'Access,
      Storage_Transfer_Test => Run_Storage_Transfer_Test'Access,
      Storage_Merge_Test => Run_Storage_Merge_Test'Access,
      Execution_Test => Run_Execution_Test'Access,
      Applicability_Test => Run_Applicability_Test'Access,
      Source_Analysis_Test => Run_Source_Analysis_Test'Access,
      Integrity_Test => Run_Integrity_Test'Access,
      Symlink_Test => Run_Symlink_Test'Access,
      History_Selection_Test => Run_History_Selection_Test'Access,
      History_Trend_Test => Run_History_Trend_Test'Access,
      History_Test => Run_History_Test'Access,
      Finding_Identity_Test => Run_Finding_Identity_Test'Access,
      Pagination_Test => Run_Pagination_Test'Access,
      Cursor_Test => Run_Cursor_Test'Access,
      Artifact_Staging_Test => Run_Artifact_Staging_Test'Access,
      Artifact_Signing_Test => Run_Artifact_Signing_Test'Access];

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
