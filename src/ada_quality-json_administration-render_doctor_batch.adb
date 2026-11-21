separate (Ada_Quality.JSON_Administration)
function Render_Doctor_Batch
  (Items : Diagnostic_Report_Vectors.Vector;
   Global_Checks : Diagnostic_Vectors.Vector := Diagnostic_Vectors.Empty_Vector;
   Maximum_Failures : Natural := 0; Pretty : Boolean := False) return String
is
   Doc : Document;
   Root : constant Node := Doc.New_Object;
   Projects : constant Node := Doc.New_Array;
   Checks : constant Node := Doc.New_Array;
   Passed : Boolean := True;
   Failures : Natural := 0;
begin
   Doc.Insert (Root, "schema_version", Doc.New_Integer (2));
   Doc.Insert (Root, "kind", Doc.New_String ("doctor-report"));
   Append_Diagnostics (Doc, Checks, Global_Checks, Passed);
   for Check of Global_Checks loop
      if not Check.Passed then
         Failures := Failures + 1;
      end if;
   end loop;
   for Item of Items loop
      declare
         Object : constant Node := Doc.New_Object;
         Checks : constant Node := Doc.New_Array;
         Project_Passed : Boolean := True;
      begin
         Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
         Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
         Append_Diagnostics (Doc, Checks, Item.Checks, Project_Passed);
         Doc.Insert (Object, "passed", Doc.New_Boolean (Project_Passed));
         Doc.Insert (Object, "checks", Checks);
         Doc.Append (Projects, Object);
         for Check of Item.Checks loop
            if not Check.Passed then
               Failures := Failures + 1;
            end if;
         end loop;
      end;
   end loop;
   Passed := Failures <= Maximum_Failures;
   Doc.Insert (Root, "failure_count", Doc.New_Integer (Long_Long_Integer (Failures)));
   Doc.Insert
     (Root, "maximum_failures", Doc.New_Integer (Long_Long_Integer (Maximum_Failures)));
   Doc.Insert (Root, "threshold_passed", Doc.New_Boolean (Passed));
   Doc.Insert (Root, "passed", Doc.New_Boolean (Passed));
   Doc.Insert (Root, "checks", Checks);
   Doc.Insert (Root, "projects", Projects);
   Doc.Set_Root (Root);
   return Serialize (Doc, Pretty);
end Render_Doctor_Batch;
