with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.Reporting;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Checks;
with Ada_Quality.Types;

--  Deterministic JSON serialization for assessments and persistent archives.
package Ada_Quality.JSON is
   --  Deterministic JSON serialization for assessments and persistent archives.
   function Render (Item : Ada_Quality.Types.Assessment; Pretty : Boolean := False) return String;
   --  Serialize one assessment using the versioned deterministic JSON contract.
   --  @param Item Assessment to serialize.
   --  @param Pretty Whether to indent the resulting document.
   --  @return Complete JSON document.

   type Batch_Outcome_Status is (Batch_Completed, Batch_Reused, Batch_Interrupted);
   --  Terminal outcome of one project in a multi-project assessment.

   type Batch_Outcome is record
      Project_Id    : Natural := 0;
      Assessment_Id : Natural := 0;
      Status        : Batch_Outcome_Status := Batch_Interrupted;
      Diagnostic    : Ada.Strings.Unbounded.Unbounded_String;
      Value         : Ada_Quality.Types.Assessment;
   end record;
   --  One completed assessment or interrupted project-local outcome.

   package Batch_Outcome_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Batch_Outcome);

   function Render_Batch
     (Items : Batch_Outcome_Vectors.Vector; Pretty : Boolean := False) return String;
   --  Serialize a multi-project run as one versioned JSON document.

   function Render_Reuse
     (Project_Id, Assessment_Id : Positive; Pretty : Boolean := False) return String;
   --  Serialize one exact unchanged-assessment reuse reference.

   type Check_Plan_Item is record
      Project_Id : Positive;
      Path       : Ada.Strings.Unbounded.Unbounded_String;
      Source_Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
      Reusable_Assessment   : Natural := 0;
      Will_Reuse            : Boolean := False;
   end record;
   package Check_Plan_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Check_Plan_Item);

   function Render_Check_Plan
     (Items : Check_Plan_Vectors.Vector; Pretty : Boolean := False) return String;
   --  Serialize a no-write assessment execution plan.

   function Render_Archive
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean := False;
      Max_Output_Bytes : Positive := 268_435_456;
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

   type Metric_Series is record
      Indicator : Ada_Quality.Types.Indicator_Id := Ada_Quality.Types.STR_01;
      Unit_Name : Ada.Strings.Unbounded.Unbounded_String;
      Points    : Ada_Quality.History.Trend_Vectors.Vector;
   end record;
   --  One named numeric series for multi-metric export.

   package Metric_Series_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Metric_Series);

   function Render_Trends
     (Project_Id : Positive;
      Series     : Metric_Series_Vectors.Vector;
      Pretty     : Boolean := False) return String;
   --  Serialize multiple compatible metric series as metric-trends-v1.

   function Render_History
     (Items : Ada_Quality.Reporting.Run_Vectors.Vector;
      Pretty : Boolean := False) return String;
   --  Serialize a filtered assessment history as assessment-history-v1.

   function Render_Comparison
     (Item : Ada_Quality.Reporting.Project_Comparison;
      Pretty : Boolean := False) return String;
   --  Serialize one selected assessment comparison as assessment-comparison-v1.

   function Render_Status
     (Item : Ada_Quality.Reporting.Session; Pretty : Boolean := False) return String;
   --  Serialize the latest portfolio state as portfolio-status-v1.

   function Render_Status
     (Item     : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
      Pretty   : Boolean := False) return String;
   --  Serialize the latest portfolio state for a selected project set.

   function Render_Scan
     (Project_Id : Positive;
      Metrics    : Ada_Quality.Checks.Source_Analysis;
      Pretty     : Boolean := False) return String;
   --  Serialize changed-source analysis as changed-source-scan-v1.

   function Render_Findings
     (Items : Ada_Quality.Types.Finding_Vectors.Vector;
      Pretty : Boolean := False) return String;
   --  Serialize a filtered finding collection as findings-v1.

   type Discovery_Status is (Already_Registered, Discovered, Added, Missing, Removed);
   type Discovery_Item is record
      Path       : Ada.Strings.Unbounded.Unbounded_String;
      Project_Id : Natural := 0;
      Status     : Discovery_Status := Discovered;
   end record;
   package Discovery_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Discovery_Item);

   function Render_Projects
     (Items : Ada_Quality.Reporting.Project_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Discovery
     (Items : Discovery_Vectors.Vector; Pretty : Boolean := False) return String;
   function Render_Aliases
     (Items : Ada_Quality.Reporting.Alias_Vectors.Vector;
      Pretty : Boolean := False) return String;
   function Render_Statistics
     (Item : Ada_Quality.Reporting.Snapshot_Statistics;
      Pretty : Boolean := False) return String;

   function Render_Indicators
     (Filter_Category : Boolean := False;
      Category        : Ada_Quality.Indicators.Indicator_Category := Ada_Quality.Indicators.Structure;
      Pretty          : Boolean := False) return String;
   --  Serialize the complete or category-filtered indicator registry as indicator-catalog-v1.
end Ada_Quality.JSON;
