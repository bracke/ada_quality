with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
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

   type Testing_Fault_Point is
     (No_Testing_Fault, Schema_Creation_Commit, Schema_Migration_Commit,
      Assessment_Start_Commit, Assessment_Publication_Commit,
      Assessment_Interruption_Commit, Assessment_Recovery_Commit);
   --  Transaction boundary at which a test may inject one deterministic failure.
   --  @enum No_Testing_Fault Disable fault injection.
   --  @enum Schema_Creation_Commit Fail the schema-creation commit.
   --  @enum Schema_Migration_Commit Fail the schema-migration commit.
   --  @enum Assessment_Start_Commit Fail the assessment-start commit.
   --  @enum Assessment_Publication_Commit Fail the terminal-publication commit.
   --  @enum Assessment_Interruption_Commit Fail the interruption commit.
   --  @enum Assessment_Recovery_Commit Fail the recovery commit.

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

   type History_Item is record
      Id         : Positive;
      Project_Id : Positive;
      Status     : Unbounded_String;
      Summary    : Unbounded_String;
      Source_Fingerprint    : Unbounded_String;
      Policy_Fingerprint    : Unbounded_String;
      Toolchain_Fingerprint : Unbounded_String;
   end record;
   --  Immutable assessment-history metadata.
   --  @field Id Positive assessment identity.
   --  @field Project_Id Owning project identity.
   --  @field Status Persisted lifecycle state.
   --  @field Summary Stable publication summary.
   --  @field Source_Fingerprint Assessed source identity.
   --  @field Policy_Fingerprint Applied policy identity.
   --  @field Toolchain_Fingerprint Selected toolchain identity.

   package History_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => History_Item);
   --  Ordered assessment-history collection.

   type Detail_Info is record
      Id       : Positive;
      Run_Id   : Positive;
      Kind     : Unbounded_String;
      State    : Unbounded_String;
      Summary  : Unbounded_String;
   end record;
   --  Generic immutable child row used for results, measurements, findings, executions, and events.
   --  @field Id Positive row identity.
   --  @field Run_Id Owning assessment identity.
   --  @field Kind Stable detail key or category.
   --  @field State Persisted detail state.
   --  @field Summary Persisted payload or evidence summary.

   package Detail_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Detail_Info);
   --  Ordered detail-row collection.

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

   procedure Testing_Set_Schema_Version (Item : in out Store; Version : Positive);
   --  Override schema metadata for migration and fail-closed tests.
   --  @param Item Open test store.
   --  @param Version Version value to persist.

   procedure Testing_Inject_Next_Fault (Point : Testing_Fault_Point);
   --  Arm one deterministic commit fault for the next matching transaction.
   --  @param Point Transaction boundary to fail, or No_Testing_Fault to disarm.

   procedure Check (Item : in out Store);
   --  Validate schema, row ownership, lifecycle, cardinality, and immutable evidence invariants.
   --  @param Item Open store to check.

private
   type Schema_Array is array (Positive range 1 .. 8) of Database.Schema.Table_Schema;

   type Store is new Ada.Finalization.Limited_Controlled with record
      DB      : Database.Handle;
      Schemas : Schema_Array;
      Opened  : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Store);
   --  Close the database and release its lock during controlled finalization.
   --  @param Item Store being finalized.
end Ada_Quality.Storage;
