separate (Ada_Quality.JSON_Administration)
function Render_Policy_Diff
     (Left_Name, Right_Name : String; Left, Right : Ada_Quality.Policy.Quality_Policy;
      Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object; Changes : constant Node := Doc.New_Array;
      procedure Add (Name, Before, After : String) is
         Object : constant Node := Doc.New_Object;
      begin
         Doc.Insert (Object, "key", Doc.New_String (Name));
         Doc.Insert (Object, "before", Doc.New_String (Before));
         Doc.Insert (Object, "after", Doc.New_String (After));
         Doc.Append (Changes, Object);
      end Add;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("policy-diff"));
      Doc.Insert (Root, "before", Doc.New_String (Left_Name));
      Doc.Insert (Root, "after", Doc.New_String (Right_Name));
      for Key in Ada_Quality.Policy.Policy_Key loop
         if Ada_Quality.Policy.Changed (Left, Right, Key) then
            Add
              (Ada_Quality.Policy.Name (Key),
               Ada_Quality.Policy.Value_Image (Left, Key),
               Ada_Quality.Policy.Value_Image (Right, Key));
         end if;
      end loop;
      Doc.Insert (Root, "changes", Changes);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Policy_Diff;
