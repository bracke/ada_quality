separate (Ada_Quality.CLI)
function Run_Check
  (Store : in out Ada_Quality.Storage.Store;
   Policy_Path : String) return Natural
is
   Loaded : constant Ada_Quality.Policy.Load_Result := Ada_Quality.Policy.Load (Policy_Path);
   Exit_Code : Natural := 0;
   JSON_Mode : constant Boolean :=
     (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--json");
   All_Mode : constant Boolean :=
     (for some J in 1 .. Ada.Command_Line.Argument_Count => Argument (J) = "--all");
   Batch_Mode : constant Boolean := JSON_Mode and then All_Mode;
   Outcomes : Ada_Quality.JSON.Batch_Outcome_Vectors.Vector;

   procedure Check_Project (Project : Ada_Quality.Storage.Project_Info) is
      Run_Id : Natural := 0;
      Value  : Assessment;
      Source : Ada.Strings.Unbounded.Unbounded_String;

      procedure Interrupt_Project (Error : Ada.Exceptions.Exception_Occurrence) is
         Message : constant String :=
           (if Ada.Exceptions.Exception_Message (Error)'Length > 0
            then Ada.Exceptions.Exception_Message (Error)
            else Ada.Exceptions.Exception_Name (Error));
         Reason : constant String := "project assessment failed: " & Message;
      begin
         Ada_Quality.Storage.Interrupt_Assessment (Store, Positive (Run_Id), Reason);
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            "project" & Positive'Image (Project.Id) & " assessment interrupted: " & Message);
         if Batch_Mode then
            Outcomes.Append
              (Ada_Quality.JSON.Batch_Outcome'
                 (Project_Id => Project.Id, Assessment_Id => Run_Id,
                  Status => Ada_Quality.JSON.Batch_Interrupted,
                  Diagnostic => To_Unbounded_String (Reason), Value => <>));
         end if;
         Exit_Code := Natural'Max (Exit_Code, 3);
      end Interrupt_Project;
   begin
      begin
         Source := To_Unbounded_String
           (Ada_Quality.Checks.Source_Fingerprint (To_String (Project.Path)));
      exception
         when Error : others =>  --  AQ: project-local fingerprint boundary
            Run_Id := Ada_Quality.Storage.Start_Assessment
              (Store, Project.Id, "source-fingerprint-unavailable",
               Ada_Quality.Policy.Fingerprint (Loaded.Value));
            Interrupt_Project (Error);
            return;
      end;
      Run_Id := Ada_Quality.Storage.Start_Assessment
        (Store, Project.Id, To_String (Source), Ada_Quality.Policy.Fingerprint (Loaded.Value));
      begin
         Value := Ada_Quality.Checks.Assess
           (Project.Id, To_String (Project.Path), Loaded.Value,
            Coverage_Evidence_Enabled =>
              not Ada.Environment_Variables.Exists
                ("ADA_QUALITY_INTERNAL_DISABLE_COVERAGE_EVIDENCE"));
      exception
         when Error : others =>  --  AQ: project-local assessment boundary
            Interrupt_Project (Error);
            return;
      end;
      Value.Id := Run_Id;
      if Ada_Quality.Storage.Publish (Store, Value) /= Run_Id then
         raise Ada_Quality.Storage.Storage_Error with
           "assessment publication changed its identifier";
      end if;
      Exit_Code := Natural'Max (Exit_Code, Result_Exit (Value));
      if Batch_Mode then
         Outcomes.Append
           (Ada_Quality.JSON.Batch_Outcome'
              (Project_Id => Project.Id, Assessment_Id => Run_Id,
               Status => Ada_Quality.JSON.Batch_Completed,
               Diagnostic => Null_Unbounded_String, Value => Value));
      elsif JSON_Mode then
         Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render (Value, Pretty => True));
      else
         Print_Assessment (Value);
      end if;
   end Check_Project;

   function Project_Id return Positive is
   begin
      return Positive'Value (Option ("--project", ""));
   exception
      when Constraint_Error =>
         raise Usage_Error with "a positive project ID is required";
   end Project_Id;
begin
   if not Loaded.Success then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, To_String (Loaded.Error));
      return 2;
   elsif Option ("--project", "") /= "" then
      declare
         Project : constant Ada_Quality.Storage.Project_Info :=
           Ada_Quality.Storage.Project (Store, Project_Id);
      begin
         if Project.Removed or else not Project.Enabled then
            raise Usage_Error with "project is not enabled";
         end if;
         Check_Project (Project);
      end;
   elsif All_Mode then
      for Project of Ada_Quality.Storage.Projects (Store) loop
         if Project.Enabled and then not Project.Removed then
            Check_Project (Project);
         end if;
      end loop;
      if Batch_Mode then
         Ada.Text_IO.Put_Line (Ada_Quality.JSON.Render_Batch (Outcomes, Pretty => True));
      end if;
   else
      raise Usage_Error with "check requires --all or --project ID";
   end if;
   return Exit_Code;
end Run_Check;
