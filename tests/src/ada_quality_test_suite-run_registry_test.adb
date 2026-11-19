separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_registry_test owner=core expires=2099-12-31 justification=one-component-fixture-matrix
procedure Run_Registry_Test is
   Id : Indicator_Id;
begin
Assert (Ada_Quality.Indicators.Count = 33, "registry contains exactly 33 indicators");
declare
   Registry : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
   Tool_Registry : constant Ada_Quality.Tools.Tool_Descriptor_Array := Ada_Quality.Tools.Registry;
begin
   for Expected in Indicator_Id loop
      Assert (Registry (Expected).Id = Expected and then Registry (Expected).Version = 1 and then
        Registry (Expected).Measurement_Version = 1 and then
        Registry (Expected).Unit_Name.all = Ada_Quality.Indicators.Measurement_Unit (Expected) and then
        Registry (Expected).Gate = Ada_Quality.Indicators.Is_Gate (Expected) and then
        Registry (Expected).Trend = Ada_Quality.Indicators.Direction_Of (Expected) and then
        Ada_Quality.Indicators.Remediation (Expected)'Length > 0,
        "registry descriptors preserve strong IDs and versions");
   end loop;
   for Tool in Ada_Quality.Tools.Tool_Id loop
      Assert (Tool_Registry (Tool).Id = Tool and then Tool_Registry (Tool).Program.all'Length > 0,
        "tool descriptors preserve registered program identities");
   end loop;
end;
for Expected in Indicator_Id loop
   Assert (Ada_Quality.Indicators.Parse (Image (Expected), Id), "indicator image parses");
   Assert (Id = Expected, "indicator parse round trip");
end loop;
Assert (not Ada_Quality.Indicators.Parse ("not-an-indicator", Id) and then Id = STR_01,
  "invalid indicator names are rejected without raising");
Assert (not Ada_Quality.Indicators.Parse_Canonical ("str_01", Id),
  "persisted indicator identities require their canonical spelling");
Assert (Ada_Quality.Indicators.Validate_Acyclic, "indicator prerequisite graph is acyclic");
for Tool in Ada_Quality.Tools.Tool_Id loop
   Assert (Ada_Quality.Tools.Program (Tool)'Length > 0, "tool registry programs are explicit");
end loop;
Assert (Ada_Quality.Presentation.Result_Line ("+", "STR-01", "pass") = "+ STR-01 pass",
  "human result lines are rendered through the message catalog");
Assert (Image (Execution_Status'(Not_Applicable)) = "not-applicable" and then
  Image (Compliance_Status'(Not_Applicable)) = "not-applicable" and then
  Image (Tool_Spawn_Error) = "tool-spawn-error",
  "status images normalize compound enumeration names");
Assert (Image (Measurement_Value'(Kind => Unavailable_Value,
  Reason => To_Unbounded_String ("missing"))) = "missing" and then
  Image (Measurement_Value'(Kind => Integer_Value, Integer_Data => 17)) = " 17" and then
  Image (Measurement_Value'(Kind => Decimal_Value, Basis_Points => 9_250)) = " 9250" and then
  Image (Measurement_Value'(Kind => Text_Value,
    Text_Data => To_Unbounded_String ("text"))) = "text" and then
  Image (Measurement_Value'(Kind => Enum_Value,
    Text_Data => To_Unbounded_String ("enum"))) = "enum",
  "all measurement variants have stable persisted images");
end Run_Registry_Test;
