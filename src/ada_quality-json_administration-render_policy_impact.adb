separate (Ada_Quality.JSON_Administration)
function Render_Policy_Impact
     (Before_Name, After_Name : String; Items : Policy_Impact_Vectors.Vector;
      Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object; Projects : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("policy-impact"));
      Doc.Insert (Root, "before", Doc.New_String (Before_Name));
      Doc.Insert (Root, "after", Doc.New_String (After_Name));
      for Item of Items loop
         declare Object : constant Node := Doc.New_Object; Keys, Indicators : constant Node := Doc.New_Array; begin
            Doc.Insert (Object, "project_id", Doc.New_Integer (Long_Long_Integer (Item.Project_Id)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Item.Path)));
            Doc.Insert
              (Object, "before_fingerprint", Doc.New_String (To_String (Item.Before_Fingerprint)));
            Doc.Insert (Object, "after_fingerprint", Doc.New_String (To_String (Item.After_Fingerprint)));
            for Key of Item.Keys loop Doc.Append (Keys, Doc.New_String (To_String (Key))); end loop;
            for Indicator of Item.Indicators loop
               Doc.Append (Indicators, Doc.New_String (To_String (Indicator)));
            end loop;
            Doc.Insert (Object, "keys", Keys); Doc.Insert (Object, "indicators", Indicators);
            Doc.Append (Projects, Object);
         end;
      end loop;
      Doc.Insert (Root, "projects", Projects);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Policy_Impact;
