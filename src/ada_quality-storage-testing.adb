package body Ada_Quality.Storage.Testing is
   type Corruption_Mapping is array (Corruption) of Testing_Corruption;
   Corruption_Map : constant Corruption_Mapping :=
     [Duplicate_Result => Duplicate_Result,
      Missing_Result => Missing_Result,
      Inconsistent_Result => Inconsistent_Result,
      Contradictory_Result_Active => Contradictory_Result_Active,
      Nonterminal_Result => Nonterminal_Result,
      Noncanonical_Result => Noncanonical_Result,
      Noncanonical_Indicator => Noncanonical_Indicator,
      Invalid_Measurement => Invalid_Measurement,
      Contradictory_Measurement_Active => Contradictory_Measurement_Active,
      Noncanonical_Measurement => Noncanonical_Measurement,
      Missing_Measurement_Semantics => Missing_Measurement_Semantics,
      Noncanonical_Measurement_Semantics => Noncanonical_Measurement_Semantics,
      Duplicate_Finding => Duplicate_Finding,
      Malformed_Finding => Malformed_Finding,
      Noncanonical_Finding => Noncanonical_Finding,
      Inactive_Finding => Inactive_Finding,
      Mismatched_Finding => Mismatched_Finding,
      Malformed_Execution => Malformed_Execution,
      Noncanonical_Execution => Noncanonical_Execution,
      Invalid_Run_State => Invalid_Run_State,
      Unsupported_Evidence_Format => Unsupported_Evidence_Format,
      Malformed_Run_Timestamp => Malformed_Run_Timestamp,
      Incomplete_Run_Timestamps => Incomplete_Run_Timestamps,
      Orphaned_Run_Finish => Orphaned_Run_Finish,
      Inverted_Run_Timestamps => Inverted_Run_Timestamps,
      Missing_Terminal_Event => Missing_Terminal_Event,
      Malformed_Metadata => Malformed_Metadata,
      Extra_Metadata => Extra_Metadata];

   procedure Set_Schema_Version (Item : in out Store; Version : Positive) is
   begin
      Testing_Set_Schema_Version (Item, Version);
   end Set_Schema_Version;

   procedure Inject_Next_Fault (Item : in out Store; Point : Fault_Point) is
   begin
      Testing_Inject_Next_Fault
        (Item,
         (case Point is
           when No_Fault => No_Testing_Fault,
           when Schema_Creation => Schema_Creation_Commit,
           when Schema_Migration => Schema_Migration_Commit,
           when Assessment_Start => Assessment_Start_Commit,
           when Assessment_Publication => Assessment_Publication_Commit,
           when Assessment_Interruption => Assessment_Interruption_Commit,
           when Assessment_Recovery => Assessment_Recovery_Commit));
   end Inject_Next_Fault;

   procedure Use_Legacy_Evidence (Item : in out Store; Enabled : Boolean) is
   begin
      Testing_Use_Legacy_Evidence (Item, Enabled);
   end Use_Legacy_Evidence;

   procedure Corrupt (Item : in out Store; Run_Id : Positive; Kind : Corruption) is
   begin
      Testing_Corrupt
        (Item, Run_Id, Corruption_Map (Kind));
   end Corrupt;
end Ada_Quality.Storage.Testing;
