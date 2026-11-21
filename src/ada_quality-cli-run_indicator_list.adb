with Ada_Quality.JSON_Reports;

separate (Ada_Quality.CLI)
function Run_Indicator_List return Natural is
   Filtered  : constant Boolean := Option ("--category", "") /= "";
   Category  : Ada_Quality.Indicators.Indicator_Category := Ada_Quality.Indicators.Structure;
   Format    : constant String :=
     Selected_Output_Format
       ("text", "text|json", "indicator list format requires text or json");
   Registry  : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
begin
   if Filtered then
      begin
         Category := Ada_Quality.Indicators.Indicator_Category'Value (Option ("--category", ""));
      exception
         when Constraint_Error =>
            raise Usage_Error with
              "--category requires structure, build, test, source, documentation, dependency," &
              " security, release, or proof";
      end;
   end if;
   if Format = "json" then
      Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
      Emit_Document
        (Ada_Quality.JSON_Reports.Render_Indicators
           (Filtered, Category, Pretty => True));
   else
      declare Output : Ada.Strings.Unbounded.Unbounded_String; begin
      for Id in Indicator_Id loop
         declare
            Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Registry (Id);
         begin
            if not Filtered or else Descriptor.Category = Category then
               Append
                 (Output, Image (Id) & " " &
                  Ada_Quality.Indicators.Indicator_Category'Image (Descriptor.Category) & " " &
                  Descriptor.Name.all & ASCII.LF);
            end if;
         end;
      end loop;
      Emit_Document (To_String (Output));
      end;
   end if;
   return 0;
end Run_Indicator_List;
