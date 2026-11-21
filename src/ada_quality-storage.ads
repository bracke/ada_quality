with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Ada_Quality.History_Data;
with Ada_Quality.Resource_Limits;
with Ada_Quality.Types;
with Database;
with Database.Schema;
with Database.Status;

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
      Tags    : Unbounded_String;
      Enabled : Boolean := True;
      Removed : Boolean := False;
   end record;
   --  Persistent project registry row.
   --  @field Id Positive project identity.
   --  @field Path Canonical project root.
   --  @field Tags Sorted comma-separated project tags.
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

   type Merge_Conflict is record
      Name   : Unbounded_String;
      Detail : Unbounded_String;
   end record;
   package Merge_Conflict_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Merge_Conflict);
   package Source_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");
   type Merge_Report is record
      Added_Projects     : Natural := 0;
      Added_Assessments  : Natural := 0;
      Reused_Assessments : Natural := 0;
      Added_Aliases      : Natural := 0;
      Conflicts          : Merge_Conflict_Vectors.Vector;
   end record;

   type Integrity_Limits is record
      Max_Total_Rows : Positive := Ada_Quality.Resource_Limits.Maximum_Database_Rows;
      Max_Text_Bytes : Positive :=
        Ada_Quality.Resource_Limits.Maximum_Database_Text_Bytes;
   end record;
   --  Resource bounds for a full database integrity audit.

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

   procedure Require_OK
     (Status : Database.Status.Result; Context : String);
   --  Raise Storage_Error with Context unless Status is successful.

   function Next_Id
     (Item : in out Store; Table : Positive) return Positive;
   --  Reserve one identity from the open store's exclusive high-water mark.

   function Reserve_Ids
     (Item : in out Store; Table : Positive; Count : Natural)
      return Positive;
   --  Reserve Count consecutive identities from the exclusive high-water mark.

   function Measurement_State
     (Id : Ada_Quality.Types.Indicator_Id;
      Kind : Ada_Quality.Types.Value_Kind) return String;
   function Assessment_Status_Image
     (Value : Ada_Quality.Types.Assessment_Status) return String;

   procedure Trigger_Testing_Fault
     (Item : in out Store; Point : Testing_Fault_Point);
   --  Raise the configured deterministic test fault at Point, if any.
end Ada_Quality.Storage;
