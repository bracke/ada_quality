with Ada_Quality.Reporting;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Checks;
with Ada_Quality.Types;
with Ada_Quality.Storage;
with Ada_Quality.Policy;
with Ada_Quality.Artifact_Signing;
with Ada_Quality.Command_Models;
with Ada_Quality.Resource_Limits;

--  Deterministic JSON serialization for assessments and persistent archives.
package Ada_Quality.JSON is
   --  Deterministic JSON serialization for assessments and persistent archives.
   function Render (Item : Ada_Quality.Types.Assessment; Pretty : Boolean := False) return String;
   --  Serialize one assessment using the versioned deterministic JSON contract.
   --  @param Item Assessment to serialize.
   --  @param Pretty Whether to indent the resulting document.
   --  @return Complete JSON document.

   function Render_Batch
     (Items : Ada_Quality.Command_Models.Batch_Outcome_Vectors.Vector;
      Pretty : Boolean := False) return String;
   --  Serialize a multi-project run as one versioned JSON document.

   function Render_Reuse
     (Project_Id, Assessment_Id : Positive; Pretty : Boolean := False) return String;
   --  Serialize one exact unchanged-assessment reuse reference.

   function Render_Check_Plan
     (Items : Ada_Quality.Command_Models.Check_Plan_Vectors.Vector;
      Pretty : Boolean := False) return String;
   --  Serialize a no-write assessment execution plan.

   function Render_Archive
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean := False;
      Max_Output_Bytes : Positive :=
        Ada_Quality.Resource_Limits.Maximum_Archive_Output_Bytes;
      Project_Id       : Natural := 0;
      Project_Tag      : String := "";
      Since_Time       : Ada_Quality.Reporting.Optional_Timestamp := (Present => False);
      Until_Time       : Ada_Quality.Reporting.Optional_Timestamp := (Present => False)) return String;
   --  Serialize every persisted project, assessment, detail, and regression.
   --  @param Item Open, bounded, read-only reporting snapshot.
   --  @param Pretty Whether to indent the resulting document.
   --  @param Max_Output_Bytes Maximum serialized archive size.
   --  @return Complete archive JSON document.
   --  @exception Ada_Quality.Reporting.Limit_Error The serialized archive exceeds the output limit.

   function Render_Trend
     (Project_Id : Positive;
      Indicator  : Ada_Quality.Types.Indicator_Id;
      Unit_Name  : String;
      Points     : Ada_Quality.History.Trend_Vectors.Vector;
      Pretty     : Boolean := False) return String;
   --  Serialize one compatible metric series as a versioned JSON document.

   function Render_Trends
     (Project_Id : Positive;
      Series     : Ada_Quality.Command_Models.Metric_Series_Vectors.Vector;
      Pretty     : Boolean := False) return String;
   --  Serialize multiple compatible metric series as metric-trends-v1.

   function Render_History
     (Items : Ada_Quality.Reporting.Run_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;
   --  Serialize a filtered assessment history as assessment-history-v1.

   function Render_Comparison
     (Item : Ada_Quality.Reporting.Project_Comparison;
      Pretty : Boolean := False) return String;
   --  Serialize one selected assessment comparison as assessment-comparison-v1.

   function Render_Status
     (Item : Ada_Quality.Reporting.Session;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;
   --  Serialize the latest portfolio state as portfolio-status-v1.

   function Render_Status
     (Item     : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page     : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty   : Boolean := False) return String;
   --  Serialize the latest portfolio state for a selected project set.

   function Render_Scan
     (Project_Id : Positive;
      Metrics    : Ada_Quality.Checks.Source_Analysis;
      Pretty     : Boolean := False) return String;
   --  Serialize changed-source analysis as changed-source-scan-v1.

   function Render_Findings
     (Items : Ada_Quality.Types.Finding_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;
   --  Serialize a filtered finding collection as findings-v1.

   function Render_Projects
     (Items : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;
   function Render_Discovery
     (Items : Ada_Quality.Command_Models.Discovery_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Aliases
     (Items : Ada_Quality.Reporting.Alias_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;
   function Render_Statistics
     (Item : Ada_Quality.Reporting.Snapshot_Statistics;
      Pretty : Boolean := False) return String;

   function Render_Indicators
     (Filter_Category : Boolean := False;
      Category        : Ada_Quality.Indicators.Indicator_Category := Ada_Quality.Indicators.Structure;
      Pretty          : Boolean := False) return String;
   --  Serialize the complete or category-filtered indicator registry as indicator-catalog-v1.

   function Render_Doctor
     (Items : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Maximum_Failures : Natural := 0;
      Failure_Count : Natural := Natural'Last; Pretty : Boolean := False) return String;
   function Render_Waivers
     (Items : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
      Maximum_Invalid : Natural := 0; Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last; Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String;
   function Render_Doctor_Batch
     (Items : Ada_Quality.Command_Models.Diagnostic_Report_Vectors.Vector;
      Global_Checks : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector :=
        Ada_Quality.Command_Models.Diagnostic_Vectors.Empty_Vector;
      Maximum_Failures : Natural := 0; Pretty : Boolean := False) return String;
   function Render_Waiver_Batch
     (Items : Ada_Quality.Command_Models.Waiver_Report_Vectors.Vector;
      Maximum_Invalid : Natural := 0; Maximum_Expiring : Natural := Natural'Last;
      Invalid_Count : Natural := Natural'Last; Expiring_Count : Natural := Natural'Last;
      Pretty : Boolean := False) return String;
   function Render_Error
     (Code, Message, Command : String; Exit_Status : Natural;
      Pretty : Boolean := False) return String;
   function Render_Command_Result
     (Command, Detail : String; Success : Boolean; Pretty : Boolean := False) return String;
   function Render_String_List
     (Kind, Member : String; Items : Ada_Quality.Command_Models.String_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Policy
     (Item : Ada_Quality.Policy.Quality_Policy; Source : String := "";
      Pretty : Boolean := False) return String;
   function Render_Policy_Diff
     (Left_Name, Right_Name : String; Left, Right : Ada_Quality.Policy.Quality_Policy;
      Pretty : Boolean := False) return String;
   function Render_Policy_Impact
     (Before_Name, After_Name : String;
      Items : Ada_Quality.Command_Models.Policy_Impact_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Comparisons
     (Items : Ada_Quality.Command_Models.Comparison_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Signature
     (Item : Ada_Quality.Artifact_Signing.Signature_Info; Verified : Boolean;
      Pretty : Boolean := False) return String;
   function Render_Trusted_Keys
     (Items : Ada_Quality.Artifact_Signing.Trusted_Key_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Retention
     (Items : Ada_Quality.Storage.History_Vectors.Vector;
      Before : String; Keep : Natural; Pretty : Boolean := False) return String;
   function Render_Merge
     (Sources : Ada_Quality.Storage.Source_Vectors.Vector; Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments, Added_Aliases : Natural;
      Conflicts : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Merge
     (Source : String; Dry_Run : Boolean;
      Added_Projects, Added_Assessments, Reused_Assessments, Added_Aliases : Natural;
      Conflicts : Ada_Quality.Command_Models.Diagnostic_Vectors.Vector;
      Pretty : Boolean := False) return String;
end Ada_Quality.JSON;
