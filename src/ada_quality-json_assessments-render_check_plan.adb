separate (Ada_Quality.JSON_Assessments)
function Render_Check_Plan
     (Items : Check_Plan_Vectors.Vector; Pretty : Boolean := False) return String
   is
      Doc : Document;
      Root : constant Node := Doc.New_Object;
      Values : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("check-plan"));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; begin
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
            Doc.Insert
              (Object, "source_fingerprint", Doc.New_String (To_String (Item.Source_Fingerprint)));
            Doc.Insert
              (Object, "policy_fingerprint", Doc.New_String (To_String (Item.Policy_Fingerprint)));
            Doc.Insert
              (Object, "toolchain_fingerprint", Doc.New_String (To_String (Item.Toolchain_Fingerprint)));
            Doc.Insert
              (Object, "reuse_eligible", Doc.New_Boolean (Item.Reusable_Assessment > 0));
            if Item.Will_Reuse then
               Doc.Insert (Object, "action", Doc.New_String ("reuse"));
            else
               Doc.Insert (Object, "action", Doc.New_String ("assess"));
            end if;
            if Item.Reusable_Assessment > 0 then
               Doc.Insert
                 (Object, "assessment_id",
                  Doc.New_Integer (Long_Long_Integer (Item.Reusable_Assessment)));
            end if;
            Doc.Append (Values, Object);
         end;
      end loop;
      Doc.Insert (Root, "projects", Values);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Check_Plan;
