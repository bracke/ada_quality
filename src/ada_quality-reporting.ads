with Ada.Calendar;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Ada_Quality.Storage;
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
      Max_Runs     : Positive := 1_000_000;
      Max_Findings : Positive := 2_000_000;
   end record;
   --  Upper bounds on the rows a session loads.
   --  @field Max_Projects Maximum project registry rows.
   --  @field Max_Runs Maximum assessment runs.
   --  @field Max_Findings Maximum finding rows.

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

   type Assessment_Record is record
      Run     : Run_Record;
      Results : Ada_Quality.Types.Result_Vectors.Vector;
   end record;
   --  Fully decoded completed assessment.
   --  @field Run Run metadata.
   --  @field Results Exactly 33 results in indicator registry order, with measurements and findings.

   type History_Evidence is record
      Results      : Ada_Quality.Storage.Detail_Vectors.Vector;
      Measurements : Ada_Quality.Storage.Detail_Vectors.Vector;
      Findings     : Ada_Quality.Storage.Detail_Vectors.Vector;
   end record;
   --  Opaque evidence rows in the shape Ada_Quality.History consumes; consumers pass them through unchanged.
   --  @field Results Indicator result rows.
   --  @field Measurements Measurement rows.
   --  @field Findings Finding rows.

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
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.Storage.History_Vectors.Vector;
   --  Return run metadata in the form Ada_Quality.History consumes.
   --  @param Item Open session.
   --  @param Project_Id Project filter; zero selects every project.
   --  @return History items in ascending identity order.

   function Read_History_Evidence (Item : Session; Run_Id : Positive) return History_Evidence;
   --  Return evidence rows of one completed run for Ada_Quality.History.Compare.
   --  @param Item Open session.
   --  @param Run_Id Completed run identity.
   --  @return Rows in ascending identity order.
   --  @exception Reporting_Error The run does not exist or is not completed.

   function All_Measurements
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.Storage.Detail_Vectors.Vector;
   --  Return measurement rows of completed runs for Ada_Quality.History.Metric_Trend.
   --  @param Item Open session.
   --  @param Project_Id Project filter; zero selects every project.
   --  @return Rows in ascending identity order.

private
   package Run_Index_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Positive);

   type Detail_Group is record
      Results      : Ada_Quality.Storage.Detail_Vectors.Vector;
      Measurements : Ada_Quality.Storage.Detail_Vectors.Vector;
      Findings     : Ada_Quality.Storage.Detail_Vectors.Vector;
   end record;

   package Detail_Maps is new Ada.Containers.Ordered_Maps
     (Key_Type => Positive, Element_Type => Detail_Group);

   type Session is new Ada.Finalization.Limited_Controlled with record
      Opened     : Boolean := False;
      Version    : Positive := Supported_Schema;
      Identity   : UString;
      All_Projects : Project_Vectors.Vector;
      All_Runs   : Run_Vectors.Vector;
      Run_Index  : Run_Index_Maps.Map;
      Payloads   : Ada_Quality.Storage.History_Vectors.Vector;
      Details    : Detail_Maps.Map;
   end record;

   overriding procedure Finalize (Item : in out Session);
   --  Discard the snapshot during finalization.
   --  @param Item Session.
end Ada_Quality.Reporting;
