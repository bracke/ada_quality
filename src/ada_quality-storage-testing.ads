--  Explicit test-only controls for storage migration, fault, and corruption fixtures.
package Ada_Quality.Storage.Testing is
   type Fault_Point is
     (No_Fault, Schema_Creation, Schema_Migration, Assessment_Start, Assessment_Publication,
      Assessment_Interruption, Assessment_Recovery);
   --  Commit boundary selected for deterministic fault injection.
   --  @enum No_Fault Disable fault injection.
   --  @enum Schema_Creation Fail schema creation commit.
   --  @enum Schema_Migration Fail schema migration commit.
   --  @enum Assessment_Start Fail assessment start commit.
   --  @enum Assessment_Publication Fail assessment publication commit.
   --  @enum Assessment_Interruption Fail assessment interruption commit.
   --  @enum Assessment_Recovery Fail assessment recovery commit.

   type Corruption is
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
   --  Deliberate damage applied to a disposable database.
   --  @enum Duplicate_Result Duplicate one indicator result.
   --  @enum Missing_Result Remove one indicator result.
   --  @enum Inconsistent_Result Store a validly spelled but contradictory result state.
   --  @enum Contradictory_Result_Active Contradict the result compliance-derived active flag.
   --  @enum Nonterminal_Result Store a running result with a matching unavailable measurement.
   --  @enum Noncanonical_Result Add an otherwise parseable extra result payload field.
   --  @enum Noncanonical_Indicator Store a parseable but noncanonical result identifier.
   --  @enum Invalid_Measurement Replace a numeric value with malformed text.
   --  @enum Contradictory_Measurement_Active Contradict the execution-derived measurement active flag.
   --  @enum Noncanonical_Measurement Store a parseable but noncanonical numeric value.
   --  @enum Missing_Measurement_Semantics Remove required schema-3 semantic versions.
   --  @enum Noncanonical_Measurement_Semantics Store a malformed semantic-version suffix.
   --  @enum Duplicate_Finding Duplicate one stable finding identity within a run.
   --  @enum Malformed_Finding Replace a finding payload with malformed text.
   --  @enum Noncanonical_Finding Add an otherwise parseable extra finding payload field.
   --  @enum Inactive_Finding Mark a persisted finding inactive.
   --  @enum Mismatched_Finding Store a valid identity for a different indicator than the payload.
   --  @enum Malformed_Execution Replace structured tool-execution evidence with malformed text.
   --  @enum Noncanonical_Execution Replace the output digest with a noncanonical spelling.
   --  @enum Invalid_Run_State Store an unknown lifecycle state.
   --  @enum Unsupported_Evidence_Format Store an unknown child-evidence format marker.
   --  @enum Malformed_Run_Timestamp Store an invalid assessment timestamp.
   --  @enum Incomplete_Run_Timestamps Remove the terminal timestamp from a lossless run.
   --  @enum Orphaned_Run_Finish Remove the start timestamp while retaining the finish timestamp.
   --  @enum Inverted_Run_Timestamps Store a finish timestamp earlier than the start timestamp.
   --  @enum Missing_Terminal_Event Remove the run's terminal lifecycle event.
   --  @enum Malformed_Metadata Store contradictory schema metadata state.
   --  @enum Extra_Metadata Insert a second schema metadata row.

   procedure Set_Schema_Version (Item : in out Store; Version : Positive);
   --  Override schema metadata in a disposable fixture.
   --  @param Item Open test store.
   --  @param Version Version value to persist.

   procedure Inject_Next_Fault (Item : in out Store; Point : Fault_Point);
   --  Arm one deterministic commit fault.
   --  @param Item Store whose next matching operation will fail.
   --  @param Point Transaction boundary to fail.

   procedure Use_Legacy_Evidence (Item : in out Store; Enabled : Boolean);
   --  Select the legacy evidence encoding for subsequent fixture publications.
   --  @param Item Store whose publications use the selected encoding.
   --  @param Enabled Whether legacy encoding is active.

   procedure Corrupt (Item : in out Store; Run_Id : Positive; Kind : Corruption);
   --  Damage one published run in a disposable database.
   --  @param Item Open test store.
   --  @param Run_Id Published run to damage.
   --  @param Kind Damage to apply.
end Ada_Quality.Storage.Testing;
