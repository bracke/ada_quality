separate (Ada_Quality.JSON_Reports)
function Render_History
     (Items : Ada_Quality.Reporting.Run_Vectors.Vector;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String
   is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
      Runs : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("assessment-history"));
      for Run of Items loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Item, "assessment_id", Doc.New_Integer (Long_Long_Integer (Run.Id)));
            Doc.Insert (Item, "project_id", Doc.New_Integer (Long_Long_Integer (Run.Project_Id)));
            Doc.Insert (Item, "status", Doc.New_String (Status_Image (Run.State)));
            Doc.Insert (Item, "started_at", Doc.New_String (Ada_Quality.Reporting.Image (Run.Started_At)));
            Doc.Insert (Item, "finished_at", Doc.New_String (Ada_Quality.Reporting.Image (Run.Finished_At)));
            Doc.Insert (Item, "source_fingerprint", Doc.New_String (To_String (Run.Source_Id)));
            Doc.Insert (Item, "policy_fingerprint", Doc.New_String (To_String (Run.Policy_Id)));
            Doc.Insert (Item, "toolchain_fingerprint", Doc.New_String (To_String (Run.Toolchain_Id)));
            Doc.Append (Runs, Item);
         end;
      end loop;
      Doc.Insert (Root, "runs", Runs);
      Populate_Page (Doc, Root, Page);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_History;
