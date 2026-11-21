separate (Ada_Quality.CLI)
function Run_Explain (Name : String) return Natural is
   Indicator : Indicator_Id;
   Output : Ada.Strings.Unbounded.Unbounded_String;
begin
   if not Ada_Quality.Indicators.Parse_Canonical (Name, Indicator) then
      raise Usage_Error with "explain requires a canonical indicator ID";
   end if;
   declare
      Registry   : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
      Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Registry (Indicator);
      Has_Prerequisite : Boolean := False;
   begin
      Append (Output, Image (Indicator) & " - " & Descriptor.Name.all & ASCII.LF);
      Append
        (Output, "category: " & Ada_Quality.Indicators.Indicator_Category'Image
           (Descriptor.Category) & ASCII.LF);
      Append
        (Output, "version:" & Positive'Image (Descriptor.Version) & ", measurement version:" &
         Positive'Image (Descriptor.Measurement_Version) & ASCII.LF);
      Append
        (Output, "unit: " & Descriptor.Unit_Name.all & ", gate: " & Boolean'Image (Descriptor.Gate) &
         ", trend: " & Ada_Quality.Indicators.Metric_Direction'Image (Descriptor.Trend) & ASCII.LF);
      Append (Output, "prerequisites:");
      for Dependency in Indicator_Id loop
         if Descriptor.Prerequisites (Dependency) then
            Append (Output, " " & Image (Dependency));
            Has_Prerequisite := True;
         end if;
      end loop;
      if not Has_Prerequisite then Append (Output, " none"); end if;
      Append (Output, ASCII.LF);
      Append (Output, "remediation: " & Ada_Quality.Indicators.Remediation (Indicator) & ASCII.LF);
   end;
   Emit_Document (To_String (Output));
   return 0;
end Run_Explain;
