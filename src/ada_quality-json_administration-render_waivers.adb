separate (Ada_Quality.JSON_Administration)
function Render_Waivers
  (Items : Ada_Quality.Checks.Waiver_Audit_Vectors.Vector;
   Maximum_Invalid : Natural := 0; Maximum_Expiring : Natural := Natural'Last;
   Invalid_Count : Natural := Natural'Last; Expiring_Count : Natural := Natural'Last;
   Pretty : Boolean := False) return String
is
   Doc : Document;
   Root : constant Node := Doc.New_Object;
   Values : constant Node := Doc.New_Array;
   Invalid, Expiring : Natural := 0;
begin
   Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
   Doc.Insert (Root, "kind", Doc.New_String ("waiver-audit"));
   for Item of Items loop
      declare
         Object : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Object, "rule", Doc.New_String (To_String (Item.Rule)));
         Doc.Insert (Object, "target", Doc.New_String (To_String (Item.Target)));
         Doc.Insert (Object, "owner", Doc.New_String (To_String (Item.Owner)));
         Doc.Insert (Object, "expires", Doc.New_String (To_String (Item.Expires)));
         Doc.Insert (Object, "justification", Doc.New_String (To_String (Item.Justification)));
         Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Relative_Path)));
         Doc.Insert (Object, "line", Doc.New_Integer (Long_Long_Integer (Item.Line)));
         Doc.Insert (Object, "expiring", Doc.New_Boolean (Item.Expiring));
         Doc.Insert
           (Object, "status", Doc.New_String
              ((case Item.Status is
                  when Ada_Quality.Checks.Waiver_Active => "active",
                  when Ada_Quality.Checks.Waiver_Unused => "unused",
                  when Ada_Quality.Checks.Waiver_Expired => "expired",
                  when Ada_Quality.Checks.Waiver_Invalid => "invalid")));
         Doc.Append (Values, Object);
         if Item.Status in Ada_Quality.Checks.Waiver_Expired | Ada_Quality.Checks.Waiver_Invalid then
            Invalid := Invalid + 1;
         end if;
         if Item.Expiring then
            Expiring := Expiring + 1;
         end if;
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
   Doc.Insert (Root, "waivers", Values);
   Doc.Set_Root (Root);
   return Serialize (Doc, Pretty);
end Render_Waivers;
