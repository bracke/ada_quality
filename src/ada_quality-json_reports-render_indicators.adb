separate (Ada_Quality.JSON_Reports)
function Render_Indicators
     (Filter_Category : Boolean := False;
      Category        : Ada_Quality.Indicators.Indicator_Category := Ada_Quality.Indicators.Structure;
      Pretty          : Boolean := False) return String
   is
      Doc      : Document;
      Root     : constant Node := Doc.New_Object;
      Items    : constant Node := Doc.New_Array;
      Registry : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("indicator-catalog"));
      for Id in Indicator_Id loop
         declare
            Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor := Registry (Id);
         begin
            if not Filter_Category or else Descriptor.Category = Category then
               declare
                  Object       : constant Node := Doc.New_Object;
                  Prerequisites : constant Node := Doc.New_Array;
               begin
                  Doc.Insert (Object, "id", Doc.New_String (Image (Id)));
                  Doc.Insert (Object, "name", Doc.New_String (Descriptor.Name.all));
                  Doc.Insert
                    (Object, "category",
                     Doc.New_String (Ada_Quality.Indicators.Indicator_Category'Image (Descriptor.Category)));
                  Doc.Insert (Object, "version", Doc.New_Integer (Long_Long_Integer (Descriptor.Version)));
                  Doc.Insert
                    (Object, "measurement_version",
                     Doc.New_Integer (Long_Long_Integer (Descriptor.Measurement_Version)));
                  Doc.Insert (Object, "unit", Doc.New_String (Descriptor.Unit_Name.all));
                  Doc.Insert (Object, "gate", Doc.New_Boolean (Descriptor.Gate));
                  Doc.Insert
                    (Object, "trend",
                     Doc.New_String (Ada_Quality.Indicators.Metric_Direction'Image (Descriptor.Trend)));
                  for Dependency in Indicator_Id loop
                     if Descriptor.Prerequisites (Dependency) then
                        Doc.Append (Prerequisites, Doc.New_String (Image (Dependency)));
                     end if;
                  end loop;
                  Doc.Insert (Object, "prerequisites", Prerequisites);
                  Doc.Insert
                    (Object, "remediation", Doc.New_String (Ada_Quality.Indicators.Remediation (Id)));
                  Doc.Append (Items, Object);
               end;
            end if;
         end;
      end loop;
      Doc.Insert (Root, "indicators", Items);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Indicators;
