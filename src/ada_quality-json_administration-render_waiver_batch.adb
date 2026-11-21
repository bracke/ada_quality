separate (Ada_Quality.JSON_Administration)
function Render_Waiver_Batch
  (Items : Waiver_Report_Vectors.Vector;
   Maximum_Invalid : Natural := 0; Maximum_Expiring : Natural := Natural'Last;
   Invalid_Count : Natural := Natural'Last; Expiring_Count : Natural := Natural'Last;
   Pretty : Boolean := False) return String
is
   Doc : Document;
   Root : constant Node := Doc.New_Object;
   Projects : constant Node := Doc.New_Array;
   Invalid, Expiring : Natural := 0;
begin
   Doc.Insert (Root, "schema_version", Doc.New_Integer (2));
   Doc.Insert (Root, "kind", Doc.New_String ("waiver-audit"));
   for Item of Items loop
      declare
         Object : constant Node := Doc.New_Object;
         Values : constant Node := Doc.New_Array;
      begin
         Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
         Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
         for Waiver of Item.Waivers loop
            Append_Waiver (Doc, Values, Waiver);
            if Waiver.Status in
              Ada_Quality.Checks.Waiver_Expired | Ada_Quality.Checks.Waiver_Invalid
            then
               Invalid := Invalid + 1;
            end if;
            if Waiver.Expiring then
               Expiring := Expiring + 1;
            end if;
         end loop;
         Doc.Insert (Object, "waivers", Values);
         Doc.Append (Projects, Object);
      end;
   end loop;
   if Invalid_Count /= Natural'Last then
      Invalid := Invalid_Count;
   end if;
   if Expiring_Count /= Natural'Last then
      Expiring := Expiring_Count;
   end if;
   Doc.Insert (Root, "invalid_count", Doc.New_Integer (Long_Long_Integer (Invalid)));
   Doc.Insert (Root, "maximum_invalid", Doc.New_Integer (Long_Long_Integer (Maximum_Invalid)));
   Doc.Insert (Root, "expiring_count", Doc.New_Integer (Long_Long_Integer (Expiring)));
   Doc.Insert (Root, "maximum_expiring", Doc.New_Integer (Long_Long_Integer (Maximum_Expiring)));
   Doc.Insert
     (Root, "threshold_passed",
      Doc.New_Boolean (Invalid <= Maximum_Invalid and then Expiring <= Maximum_Expiring));
   Doc.Insert (Root, "projects", Projects);
   Doc.Set_Root (Root);
   return Serialize (Doc, Pretty);
end Render_Waiver_Batch;
