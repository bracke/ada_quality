with Ada.Calendar;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Ada_Quality.History;
with Ada_Quality.History_Data;
with Ada_Quality.Types;

--  Read-only, snapshot-consistent, strongly typed view of persisted assessments for reporting consumers.
--
--  Open takes a shared process lock on an existing database, reads every required table inside one read
--  transaction, validates and decodes the evidence, and releases the database before returning. All queries then
--  operate on that immutable in-memory snapshot. Reporting never creates, migrates, recovers, or modifies a database.
package Ada_Quality.Reporting is
   --  Read-only, snapshot-consistent, strongly typed view of persisted assessments for reporting consumers.
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized reporting text.

   Reporting_Error : exception;
   --  Raised for an invalid request or an open, read, or cleanup failure.
   Schema_Error    : exception;
   --  Raised when the logical schema is missing, incomplete, or not exactly supported.
   Integrity_Error : exception;
   --  Raised for corrupt, incomplete, duplicate, inconsistent, or recovery-pending evidence.
   Busy_Error      : exception;
   --  Raised when another process holds a conflicting database lock.
   Limit_Error     : exception;
   --  Raised when the snapshot exceeds a configured resource limit.

   Supported_Schema : constant Positive := 3;
   --  The only logical schema version a reporting session accepts.

   type Load_Limits is record
      Max_Projects : Positive := 10_000;
      Max_Runs     : Positive := 100_000;
      Max_Results  : Positive := 2_000_000;
      Max_Measurements : Positive := 2_000_000;
      Max_Findings : Positive := 2_000_000;
      Max_Executions : Positive := 2_000_000;
      Max_Events     : Positive := 2_000_000;
      Max_Total_Rows : Positive := 2_500_000;
      Max_Text_Bytes : Positive := 268_435_456;
   end record;
   --  Upper bounds on the rows a session loads.
   --  @field Max_Projects Maximum project registry rows.
   --  @field Max_Runs Maximum assessment runs.
   --  @field Max_Results Maximum indicator-result rows.
   --  @field Max_Measurements Maximum typed-measurement rows.
   --  @field Max_Findings Maximum finding rows.
   --  @field Max_Executions Maximum external-execution rows.
   --  @field Max_Events Maximum lifecycle-event rows.
   --  @field Max_Total_Rows Maximum rows across all tables, including schema metadata.
   --  @field Max_Text_Bytes Maximum aggregate UTF-8 bytes in persisted text fields.

   type Optional_Timestamp (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Ada.Calendar.Time;
         when False =>
            null;
      end case;
   end record;
   --  Persisted UTC timestamp, absent for legacy runs that never recorded one.
   --  @field Present Whether a timestamp was persisted.
   --  @field Value Persisted instant.

   function Image (Item : Optional_Timestamp) return String;
   --  Return an ISO 8601 UTC image.
   --  @param Item Timestamp.
   --  @return Text of the form `YYYY-MM-DDTHH:MM:SSZ`, or an empty string when absent.

   type Evidence_Format is (Legacy_Evidence, Lossless_Evidence);
   --  Encoding of a run's result and finding evidence.
   --  @enum Legacy_Evidence Published before schema 3; findings carry no source location and indicators are
   --  attributed through the stable fingerprint prefix.
   --  @enum Lossless_Evidence Published with explicit, escaped result and finding fields.

   type Run_Record is record
      Id           : Positive;
      Project_Id   : Positive;
      State        : Ada_Quality.Types.Assessment_Status;
      Source_Id    : UString;
      Policy_Id    : UString;
      Toolchain_Id : UString;
      Started_At   : Optional_Timestamp;
      Finished_At  : Optional_Timestamp;
      Format       : Evidence_Format := Legacy_Evidence;
   end record;
   --  Persisted assessment-run metadata.
   --  @field Id Assessment identity.
   --  @field Project_Id Owning project identity.
   --  @field State Lifecycle state.
   --  @field Source_Id Source fingerprint.
   --  @field Policy_Id Policy fingerprint.
   --  @field Toolchain_Id Toolchain fingerprint.
   --  @field Started_At Persisted start time.
   --  @field Finished_At Persisted terminal time.
   --  @field Format Child evidence encoding.

   package Run_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Run_Record);
   --  Runs in ascending identity order.

   type Project_Record is record
      Id      : Positive;
      Path    : UString;
      Enabled : Boolean;
      Removed : Boolean;
   end record;
   --  Persisted project registry entry.
   --  @field Id Project identity.
   --  @field Path Canonical project root.
   --  @field Enabled Whether bulk assessment includes the project.
   --  @field Removed Whether the entry is a tombstone.

   package Project_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Project_Record);
   --  Projects in ascending identity order.

   type Execution_Record is record
      Id            : Positive;
      Run_Id        : Positive;
      Tool          : UString;
      Command       : UString;
      Status        : Ada_Quality.Types.Tool_Run_Status;
      Exit_Code     : Integer;
      Output_Digest : UString;
      Output_Bytes  : Long_Long_Integer;
      Truncated     : Boolean;
   end record;
   --  Decoded external-tool execution evidence.
   --  @field Id Persistent execution-row identity.
   --  @field Run_Id Owning assessment identity.
   --  @field Tool Stable adapter label.
   --  @field Command Redacted executable and argument-shape summary.
   --  @field Status Terminal tool state.
   --  @field Exit_Code Child exit code, or minus one when unavailable.
   --  @field Output_Digest Digest of the complete tool output.
   --  @field Output_Bytes 64-bit complete combined output byte count before truncation.
   --  @field Truncated Whether retained diagnostic output was truncated.

   package Execution_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Execution_Record);
   --  External executions in ascending persistent identity order.

   type Assessment_Record is record
      Run        : Run_Record;
      Results    : Ada_Quality.Types.Result_Vectors.Vector;
      Executions : Execution_Vectors.Vector;
   end record;
   --  Fully decoded completed assessment.
   --  @field Run Run metadata.
   --  @field Results Exactly 33 results in indicator registry order, with measurements and findings.
   --  @field Executions Validated external-tool execution evidence.

   type History_Evidence is record
      Results      : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Findings     : Ada_Quality.History_Data.Detail_Vectors.Vector;
   end record;
   --  Opaque evidence rows in the shape Ada_Quality.History consumes; consumers pass them through unchanged.
   --  @field Results Indicator result rows.
   --  @field Measurements Measurement rows.
   --  @field Findings Finding rows.

   type Project_Comparison is record
      Project_Id : Positive;
      Selection  : Ada_Quality.History.Comparison_Selection;
      Changes    : Ada_Quality.History.Regression_Vectors.Vector;
   end record;
   --  Baseline selection and derived regressions for one project snapshot.

   type Session is new Ada.Finalization.Limited_Controlled with private;
   --  Immutable reporting snapshot.

   procedure Open (Item : in out Session; Path : String; Limits : Load_Limits := (others => <>));
   --  Load one coherent read-only snapshot of an existing database.
   --  @param Item Session to initialize; an open session is closed first.
   --  @param Path Existing database file.
   --  @param Limits Resource limits.
   --  @exception Reporting_Error Path is empty, missing, not a regular file, or unreadable.
   --  @exception Busy_Error A writer holds the database lock.
   --  @exception Schema_Error The schema is missing, incomplete, or not version 3.
   --  @exception Integrity_Error Evidence is corrupt or the database requires recovery.
   --  @exception Limit_Error A load limit is exceeded.

   procedure Close (Item : in out Session);
   --  Discard the snapshot; closed sessions are accepted.
   --  @param Item Session.

   function Is_Open (Item : Session) return Boolean;
   --  Test whether a snapshot is loaded.
   --  @param Item Session.
   --  @return True after a successful Open.

   function Projects (Item : Session; Include_Removed : Boolean := False) return Project_Vectors.Vector;
   --  Return registry entries in ascending identity order.
   --  @param Item Open session.
   --  @param Include_Removed Whether tombstones are included.
   --  @return Projects, including disabled ones.

   function Project (Item : Session; Project_Id : Positive) return Project_Record;
   --  Return one project, including a removed registry entry.
   --  @param Item Open session.
   --  @param Project_Id Persistent project identity.
   --  @return Matching project record.
   --  @exception Reporting_Error No matching project exists.

   function Runs (Item : Session; Project_Id : Natural := 0) return Run_Vectors.Vector;
   --  Return all run metadata in ascending identity order.
   --  @param Item Open session.
   --  @param Project_Id Project filter; zero selects every project.
   --  @return Runs in every lifecycle state.

   function Read_Assessment (Item : Session; Run_Id : Positive) return Assessment_Record;
   --  Return a fully decoded completed assessment.
   --  @param Item Open session.
   --  @param Run_Id Completed run identity.
   --  @return Assessment with 33 results.
   --  @exception Reporting_Error The run does not exist or is not completed.

   function Supported_Schema_Version (Item : Session) return Positive;
   --  Return the validated schema version of the snapshot.
   --  @param Item Open session.
   --  @return Persisted logical schema version.

   function Snapshot_Identity (Item : Session) return String;
   --  Return a deterministic digest of every loaded row.
   --  @param Item Open session.
   --  @return Text of the form `fnv1a64:` followed by sixteen lowercase hexadecimal digits.

   function History_Items
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.History_Data.History_Vectors.Vector;
   --  Return run metadata in the form Ada_Quality.History consumes.
   --  @param Item Open session.
   --  @param Project_Id Project filter; zero selects every project.
   --  @return History items in ascending identity order.

   function Compare_Project (Item : Session; Project_Id : Positive) return Project_Comparison;
   --  Select and compare the latest project assessments using validated snapshot evidence.
   --  @param Item Open session.
   --  @param Project_Id Project whose latest comparable assessments are selected.
   --  @return Selection status and deterministically ordered regressions.

   function Compare_Project
     (Item : Session; Project_Id : Positive; Current_Id : Positive) return Project_Comparison;
   --  As Compare_Project, for the project history through Current_Id: the comparison a report makes for a chosen
   --  current assessment, such as the latest completed one while a newer run has not finished.
   --  @param Item Open session.
   --  @param Project_Id Project.
   --  @param Current_Id Assessment that plays the current role; later runs are ignored.
   --  @return Selection status and deterministically ordered regressions.

   function Select_Project_Comparison
     (Item : Session; Project_Id : Positive) return Ada_Quality.History.Comparison_Selection;
   --  Select the latest comparable assessments without deriving regressions.
   --  @param Item Open session.
   --  @param Project_Id Project whose latest assessments are selected.
   --  @return Typed comparison availability and selected assessment identities.

   function Read_History_Evidence (Item : Session; Run_Id : Positive) return History_Evidence;
   --  Return evidence rows of one completed run for Ada_Quality.History.Compare.
   --  @param Item Open session.
   --  @param Run_Id Completed run identity.
   --  @return Rows in ascending identity order.
   --  @exception Reporting_Error The run does not exist or is not completed.

   function All_Measurements
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return measurement rows of completed runs for Ada_Quality.History.Metric_Trend.
   --  @param Item Open session.
   --  @param Project_Id Project filter; zero selects every project.
   --  @return Rows in ascending identity order.

   function All_Persisted_Measurements
     (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return all validated measurement rows, including evidence from invalid terminal runs.
   --  @param Item Open session.
   --  @return Rows in ascending assessment and row identity order.

   function All_Results (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return all validated indicator-result rows in ascending identity order.
   --  @param Item Open session.
   --  @return Structurally validated rows from terminal assessments.

   function All_Findings (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return all validated finding rows in ascending identity order.
   --  @param Item Open session.
   --  @return Structurally validated rows from terminal assessments.

   function All_Executions (Item : Session) return Execution_Vectors.Vector;
   --  Return all external-execution rows in ascending identity order.
   --  @param Item Open session.
   --  @return Structurally validated execution rows.

   function All_Events (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return all lifecycle-event rows in ascending identity order.
   --  @param Item Open session.
   --  @return Structurally validated lifecycle rows.

   function Results
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return validated indicator-result rows for one run.
   --  @param Item Open session.
   --  @param Run_Id Assessment identity.
   --  @return Rows owned by the selected run.

   function Measurements
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return validated measurement rows for one run.
   --  @param Item Open session.
   --  @param Run_Id Assessment identity.
   --  @return Rows owned by the selected run.

   function Findings
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return validated finding rows for one run.
   --  @param Item Open session.
   --  @param Run_Id Assessment identity.
   --  @return Rows owned by the selected run.

   function Executions
     (Item : Session; Run_Id : Positive) return Execution_Vectors.Vector;
   --  Return validated external-execution rows for one run.
   --  @param Item Open session.
   --  @param Run_Id Assessment identity.
   --  @return Rows owned by the selected run.

   function Events
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector;
   --  Return validated lifecycle-event rows for one run.
   --  @param Item Open session.
   --  @param Run_Id Assessment identity.
   --  @return Rows owned by the selected run.

   type Detail_Collection is
     (Result_Details, Measurement_Details, Finding_Details, Event_Details);
   --  Raw detail collection selected for allocation-free internal streaming.

   procedure Visit_Details
     (Item    : Session;
      Run_Id  : Positive;
      Kind    : Detail_Collection;
      Process : not null access procedure (Row : Ada_Quality.History_Data.Detail_Info));
   --  Visit one detail collection without constructing a returned vector copy.
   --  @param Item Open session.
   --  @param Run_Id Assessment identity.
   --  @param Kind Detail collection to visit.
   --  @param Process Callback invoked once per row in persistent identity order.

   procedure Visit_Executions
     (Item    : Session;
      Run_Id  : Positive;
      Process : not null access procedure (Row : Execution_Record));
   --  Visit execution records without constructing a returned vector copy.
   --  @param Item Open session.
   --  @param Run_Id Assessment identity.
   --  @param Process Callback invoked once per execution in persistent identity order.

private
   type Indicator_Boolean_Array is array (Ada_Quality.Types.Indicator_Id) of Boolean;

   package Run_Index_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Positive);

   type Detail_Group is record
      Results      : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Findings     : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Executions   : Execution_Vectors.Vector;
      Events       : Ada_Quality.History_Data.Detail_Vectors.Vector;
      Has_Result_State : Indicator_Boolean_Array := [others => False];
      Result_Succeeded : Indicator_Boolean_Array := [others => False];
   end record;

   package Detail_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Detail_Group);

   package History_Position_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Positive);

   package Project_History_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type     => Positive,
      Element_Type => History_Position_Vectors.Vector,
      "="          => History_Position_Vectors."=");

   type Session is new Ada.Finalization.Limited_Controlled with record
      Opened     : Boolean := False;
      Version    : Positive := Supported_Schema;
      Identity   : UString;
      All_Projects : Project_Vectors.Vector;
      All_Runs   : Run_Vectors.Vector;
      Run_Index  : Run_Index_Maps.Map;
      Payloads   : Ada_Quality.History_Data.History_Vectors.Vector;
      Project_Histories : Project_History_Maps.Map;
      Details    : Detail_Maps.Map;
   end record;

   overriding procedure Finalize (Item : in out Session);
   --  Discard the snapshot during finalization.
   --  @param Item Session.
end Ada_Quality.Reporting;
