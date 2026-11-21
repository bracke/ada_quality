separate (Ada_Quality.JSON_Administration)
function Render_Doctor
  (Items : Diagnostic_Vectors.Vector; Maximum_Failures : Natural := 0;
   Failure_Count : Natural := Natural'Last; Pretty : Boolean := False) return String
is
   Doc : Document;
   Root : constant Node := Doc.New_Object;
   Values : constant Node := Doc.New_Array;
   Failures : Natural := 0;
begin
   Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
   Doc.Insert (Root, "kind", Doc.New_String ("doctor-report"));
   for Item of Items loop
      declare
         Object : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Object, "name", Doc.New_String (To_String (Item.Name)));
         Doc.Insert (Object, "passed", Doc.New_Boolean (Item.Passed));
         Doc.Insert (Object, "detail", Doc.New_String (To_String (Item.Detail)));
         Doc.Append (Values, Object);
         if not Item.Passed then
            Failures := Failures + 1;
         end if;
      end;
   end loop;
   if Failure_Count /= Natural'Last then
      Failures := Failure_Count;
   end if;
   Doc.Insert (Root, "failure_count", Doc.New_Integer (Long_Long_Integer (Failures)));
   Doc.Insert
     (Root, "maximum_failures", Doc.New_Integer (Long_Long_Integer (Maximum_Failures)));
   Doc.Insert (Root, "threshold_passed", Doc.New_Boolean (Failures <= Maximum_Failures));
   Doc.Insert (Root, "passed", Doc.New_Boolean (Failures <= Maximum_Failures));
   Doc.Insert (Root, "checks", Values);
   Doc.Set_Root (Root);
   return Serialize (Doc, Pretty);
end Render_Doctor;
