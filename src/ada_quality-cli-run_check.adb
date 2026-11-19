separate (Ada_Quality.CLI)
--  AQ-WAIVER: SRC-03 target=project_id owner=core expires=2099-12-31 justification=parallel-check-coordination-boundary
function Run_Check
  (Store : in out Ada_Quality.Storage.Store;
   Policy_Path : String) return Natural
is
   function Profile_Path return String is
      Name : constant String := Option ("--profile", "");
   begin
      if Name /= "" and then not Ada_Quality.Policy.Is_Profile_Name (Name) then
         raise Usage_Error with "--profile requires letters, digits, underscores, or hyphens";
      end if;
      return Ada_Quality.Policy.Profile_Path (Policy_Path, Name);
   end Profile_Path;

   Loaded : constant Ada_Quality.Policy.Load_Result :=
     Ada_Quality.Policy.Load (Profile_Path);
   Exit_Code : Natural := 0;
   JSON_Mode : constant Boolean := Has_Flag ("--json");
   All_Mode : constant Boolean := Has_Flag ("--all");
   Batch_Mode : constant Boolean := JSON_Mode and then All_Mode;
   Reuse_Unchanged : constant Boolean := Has_Flag ("--reuse-unchanged");
   Dry_Run : constant Boolean := Has_Flag ("--dry-run");
   Selected_Tag : constant String := Option ("--tag", "");
   Use_Project_Policy : constant Boolean := Has_Flag ("--project-policy");
   Outcomes : Ada_Quality.JSON.Batch_Outcome_Vectors.Vector;
   Selected : Ada_Quality.Storage.Project_Vectors.Vector;
   Jobs : Positive := 1;

   type Job_Result is record
      Value      : Assessment;
      Success    : Boolean := False;
      Diagnostic : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   task type Worker is
      entry Start
        (Project : Ada_Quality.Storage.Project_Info;
         Run_Id  : Positive;
         Policy  : Ada_Quality.Policy.Quality_Policy);
      entry Collect (Result : out Job_Result);
   end Worker;
   type Worker_Access is access Worker;

   task body Worker is
      Current_Project : Ada_Quality.Storage.Project_Info :=
        (Id => 1, Path => Null_Unbounded_String, Tags => Null_Unbounded_String,
         Enabled => True, Removed => False);
      Current_Run_Id : Positive := 1;
      Current_Policy : Ada_Quality.Policy.Quality_Policy := Ada_Quality.Policy.Default;
      Work_Result : Job_Result;
   begin
      accept Start
        (Project : Ada_Quality.Storage.Project_Info;
         Run_Id  : Positive;
         Policy  : Ada_Quality.Policy.Quality_Policy)
      do
         Current_Project := Project;
         Current_Run_Id := Run_Id;
         Current_Policy := Policy;
      end Start;
      begin
         Work_Result.Value := Ada_Quality.Checks.Assess
           (Current_Project.Id, To_String (Current_Project.Path), Current_Policy,
            Coverage_Evidence_Enabled =>
              not Ada.Environment_Variables.Exists
                ("ADA_QUALITY_INTERNAL_DISABLE_COVERAGE_EVIDENCE"));
         Work_Result.Value.Id := Current_Run_Id;
         Work_Result.Success := True;
      exception
         when Error : others =>
            Work_Result.Diagnostic := To_Unbounded_String
              ((if Ada.Exceptions.Exception_Message (Error)'Length > 0
                then Ada.Exceptions.Exception_Message (Error)
                else Ada.Exceptions.Exception_Name (Error)));
      end;
      accept Collect (Result : out Job_Result) do
         Result := Work_Result;
      end Collect;
   end Worker;

   function Effective_Policy
     (Project : Ada_Quality.Storage.Project_Info) return Ada_Quality.Policy.Load_Result
   is
      Override_Path : constant String :=
        To_String (Project.Path) & "/quality-policy.override.toml";
   begin
      if Use_Project_Policy and then Project_Tools.Files.File_Exists (Override_Path) then
         return Ada_Quality.Policy.Load_Overlay (Override_Path, Loaded.Value);
      end if;
      return (Success => True, Value => Loaded.Value, Error => Null_Unbounded_String);
   end Effective_Policy;

   procedure Interrupt
     (Project : Ada_Quality.Storage.Project_Info;
      Run_Id  : Positive;
      Message : String)
   is
      Reason : constant String := "project assessment failed: " & Message;
   begin
      Ada_Quality.Storage.Interrupt_Assessment (Store, Run_Id, Reason);
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
   end Interrupt;

   procedure Publish_Result
     (Project : Ada_Quality.Storage.Project_Info;
      Run_Id  : Positive;
      Result  : Job_Result) is
   begin
      if not Result.Success then
         Interrupt (Project, Run_Id, To_String (Result.Diagnostic));
      else
         if Ada_Quality.Storage.Publish (Store, Result.Value) /= Run_Id then
            raise Ada_Quality.Storage.Storage_Error with
              "assessment publication changed its identifier";
         end if;
         Exit_Code := Natural'Max (Exit_Code, Result_Exit (Result.Value));
         if Batch_Mode then
            Outcomes.Append
              (Ada_Quality.JSON.Batch_Outcome'
                 (Project_Id => Project.Id, Assessment_Id => Run_Id,
                  Status => Ada_Quality.JSON.Batch_Completed,
                  Diagnostic => Null_Unbounded_String, Value => Result.Value));
         elsif JSON_Mode then
            Emit_Document (Ada_Quality.JSON.Render (Result.Value, Pretty => True));
         else
            Print_Assessment (Result.Value);
         end if;
      end if;
   end Publish_Result;

   function Cached_Run
     (Project : Ada_Quality.Storage.Project_Info;
      Source, Policy_Id, Toolchain_Id : String) return Natural
   is
      Result : Natural := 0;
   begin
      if Toolchain_Id = "" then return 0; end if;
      for Run of Ada_Quality.Storage.History (Store, Project.Id) loop
         if To_String (Run.Status) = "completed" and then
           To_String (Run.Source_Fingerprint) = Source and then
           To_String (Run.Policy_Fingerprint) = Policy_Id and then
           To_String (Run.Toolchain_Fingerprint) = Toolchain_Id
         then
            Result := Run.Id;
         end if;
      end loop;
      return Result;
   end Cached_Run;

   procedure Reuse (Project : Ada_Quality.Storage.Project_Info; Run_Id : Positive) is
      Project_Exit : Natural := 0;
   begin
      for Row of Ada_Quality.Storage.Results (Store, Run_Id) loop
         if Ada.Strings.Fixed.Index (To_String (Row.State), "/violation") > 0 then
            Project_Exit := Natural'Max (Project_Exit, 1);
         elsif Ada.Strings.Fixed.Index (To_String (Row.State), "succeeded/") /= 1 and then
           Ada.Strings.Fixed.Index (To_String (Row.State), "not_applicable/") /= 1
         then
            Project_Exit := 3;
         end if;
      end loop;
      Exit_Code := Natural'Max (Exit_Code, Project_Exit);
      if Batch_Mode then
         Outcomes.Append
           (Ada_Quality.JSON.Batch_Outcome'
              (Project_Id => Project.Id, Assessment_Id => Run_Id,
               Status => Ada_Quality.JSON.Batch_Reused,
               Diagnostic => Null_Unbounded_String, Value => <>));
      elsif JSON_Mode then
         Emit_Document (Ada_Quality.JSON.Render_Reuse (Project.Id, Run_Id, Pretty => True));
      else
         Ada.Text_IO.Put_Line
           ("project" & Positive'Image (Project.Id) & " unchanged; reused assessment" &
            Positive'Image (Run_Id));
      end if;
   end Reuse;

   function Project_Id return Positive is
   begin
      return Positive'Value (Option ("--project", ""));
   exception
      when Constraint_Error => raise Usage_Error with "a positive project ID is required";
   end Project_Id;
begin
   if not Loaded.Success then
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, To_String (Loaded.Error));
      return 2;
   elsif Option ("--jobs", "") /= "" then
      begin
         Jobs := Positive'Value (Option ("--jobs", ""));
      exception
         when Constraint_Error => raise Usage_Error with "--jobs requires a positive count";
      end;
      if Jobs > 64 then raise Usage_Error with "--jobs must not exceed 64"; end if;
   end if;
   if Option ("--output", "") /= "" and then not JSON_Mode and then not Dry_Run then
      raise Usage_Error with "check --output requires --json";
   end if;
   if Selected_Tag /= "" and then not Ada_Quality.Storage.Is_Project_Tag_Name (Selected_Tag) then
      raise Usage_Error with "--tag requires lowercase letters, digits, hyphens, or underscores";
   end if;
   if Option ("--project", "") /= "" then
      declare
         Project : constant Ada_Quality.Storage.Project_Info :=
           Ada_Quality.Storage.Project (Store, Project_Id);
      begin
         if Project.Removed or else not Project.Enabled then
            raise Usage_Error with "project is not enabled";
         end if;
         Selected.Append (Project);
      end;
   elsif All_Mode then
      for Project of Ada_Quality.Storage.Projects (Store) loop
         if Project.Enabled and then not Project.Removed then Selected.Append (Project); end if;
      end loop;
   elsif Selected_Tag /= "" then
      for Project of Ada_Quality.Storage.Projects (Store) loop
         if Project.Enabled and then not Project.Removed and then
           Ada_Quality.Storage.Has_Project_Tag (Project, Selected_Tag)
         then
            Selected.Append (Project);
         end if;
      end loop;
   else
      raise Usage_Error with "check requires --all, --project ID, or --tag NAME";
   end if;

   declare
      type Worker_Array is array (Positive range <>) of Worker_Access;
      type Project_Array is array (Positive range <>) of Ada_Quality.Storage.Project_Info;
      type Run_Array is array (Positive range <>) of Natural;
      type Policy_Array is array (Natural range <>) of Ada_Quality.Policy.Quality_Policy;
      Workers : Worker_Array (1 .. Jobs) := [others => null];
      Projects : Project_Array (1 .. Jobs) :=
        [others => (Id => 1, Path => Null_Unbounded_String, Tags => Null_Unbounded_String,
                    Enabled => True, Removed => False)];
      Run_Ids : Run_Array (1 .. Jobs) := [others => 0];
      Policies : Policy_Array (1 .. Natural (Selected.Length));
      Next : Positive := (if Selected.Is_Empty then 1 else Selected.First_Index);
   begin
      for Index in Policies'Range loop
         declare
            Result : constant Ada_Quality.Policy.Load_Result := Effective_Policy (Selected (Index));
         begin
            if not Result.Success then raise Usage_Error with To_String (Result.Error); end if;
            Policies (Index) := Result.Value;
         end;
      end loop;
      if Dry_Run then
         declare
            Plan : Ada_Quality.JSON.Check_Plan_Vectors.Vector;
            Text : Ada.Strings.Unbounded.Unbounded_String;
         begin
            for Index in Policies'Range loop
               declare
                  Project : constant Ada_Quality.Storage.Project_Info := Selected (Index);
                  Source : constant String :=
                    Ada_Quality.Checks.Source_Fingerprint (To_String (Project.Path));
                  Policy_Id : constant String := Ada_Quality.Policy.Fingerprint (Policies (Index));
                  Toolchain : constant String := Ada_Quality.Checks.Current_Toolchain_Fingerprint
                    (To_String (Project.Path));
                  Cached : constant Natural := Cached_Run (Project, Source, Policy_Id, Toolchain);
               begin
                  Plan.Append
                    (Ada_Quality.JSON.Check_Plan_Item'
                       (Project_Id => Project.Id, Path => Project.Path,
                        Source_Fingerprint => To_Unbounded_String (Source),
                        Policy_Fingerprint => To_Unbounded_String (Policy_Id),
                        Toolchain_Fingerprint => To_Unbounded_String (Toolchain),
                        Reusable_Assessment => Cached,
                        Will_Reuse => Reuse_Unchanged and then Cached > 0));
                  Append
                    (Text, "project" & Positive'Image (Project.Id) & " " & To_String (Project.Path) &
                     " action=" & (if Reuse_Unchanged and then Cached > 0 then "reuse" else "assess") &
                     " source=" & Source & " policy=" & Policy_Id & " toolchain=" & Toolchain &
                     (if Cached > 0 then " reusable_assessment=" & Natural'Image (Cached) else "") & ASCII.LF);
               end;
            end loop;
            if JSON_Mode then
               Emit_Document (Ada_Quality.JSON.Render_Check_Plan (Plan, Pretty => True));
            else
               Emit_Document (To_String (Text));
            end if;
            return 0;
         end;
      end if;
      while not Selected.Is_Empty and then Next <= Selected.Last_Index loop
         Workers := [others => null];
         Run_Ids := [others => 0];
         for Slot in Workers'Range loop
            exit when Next > Selected.Last_Index;
            Projects (Slot) := Selected (Next);
            declare
               Current_Policy : constant Ada_Quality.Policy.Quality_Policy := Policies (Next);
               Source : Ada.Strings.Unbounded.Unbounded_String;
            begin
               begin
                  Source := To_Unbounded_String
                    (Ada_Quality.Checks.Source_Fingerprint (To_String (Projects (Slot).Path)));
               exception
                  when Error : others =>
                     Run_Ids (Slot) := Ada_Quality.Storage.Start_Assessment
                       (Store, Projects (Slot).Id, "source-fingerprint-unavailable",
                        Ada_Quality.Policy.Fingerprint (Current_Policy));
                     Interrupt
                       (Projects (Slot), Positive (Run_Ids (Slot)),
                        Ada.Exceptions.Exception_Message (Error));
               end;
               if Run_Ids (Slot) = 0 and then Reuse_Unchanged then
                  declare
                     Cached : constant Natural := Cached_Run
                       (Projects (Slot), To_String (Source),
                        Ada_Quality.Policy.Fingerprint (Current_Policy),
                        Ada_Quality.Checks.Current_Toolchain_Fingerprint
                          (To_String (Projects (Slot).Path)));
                  begin
                     if Cached > 0 then Reuse (Projects (Slot), Positive (Cached)); end if;
                     Run_Ids (Slot) := Cached;
                  end;
               end if;
               if Run_Ids (Slot) = 0 then
                  Run_Ids (Slot) := Ada_Quality.Storage.Start_Assessment
                    (Store, Projects (Slot).Id, To_String (Source),
                     Ada_Quality.Policy.Fingerprint (Current_Policy));
                  Workers (Slot) := new Worker;
                  Workers (Slot).Start
                    (Projects (Slot), Positive (Run_Ids (Slot)), Current_Policy);
               end if;
            end;
            Next := Next + 1;
         end loop;
         for Slot in Workers'Range loop
            if Workers (Slot) /= null then
               declare Result : Job_Result; begin
                  Workers (Slot).Collect (Result);
                  Publish_Result (Projects (Slot), Positive (Run_Ids (Slot)), Result);
               end;
            end if;
         end loop;
      end loop;
   end;
   if Batch_Mode then
      Emit_Document (Ada_Quality.JSON.Render_Batch (Outcomes, Pretty => True));
   end if;
   return Exit_Code;
end Run_Check;
