separate (Ada_Quality.JSON_Reports)
function Render_Scan
     (Project_Id : Positive;
      Metrics    : Ada_Quality.Checks.Source_Analysis;
      Pretty     : Boolean := False) return String
   is
      Doc      : Document;
      Root     : constant Node := Doc.New_Object;
      Counts   : constant Node := Doc.New_Object;
      Findings : constant Node := Doc.New_Array;
      Violations : constant Natural :=
        Metrics.Long_Lines + Metrics.Hygiene_Errors + Metrics.Naming_Errors +
        Metrics.Oversized_Files + Metrics.Undocumented_Specs + Metrics.Broad_Handlers +
        Metrics.Complexity_Violations + Metrics.Secret_Matches + Metrics.Unsafe_Processes;

      procedure Count (Name : String; Value : Natural) is
      begin
         Doc.Insert (Counts, Name, Doc.New_Integer (Long_Long_Integer (Value)));
      end Count;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("changed-source-scan"));
      Doc.Insert (Root, "project_id", Doc.New_Integer (Long_Long_Integer (Project_Id)));
      Count ("files", Metrics.File_Count);
      Count ("lines", Metrics.Lines);
      Count ("long_lines", Metrics.Long_Lines);
      Count ("hygiene_errors", Metrics.Hygiene_Errors);
      Count ("naming_errors", Metrics.Naming_Errors);
      Count ("oversized_files", Metrics.Oversized_Files);
      Count ("undocumented_specs", Metrics.Undocumented_Specs);
      Count ("broad_handlers", Metrics.Broad_Handlers);
      Count ("complexity_violations", Metrics.Complexity_Violations);
      Count ("secret_matches", Metrics.Secret_Matches);
      Count ("unsafe_processes", Metrics.Unsafe_Processes);
      Count ("violations", Violations);
      Doc.Insert (Root, "counts", Counts);
      for Finding of Metrics.Findings loop
         declare
            Object : constant Node := Doc.New_Object;
         begin
            Doc.Insert (Object, "indicator", Doc.New_String (Image (Finding.Indicator)));
            Doc.Insert (Object, "rule", Doc.New_String (To_String (Finding.Rule)));
            Doc.Insert (Object, "severity", Doc.New_String (Severity'Image (Finding.Level)));
            Doc.Insert (Object, "message", Doc.New_String (To_String (Finding.Message)));
            Doc.Insert (Object, "path", Doc.New_String (To_String (Finding.Relative_Path)));
            Doc.Insert (Object, "line", Doc.New_Integer (Long_Long_Integer (Finding.Line)));
            Doc.Insert (Object, "fingerprint", Doc.New_String (To_String (Finding.Fingerprint)));
            Doc.Append (Findings, Object);
         end;
      end loop;
      Doc.Insert (Root, "findings", Findings);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Scan;
