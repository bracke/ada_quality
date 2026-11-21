with Ada_Quality.JSON_Administration;
with Ada_Quality.JSON_Assessments;
with Ada_Quality.JSON_Reports;

package body Ada_Quality.JSON is
   function Render
     (Item : Ada_Quality.Types.Assessment; Pretty : Boolean := False)
      return String renames Ada_Quality.JSON_Assessments.Render;
   function Render_Batch
     (Items : Ada_Quality.Command_Models.Batch_Outcome_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Assessments.Render_Batch;
   function Render_Reuse
     (Project_Id, Assessment_Id : Positive; Pretty : Boolean := False)
      return String renames Ada_Quality.JSON_Assessments.Render_Reuse;
   function Render_Check_Plan
     (Items : Ada_Quality.Command_Models.Check_Plan_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Assessments.Render_Check_Plan;
   function Render_Comparison
     (Item : Ada_Quality.Reporting.Project_Comparison;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Assessments.Render_Comparison;
   function Render_Aliases
     (Items : Ada_Quality.Reporting.Alias_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Assessments.Render_Aliases;

   function Render_Archive
     (Item : Ada_Quality.Reporting.Session;
      Pretty : Boolean := False;
      Max_Output_Bytes : Positive :=
        Ada_Quality.Resource_Limits.Maximum_Archive_Output_Bytes;
      Project_Id : Natural := 0;
      Project_Tag : String := "";
      Since_Time : Ada_Quality.Reporting.Optional_Timestamp :=
        (Present => False);
      Until_Time : Ada_Quality.Reporting.Optional_Timestamp :=
        (Present => False)) return String
      renames Ada_Quality.JSON_Reports.Render_Archive;
   function Render_Trend
     (Project_Id : Positive;
      Indicator : Ada_Quality.Types.Indicator_Id;
      Unit_Name : String;
      Points : Ada_Quality.History.Trend_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Trend;
   function Render_Trends
     (Project_Id : Positive;
      Series : Ada_Quality.Command_Models.Metric_Series_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Trends;
   function Render_History
     (Items : Ada_Quality.Reporting.Run_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_History;
   function Render_Status
     (Item : Ada_Quality.Reporting.Session;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Status;
   function Render_Status
     (Item : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Status;
   function Render_Scan
     (Project_Id : Positive;
      Metrics : Ada_Quality.Checks.Source_Analysis;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Scan;
   function Render_Findings
     (Items : Ada_Quality.Types.Finding_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Findings;
   function Render_Projects
     (Items : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Projects;
   function Render_Discovery
     (Items : Ada_Quality.Command_Models.Discovery_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Discovery;
   function Render_Statistics
     (Item : Ada_Quality.Reporting.Snapshot_Statistics;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Statistics;
   function Render_Indicators
     (Filter_Category : Boolean := False;
      Category : Ada_Quality.Indicators.Indicator_Category :=
        Ada_Quality.Indicators.Structure;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Indicators;
   function Render_Comparisons
     (Items : Ada_Quality.Command_Models.Comparison_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Reports.Render_Comparisons;

   function Render_Doctor
     (Items : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Maximum_Failures : Natural := 0;
      Failure_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Doctor;
   function Render_Waivers
     (Items : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
      Maximum_Invalid : Natural := 0;
      Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last;
      Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Waivers;
   function Render_Doctor_Batch
     (Items : Ada_Quality.Command_Models.Diagnostic_Report_Vectors.Vector;
      Global_Checks : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector :=
        Ada_Quality.Command_Models.Diagnostic_Vectors.Empty_Vector;
      Maximum_Failures : Natural := 0;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Doctor_Batch;
   function Render_Waiver_Batch
     (Items : Ada_Quality.Command_Models.Waiver_Report_Vectors.Vector;
      Maximum_Invalid : Natural := 0;
      Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last;
      Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Waiver_Batch;
   function Render_Error
     (Code, Message, Command : String;
      Exit_Status : Natural;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Error;
   function Render_Command_Result
     (Command, Detail : String;
      Success : Boolean;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Command_Result;
   function Render_String_List
     (Kind, Member : String;
      Items : Ada_Quality.Command_Models.String_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_String_List;
   function Render_Policy
     (Item : Ada_Quality.Policy.Quality_Policy;
      Source : String := "";
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Policy;
   function Render_Policy_Diff
     (Left_Name, Right_Name : String;
      Left, Right : Ada_Quality.Policy.Quality_Policy;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Policy_Diff;
   function Render_Policy_Impact
     (Before_Name, After_Name : String;
      Items : Ada_Quality.Command_Models.Policy_Impact_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Policy_Impact;
   function Render_Signature
     (Item : Ada_Quality.Artifact_Signing.Signature_Info;
      Verified : Boolean;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Signature;
   function Render_Trusted_Keys
     (Items : Ada_Quality.Artifact_Signing.Trusted_Key_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Trusted_Keys;
   function Render_Retention
     (Items : Ada_Quality.Storage.History_Vectors.Vector;
      Before : String;
      Keep : Natural;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Retention;
   function Render_Merge
     (Sources : Ada_Quality.Storage.Source_Vectors.Vector;
      Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments,
      Added_Aliases : Natural;
      Conflicts : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Merge;
   function Render_Merge
     (Source : String;
      Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments,
      Added_Aliases : Natural;
      Conflicts : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String
      renames Ada_Quality.JSON_Administration.Render_Merge;
end Ada_Quality.JSON;
