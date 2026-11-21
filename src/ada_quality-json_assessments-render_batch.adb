separate (Ada_Quality.JSON_Assessments)
function Render_Batch
     (Items : Batch_Outcome_Vectors.Vector; Pretty : Boolean := False) return String
   is
      Doc      : Document;
      Root     : constant Node := Doc.New_Object;
      Outcomes : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-batch"));
      for Item of Items loop
         declare
            Outcome : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Outcome, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert
              (Outcome, "assessment_id", Doc.New_Integer (Long_Long_Integer (Item.Assessment_Id)));
            Doc.Insert
              (Outcome, "status",
               Doc.New_String
                 ((case Item.Status is
                     when Batch_Completed => "completed",
                     when Batch_Reused => "reused",
                     when Batch_Interrupted => "interrupted")));
            Doc.Insert (Outcome, "diagnostic", Doc.New_String (To_String (Item.Diagnostic)));
            if Item.Status = Batch_Completed then
               declare
                  Assessment_Object : constant Node := Doc.New_Object;
               begin
                  Populate_Assessment (Doc, Assessment_Object, Item.Value);
                  Doc.Insert (Outcome, "assessment", Assessment_Object);
               end;
            end if;
            Doc.Append (Outcomes, Outcome);
         end;
      end loop;
      Doc.Insert (Root, "outcomes", Outcomes);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Batch;
