with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Ada_Quality.History_Data;
with Ada_Quality.Types;
with Database;
with Database.Schema;

--  Transactional project registry and immutable assessment persistence.
package Ada_Quality.Storage is
   --  Transactional project registry and immutable assessment persistence.
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized persistent text.

   Storage_Error : exception;
   --  Raised when persistence, integrity, locking, or lifecycle validation fails.

   type Project_Info is record
      Id      : Positive;
      Path    : Unbounded_String;
      Enabled : Boolean := True;
      Removed : Boolean := False;
   end record;
   --  Persistent project registry row.
   --  @field Id Positive project identity.
   --  @field Path Canonical project root.
   --  @field Enabled Whether bulk assessment includes the project.
   --  @field Removed Whether the registry row is a retained tombstone.

   package Project_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Project_Info);
   --  Ordered project registry collection.

   subtype History_Item is Ada_Quality.History_Data.History_Item;
   --  Compatibility alias for persistence-neutral assessment metadata.
   package History_Vectors renames Ada_Quality.History_Data.History_Vectors;
   --  Compatibility alias for ordered assessment metadata.
   subtype Detail_Info is Ada_Quality.History_Data.Detail_Info;
   --  Compatibility alias for persistence-neutral detail rows.
   package Detail_Vectors renames Ada_Quality.History_Data.Detail_Vectors;
   --  Compatibility alias for ordered detail rows.

   type Store is new Ada.Finalization.Limited_Controlled with private;
   --  Exclusive persistent database handle with automatic close and lock release.

   procedure Open (Item : in out Store; Path : String; Create_If_Missing : Boolean := True);
   --  Open, lock, create, or migrate a store and validate its schema metadata.
   --  @param Item Store handle to initialize.
   --  @param Path Database file path.
   --  @param Create_If_Missing Whether a missing database may be created.

   procedure Close (Item : in out Store);
   --  Close a store and release its persistent lock.
   --  @param Item Store handle to close; closed handles are accepted.

   function Is_Open (Item : Store) return Boolean;
   --  Test whether a store is open.
   --  @param Item Store handle to inspect.
   --  @return True while the database handle is open.

   function Add_Project (Item : in out Store; Path : String) return Positive;
   --  Register one existing nonsymlink Alire crate by canonical path.
   --  @param Item Open store.
   --  @param Path Project root to validate and register.
   --  @return New project identity.

   function Projects (Item : in out Store; Include_Removed : Boolean := False) return Project_Vectors.Vector;
   --  Load project registry rows in deterministic identity order.
   --  @param Item Open store.
   --  @param Include_Removed Whether tombstoned rows are included.
   --  @return Matching project rows.

   function Project (Item : in out Store; Id : Positive) return Project_Info;
   --  Load one project registry row.
   --  @param Item Open store.
   --  @param Id Project identity.
   --  @return Matching project row.

   procedure Set_Enabled (Item : in out Store; Id : Positive; Enabled : Boolean);
   --  Change whether a registered project participates in bulk assessment.
   --  @param Item Open store.
   --  @param Id Project identity.
   --  @param Enabled New enabled state.

   procedure Remove_Project (Item : in out Store; Id : Positive);
   --  Tombstone a project while retaining immutable assessment history.
   --  @param Item Open store.
   --  @param Id Project identity.

   procedure Relocate_Project (Item : in out Store; Id : Positive; Path : String);
   --  Change a registered project's root without changing its identity or history.
   --  The replacement path is validated with the same rules as a newly added project.
   --  @param Item Open store.
   --  @param Id Project identity.
   --  @param Path New project root.

   procedure Backup (Item : in out Store; Destination : String);
   --  Create and verify a physical backup directory for the open store.
   --  @param Item Open store.
   --  @param Destination New backup directory.

   procedure Export (Item : in out Store; Destination : String);
   --  Create and verify a database-native logical export file.
   --  @param Item Open store.
   --  @param Destination New logical export file.

   procedure Restore (Source, Destination : String);
   --  Restore and verify a physical backup into a new database file.
   --  @param Source Existing physical backup directory.
   --  @param Destination New database file.

   procedure Import (Source, Destination : String);
   --  Import a database-native logical export into a new database file.

   procedure Archive_And_Prune
     (Item        : in out Store;
      Destination : String;
      Before      : Ada.Calendar.Time;
      Keep        : Natural;
      Removed     : out Natural);
   --  Verify a full logical archive, then transactionally remove old terminal assessments.

   procedure Compact (Item : in out Store);
   --  Reclaim unused database pages inside one exclusive transaction.
   --  @param Item Open store.

   function Start_Assessment
     (Item               : in out Store;
      Project_Id         : Positive;
      Source_Fingerprint : String;
      Policy_Fingerprint : String) return Positive;
   --  Atomically create a running assessment and its start event before external tools run.
   --  @param Item Open store.
   --  @param Project_Id Owning project identity.
   --  @param Source_Fingerprint Initial source identity.
   --  @param Policy_Fingerprint Applied policy identity.
   --  @return New assessment identity.

   function Publish (Item : in out Store; Value : Ada_Quality.Types.Assessment) return Positive;
   --  Validate and atomically publish all terminal assessment evidence.
   --  @param Item Open store.
   --  @param Value Complete publishable assessment.
   --  @return Published assessment identity.

   function History (Item : in out Store; Project_Id : Natural := 0) return History_Vectors.Vector;
   --  Load immutable assessment metadata.
   --  @param Item Open store.
   --  @param Project_Id Optional project filter; zero selects every project.
   --  @return Matching history in deterministic order.

   function Results (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector;
   --  Load persisted indicator result rows.
   --  @param Item Open store.
   --  @param Run_Id Optional assessment filter; zero selects every assessment.
   --  @return Matching result rows.

   function Measurements (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector;
   --  Load persisted typed measurement rows.
   --  @param Item Open store.
   --  @param Run_Id Optional assessment filter; zero selects every assessment.
   --  @return Matching measurement rows.

   function Findings (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector;
   --  Load persisted finding rows.
   --  @param Item Open store.
   --  @param Run_Id Optional assessment filter; zero selects every assessment.
   --  @return Matching finding rows.

   function Executions (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector;
   --  Load persisted external-execution rows.
   --  @param Item Open store.
   --  @param Run_Id Optional assessment filter; zero selects every assessment.
   --  @return Matching execution rows.

   function Events (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector;
   --  Load persisted assessment lifecycle events.
   --  @param Item Open store.
   --  @param Run_Id Optional assessment filter; zero selects every assessment.
   --  @return Matching event rows.

   procedure Add_Assessment_Alias (Item : in out Store; Run_Id : Positive; Name : String);
   --  Assign one globally unique, append-only alias to a completed assessment.
   --  @param Item Open store.
   --  @param Run_Id Completed assessment identity.
   --  @param Name Canonical lowercase alias.

   procedure Interrupt_Assessment (Item : in out Store; Run_Id : Positive; Reason : String);
   --  Atomically mark a running assessment interrupted and record its reason.
   --  @param Item Open store.
   --  @param Run_Id Running assessment identity.
   --  @param Reason Human-readable interruption reason.

   procedure Recover (Item : in out Store; Count : out Natural);
   --  Atomically interrupt every stale running assessment.
   --  @param Item Open store.
   --  @param Count Number of assessments recovered.

   function Schema_Version (Item : in out Store) return Positive;
   --  Read the persisted logical schema version.
   --  @param Item Open store.
   --  @return Supported positive schema version.

   type Integrity_Limits is record
      Max_Total_Rows : Positive := 2_500_000;
      Max_Text_Bytes : Positive := 268_435_456;
   end record;
   --  Resource bounds for a full database integrity audit.
   --  @field Max_Total_Rows Maximum rows across all logical tables.
   --  @field Max_Text_Bytes Maximum aggregate UTF-8 bytes in persisted text fields.

   procedure Check (Item : in out Store; Limits : Integrity_Limits := (others => <>));
   --  Validate schema, row ownership, lifecycle, cardinality, and immutable evidence invariants.
   --  @param Item Open store to check.
   --  @param Limits Resource bounds applied before rows enter the audit snapshot.

private
   type Testing_Fault_Point is
     (No_Testing_Fault, Schema_Creation_Commit, Schema_Migration_Commit,
      Assessment_Start_Commit, Assessment_Publication_Commit,
      Assessment_Interruption_Commit, Assessment_Recovery_Commit);
   --  Internal transaction boundary selected by the explicit test child.

   type Testing_Corruption is
     (Duplicate_Result, Missing_Result, Inconsistent_Result, Contradictory_Result_Active,
      Nonterminal_Result, Noncanonical_Result,
      Noncanonical_Indicator,
      Invalid_Measurement, Contradictory_Measurement_Active,
      Noncanonical_Measurement, Missing_Measurement_Semantics,
      Noncanonical_Measurement_Semantics, Duplicate_Finding, Malformed_Finding, Noncanonical_Finding,
      Inactive_Finding, Mismatched_Finding,
      Malformed_Execution, Noncanonical_Execution,
      Invalid_Run_State, Unsupported_Evidence_Format, Malformed_Run_Timestamp,
      Incomplete_Run_Timestamps, Orphaned_Run_Finish, Inverted_Run_Timestamps,
      Missing_Terminal_Event,
      Malformed_Metadata, Extra_Metadata);
   --  Internal corruption mode selected by the explicit test child.

   procedure Testing_Set_Schema_Version (Item : in out Store; Version : Positive);
   --  Internal implementation of the test child's schema-version override.
   --  @param Item Open disposable store.
   --  @param Version Version to persist.
   procedure Testing_Inject_Next_Fault (Item : in out Store; Point : Testing_Fault_Point);
   --  Internal implementation of deterministic commit fault injection.
   --  @param Item Store whose operation will fail.
   --  @param Point Commit boundary to fail.
   procedure Testing_Use_Legacy_Evidence (Item : in out Store; Enabled : Boolean);
   --  Internal implementation of legacy fixture encoding selection.
   --  @param Item Store whose publication encoding is selected.
   --  @param Enabled Whether legacy encoding is active.
   procedure Testing_Corrupt (Item : in out Store; Run_Id : Positive; Kind : Testing_Corruption);
   --  Internal implementation of deliberate fixture corruption.
   --  @param Item Open disposable store.
   --  @param Run_Id Published run to damage.
   --  @param Kind Damage to apply.

   type Schema_Array is array (Positive range 1 .. 8) of Database.Schema.Table_Schema;
   type Identifier_Array is array (Positive range 1 .. 8) of Positive;

   type Store is new Ada.Finalization.Limited_Controlled with record
      DB      : Database.Handle;
      Schemas : Schema_Array;
      Next_Identifiers : Identifier_Array := [others => 1];
      Opened  : Boolean := False;
      Next_Testing_Fault : Testing_Fault_Point := No_Testing_Fault;
      Legacy_Testing_Evidence : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Store);
   --  Close the database and release its lock during controlled finalization.
   --  @param Item Store being finalized.
end Ada_Quality.Storage;
