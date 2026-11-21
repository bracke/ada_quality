separate (Ada_Quality_Test_Suite)
procedure Run_Status_Test is
begin
Assert
  (Is_Valid
     ((Indicator => STR_01, Execution => Succeeded, Compliance => Pass, Applicable => True,
       Summary => Null_Unbounded_String, Evidence => Null_Unbounded_String,
       Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>)),
   "succeeded/pass combination is valid");
Assert
  (not Is_Valid
     ((Indicator => STR_01, Execution => Blocked, Compliance => Pass, Applicable => True,
       Summary => Null_Unbounded_String, Evidence => Null_Unbounded_String,
       Measurement => (Kind => Unavailable_Value, Reason => Null_Unbounded_String), Findings => <>)),
   "blocked evidence cannot pass");
declare
   Units_Are_Defined : Boolean := True;
begin
   for Id in Indicator_Id loop
      Units_Are_Defined := Units_Are_Defined and then
        Ada_Quality.Indicators.Measurement_Unit (Id)'Length > 0;
   end loop;
   Assert (Units_Are_Defined, "every indicator has a stable measurement unit");
end;
declare
   Evaluated : constant Indicator_Result := Ada_Quality.Evaluation.Evaluate
     (STR_01, Succeeded, True, False, "present", "missing", "fixture");
begin
   Assert (Evaluated.Compliance = Violation and then Is_Valid (Evaluated),
     "the evaluator maps successful negative evidence to a valid violation");
end;
declare
   Value : Assessment;
begin
   Value.Project_Id := 1;
   Value.Status := Assessment_Completed;
   Value.Source_Fingerprint := To_Unbounded_String ("source");
   Value.Policy_Fingerprint := To_Unbounded_String ("policy");
   Value.Toolchain_Fingerprint := To_Unbounded_String ("toolchain");
   for Indicator in Indicator_Id loop
      Value.Results.Append
        (Indicator_Result'(Indicator => Indicator, Execution => Succeeded, Compliance => Pass,
          Applicable => True, Summary => To_Unbounded_String ("pass"),
          Evidence => To_Unbounded_String ("evidence"),
          Measurement => (Kind => Boolean_Value, Boolean_Data => True), Findings => <>));
   end loop;
   Assert (Is_Publishable (Value), "complete unique terminal results are publishable");
   Value.Executions.Append
     (Tool_Execution'
        (Tool => To_Unbounded_String ("fixture"), Command => To_Unbounded_String ("fixture <arg>"),
         Status => Tool_Completed, Exit_Code => 0,
         Output_Digest => To_Unbounded_String ("not-a-digest"),
         Output_Bytes => 0, Truncated => False));
   Assert (not Is_Publishable (Value),
     "publication rejects noncanonical execution digests");
   Value.Executions.Reference (Value.Executions.First_Index).Output_Digest :=
     To_Unbounded_String ("cbf29ce484222325");
   Assert (Is_Publishable (Value),
     "publication accepts canonical lowercase 64-bit execution digests");
   Value.Executions.Reference (Value.Executions.First_Index).Status := Tool_Spawn_Error;
   Assert (not Is_Publishable (Value),
     "spawn-error evidence cannot claim a child exit code");
   Value.Executions.Reference (Value.Executions.First_Index).Status := Tool_Completed;
   declare
      Nonterminal : Indicator_Result := Value.Results.First_Element;
   begin
      Nonterminal.Execution := Running;
      Nonterminal.Compliance := Unknown;
      Nonterminal.Measurement :=
        (Kind => Unavailable_Value, Reason => To_Unbounded_String ("still running"));
      Value.Results.Replace_Element (Value.Results.First_Index, Nonterminal);
      Assert (not Is_Publishable (Value),
        "terminal assessments reject running indicator evidence");
      Nonterminal.Execution := Succeeded;
      Nonterminal.Compliance := Pass;
      Nonterminal.Measurement := (Kind => Boolean_Value, Boolean_Data => True);
      Value.Results.Replace_Element (Value.Results.First_Index, Nonterminal);
   end;
   Value.Source_Fingerprint := Null_Unbounded_String;
   Assert (not Is_Publishable (Value), "publication requires a source fingerprint");
   Value.Source_Fingerprint := To_Unbounded_String ("source");
   Value.Policy_Fingerprint := To_Unbounded_String ("policy" & Character'Val (10) & "injected");
   Assert (not Is_Publishable (Value), "publication identities must remain single-line values");
   Value.Policy_Fingerprint := To_Unbounded_String ("policy");
   Value.Results.Delete_Last;
   Assert (not Is_Publishable (Value), "partial assessments are not publishable");
end;
end Run_Status_Test;
