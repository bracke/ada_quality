separate (Ada_Quality.JSON_Assessments)
function Render_Reuse
     (Project_Id, Assessment_Id : Positive; Pretty : Boolean := False) return String
   is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-reuse"));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Project_Id)));
      Doc.Insert (Root, "assessment_id", Doc.New_Integer (Long_Long_Integer (Assessment_Id)));
      Doc.Insert (Root, "status", Doc.New_String ("reused"));
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Reuse;
