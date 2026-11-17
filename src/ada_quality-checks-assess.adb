separate (Ada_Quality.Checks)
--  AQ-WAIVER: SRC-03 target=state_after_run justification=coordinator-retains-one-evidence-boundary
function Assess
  (Project_Id : Natural;
   Root       : String;
   Policy     : Ada_Quality.Policy.Quality_Policy;
   Coverage_Evidence_Enabled : Boolean := True) return Assessment
is
   Result       : Assessment;
   Metrics      : Source_Analysis;
   Manifest     : constant String := Project_Tools.Files.Join (Root, "alire.toml");
   Manifest_Data : constant String :=
     (if Project_Tools.Files.File_Exists (Manifest)
      then Project_Tools.Files.Read_Raw_File (Manifest) else "");
   GPR           : constant String :=
     Project_Tools.Files.Find_File (Root, Ada.Directories.Simple_Name (Root) & ".gpr");
   Any_GPR       : constant Project_Tools.Files.Path_List :=
     Project_Tools.Files.List_Tree
       (Root, "*.gpr", Ada_Quality.Project_Inventory.Excluded_Source_Directories);
   function Selected_Project_Files return Text_Vectors.Vector is
      Result : Text_Vectors.Vector := Manifest_Project_Files (Root, Manifest_Data);
      Name   : constant Project_Tools.TOML.String_Parse_Result :=
        Project_Tools.TOML.Parse_String_After (Manifest_Data, "name", Manifest_Data'First);
   begin
      if Result.Is_Empty and then Name.Status = Project_Tools.TOML.Parsed_String then
         declare
            Named_GPR : constant String := Project_Tools.Files.Find_File
              (Root, To_String (Name.Value) & ".gpr");
         begin
            if Named_GPR'Length > 0 then Result.Append (To_Unbounded_String (Named_GPR)); end if;
         end;
      end if;
      if Result.Is_Empty and then GPR'Length > 0 then
         Result.Append (To_Unbounded_String (GPR));
      elsif Result.Is_Empty and then Any_GPR'Length > 0 then
         Result.Append (Any_GPR (Any_GPR'First));
      end if;
      return Result;
   end Selected_Project_Files;
   Project_GPRs  : constant Text_Vectors.Vector := Selected_Project_Files;
   Checker_A     : constant String := Project_Tools.Files.Join (Root, "tools/bin/check_all");
   Checker_B     : constant String := Project_Tools.Files.Join (Root, "bin/check_all");
   Checker_C     : constant String := Project_Tools.Files.Join (Root, "tests/bin/check_all");
   --  The first release checker present, in this precedence order, or empty when none exists. The tests-crate
   --  location serves projects whose tooling lives entirely in their tests crate.
   Release_Checker : constant String :=
     (if Project_Tools.Files.File_Exists (Checker_A) then Checker_A
      elsif Project_Tools.Files.File_Exists (Checker_B) then Checker_B
      elsif Project_Tools.Files.File_Exists (Checker_C) then Checker_C
      else "");
   Test_Manifest : constant String := Project_Tools.Files.Join (Root, "tests/alire.toml");
   Coverage_File : constant String := Project_Tools.Files.Join (Root, "coverage/gcov-summary.txt");
   Before        : constant String := Source_Fingerprint (Root);
   Build_Run, Validation_Run, Warning_Run, Test_Build_Run, Test_Run_1, Test_Run_2,
     Toolchain_Run : Ada_Quality.Execution.Run_Result;
   Release_Run, Proof_Run, Doc_Run : Ada_Quality.Execution.Run_Result;
   Git_Before, Git_After : Ada_Quality.Execution.Run_Result;
   Has_SPARK : Boolean := False;
   Stage : Ada_Quality.Workspaces.Workspace;
   Execution_Root : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String (Root);
   Test_Artifact_1, Test_Artifact_2 : Ada.Strings.Unbounded.Unbounded_String;

   procedure Add (Item : Indicator_Result) is
   begin
      pragma Assert (Is_Valid (Item));
      Result.Results.Append (Item);
   end Add;

   function Present (Condition : Boolean; Id : Indicator_Id; Good, Bad, Evidence : String)
     return Indicator_Result is
     (if Condition then Passed (Id, Good, Evidence) else Violated (Id, Bad, Evidence));

   function Integer_Result
     (Condition : Boolean;
      Id        : Indicator_Id;
      Good, Bad : String;
      Evidence  : String;
      Value     : Natural) return Indicator_Result
   is
      Item : Indicator_Result := Present (Condition, Id, Good, Bad, Evidence);
   begin
      Item.Measurement :=
        (Kind => Integer_Value, Integer_Data => Long_Long_Integer (Value));
      for Finding of Metrics.Findings loop
         if Finding.Indicator = Id and then
           (not Condition or else To_String (Finding.Rule) = "review-waiver")
         then
            if not Condition then
               if Item.Findings.Length = 1 and then
                 Length (Item.Findings.First_Element.Relative_Path) = 0
               then
                  Item.Findings.Clear;
               end if;
            end if;
            Item.Findings.Append (Finding);
         end if;
      end loop;
      return Item;
   end Integer_Result;

   function Execute
     (Label     : String;
      Directory : String;
      Name      : String;
      Arguments : Project_Tools.Processes.Argument_Vectors.Vector)
      return Ada_Quality.Execution.Run_Result
   is
      Run : constant Ada_Quality.Execution.Run_Result := Run_Tool (Directory, Name, Arguments, Policy);
   begin
      Result.Executions.Append
        (Tool_Execution'
           (Tool => To_Unbounded_String (Label), Command => Run.Command,
            Status =>
              (case Run.Status is
                 when Ada_Quality.Execution.Completed => Tool_Completed,
                 when Ada_Quality.Execution.Timed_Out => Tool_Timed_Out,
                 when Ada_Quality.Execution.Spawn_Error => Tool_Spawn_Error),
            Exit_Code => Run.Exit_Code, Output_Digest => Run.Output_Digest,
            Output_Bytes => Run.Output_Bytes, Truncated => Run.Truncated));
      return Run;
   end Execute;

   procedure Measure_Build is
   begin
   Result.Project_Id := Project_Id;
   Result.Project_Path := To_Unbounded_String (Root);
   Result.Source_Fingerprint := To_Unbounded_String (Before);
   Result.Policy_Fingerprint := To_Unbounded_String (Ada_Quality.Policy.Fingerprint (Policy));
   Result.Toolchain_Fingerprint := To_Unbounded_String (Unavailable_Toolchain_Fingerprint);
   Metrics := Analyze_Source (Root, Policy);
   Ada_Quality.Workspaces.Prepare
     (Stage, Root, Ada.Strings.Fixed.Trim (Natural'Image (Project_Id), Ada.Strings.Both));
   Execution_Root := To_Unbounded_String (Ada_Quality.Workspaces.Path (Stage));
   if Policy.Require_Clean_Worktree then
      Git_Before := Execute
        ("git-status-before", Root, Ada_Quality.Tools.Program (Ada_Quality.Tools.Git),
         Args ([Project_Tools.Processes.Argument ("-C"),
         Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("status"),
         Project_Tools.Processes.Argument ("--porcelain"),
         Project_Tools.Processes.Argument ("--untracked-files=all")]));
   end if;

   Add (Present (Project_Tools.Files.File_Exists (Manifest) and then Valid_Manifest (Manifest_Data), STR_01,
     "valid Alire manifest present", "missing or malformed alire.toml", Manifest));
   Add (Present (Any_GPR'Length > 0, STR_02, "GPR project present", "missing GPR project", Root));
   Add (Present (Project_Tools.Files.Directory_Exists (Project_Tools.Files.Join (Root, "src")), STR_03,
     "standard src layout present", "missing src directory", Root));
   Add (Present (Project_Tools.Files.File_Exists (Test_Manifest), STR_04,
     "test subcrate present", "missing tests/alire.toml", Test_Manifest));
   Add (Present (Release_Checker'Length > 0, STR_05, "release checker present", "missing release checker", Root));

   if Project_Tools.Files.File_Exists (Manifest) and then Valid_Manifest (Manifest_Data) and then
     Any_GPR'Length > 0
   then
      Build_Run := Execute
        ("alire-build", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
         Args ([Project_Tools.Processes.Argument ("build")]));
      Validation_Run := Execute
        ("alire-validation-build", To_String (Execution_Root),
         Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
         Args ([Project_Tools.Processes.Argument ("build"),
         Project_Tools.Processes.Argument ("--validation"), Project_Tools.Processes.Argument ("--"),
         Project_Tools.Processes.Argument ("-f")]));
      for Index in Project_GPRs.First_Index .. Project_GPRs.Last_Index loop
         declare
            Original_Project : constant String := Project_Tools.Files.Join
              (To_String (Execution_Root), Relative (Root, To_String (Project_GPRs (Index))));
            Original_Name : constant String := GPR_Project_Name (Original_Project);
            Inherited_Switches : constant String :=
              (if GPR_Has_Compiler_Package (Original_Project)
               then Original_Name & ".Compiler'Default_Switches (""Ada"") & "
               else "");
            Suffix : constant String := Ada.Strings.Fixed.Trim (Positive'Image (Index), Ada.Strings.Both);
            Wrapper_Name : constant String := "Ada_Quality_Warning_Gate_" & Suffix;
            Warning_Project : constant String := Ada_Quality.Workspaces.Scratch_Path
              (Stage, "ada_quality_warning_gate_" & Suffix & ".gpr");
            Current_Run : Ada_Quality.Execution.Run_Result;
         begin
            if Original_Name'Length = 0 then
               raise Constraint_Error with "cannot determine GPR project name: " & Original_Project;
            end if;
            Project_Tools.Files.Write_Text_File
              (Warning_Project,
               "project " & Wrapper_Name & " extends """ & GPR_String (Original_Project) & """ is" &
               Ada.Characters.Latin_1.LF &
               "   package Compiler is" & Ada.Characters.Latin_1.LF &
               "      for Default_Switches (""Ada"") use " & Inherited_Switches &
               "(""-gnatwa"", ""-gnatwe"");" &
               Ada.Characters.Latin_1.LF &
               "   end Compiler;" & Ada.Characters.Latin_1.LF &
               "end " & Wrapper_Name & ";" & Ada.Characters.Latin_1.LF);
            Current_Run := Execute
              ("compiler-warning-build-" & Suffix, To_String (Execution_Root),
               Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
               Args ([Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
               Project_Tools.Processes.Argument ("gprbuild"), Project_Tools.Processes.Argument ("-P"),
               Project_Tools.Processes.Argument (Warning_Project), Project_Tools.Processes.Argument ("-p"),
               Project_Tools.Processes.Argument ("-f")]));
            if Index = Project_GPRs.First_Index or else
              (Warning_Run.Status = Ada_Quality.Execution.Completed and then Warning_Run.Exit_Code = 0 and then
               (Current_Run.Status /= Ada_Quality.Execution.Completed or else Current_Run.Exit_Code /= 0))
            then
               Warning_Run := Current_Run;
            end if;
         end;
      end loop;
      Toolchain_Run := Execute
        ("gnat-toolchain", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
         Args ([Project_Tools.Processes.Argument ("exec"),
         Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("gnatls"),
         Project_Tools.Processes.Argument ("--version")]));
      if Toolchain_Identified (Toolchain_Run) then
         Result.Toolchain_Fingerprint := Result.Executions.Last_Element.Output_Digest;
      end if;
      Add (Tool_Result (BLD_01, Build_Run, "project builds", "project build failed"));
      Add (Tool_Result (BLD_02, Validation_Run, "validation build passes", "validation build failed"));
      Add (Tool_Result (BLD_03, Warning_Run, "compiler warnings gate passes", "compiler warnings gate failed"));
      Add
        (Inspected_Output_Result
           (BLD_04, Toolchain_Run, Contains (To_String (Toolchain_Run.Output), "GNAT"),
            "Alire GNAT toolchain identified", "toolchain output did not identify GNAT"));
   else
      Add (Blocked_Result (BLD_01, "build prerequisites unavailable", "requires STR-01 and STR-02"));
      Add (Blocked_Result (BLD_02, "build prerequisites unavailable", "requires BLD-01"));
      Add (Blocked_Result (BLD_03, "build prerequisites unavailable", "requires BLD-01"));
      Add (Blocked_Result (BLD_04, "toolchain prerequisites unavailable", "requires STR-01 and STR-02"));
   end if;

   end Measure_Build;

   procedure Measure_Tests is
      Test_Directory : constant String := Project_Tools.Files.Join
        (To_String (Execution_Root), "tests");
      Test_Project : constant String := Test_Project_File (To_String (Execution_Root));
      Test_Binary : constant String := Test_Suite_Executable (To_String (Execution_Root));
      Baseline_Directory : constant String :=
        Ada_Quality.Workspaces.Scratch_Path (Stage, "determinism-baseline");
      Artifact_Error : Ada.Strings.Unbounded.Unbounded_String;

      --  Fingerprint the project state after a test run. A project whose artifacts exceed the fingerprint limits
      --  cannot show deterministic artifacts; that blocks TST-04 instead of aborting the assessment.
      function State_After_Run return Ada.Strings.Unbounded.Unbounded_String is
      begin
         return To_Unbounded_String (Project_State_Fingerprint (To_String (Execution_Root)));
      exception
         when Error : Constraint_Error =>
            declare
               Message : constant String := Ada.Exceptions.Exception_Message (Error);
            begin
               if Message'Length < 8 or else Message (Message'First .. Message'First + 7) /= "project " then
                  raise;
               end if;
               Artifact_Error := To_Unbounded_String (Message);
               return Null_Unbounded_String;
            end;
      end State_After_Run;
   begin
   if Project_Tools.Files.File_Exists (Test_Manifest) and then
     Build_Run.Status = Ada_Quality.Execution.Completed and then Build_Run.Exit_Code = 0
   then
      Test_Build_Run := Execute
        ("aunit-build", Test_Directory, Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
         Args ([Project_Tools.Processes.Argument ("exec"),
         Project_Tools.Processes.Argument ("--"),
         Project_Tools.Processes.Argument ("gprbuild"),
         Project_Tools.Processes.Argument ("-P"),
         Project_Tools.Processes.Argument (Test_Project),
         Project_Tools.Processes.Argument ("-p"),
         Project_Tools.Processes.Argument ("-j0")]));
      if Test_Build_Run.Status = Ada_Quality.Execution.Completed and then Test_Build_Run.Exit_Code = 0 then
         Copy_State_Tree (To_String (Execution_Root), Baseline_Directory);
         Test_Run_1 := Execute
           ("aunit-first", Test_Directory, Test_Binary, Project_Tools.Processes.No_Arguments);
         Test_Artifact_1 := State_After_Run;
         Project_Tools.Files.Delete_Tree (To_String (Execution_Root));
         Copy_State_Tree (Baseline_Directory, To_String (Execution_Root));
         Test_Run_2 := Execute
           ("aunit-second", Test_Directory, Test_Binary, Project_Tools.Processes.No_Arguments);
         Test_Artifact_2 := State_After_Run;
         Add (Tool_Result (TST_01, Test_Run_1, "AUnit suite passes", "AUnit suite failed"));
      else
         Test_Run_1 := Test_Build_Run;
         Test_Run_2 := Test_Build_Run;
         Add (Tool_Result (TST_01, Test_Build_Run, "AUnit suite builds", "AUnit suite build failed"));
      end if;
      Add (Integer_Result (Metrics.Test_Registrations > 0, TST_02,
        "registered tests found", "no AUnit registrations found", "Register_Routine scan",
        Metrics.Test_Registrations));
      if Length (Artifact_Error) > 0 then
         Add (Blocked_Result (TST_04, "project artifacts could not be fingerprinted", To_String (Artifact_Error)));
      elsif Test_Run_1.Truncated or else Test_Run_2.Truncated then
         Add
           (Blocked_Result
              (TST_04, "test output was truncated before determinism could be established",
               "both complete normalized outputs are required"));
      else
         Add (Present (Test_Run_1.Status = Ada_Quality.Execution.Completed and then Test_Run_1.Exit_Code = 0 and then
           Test_Run_2.Status = Ada_Quality.Execution.Completed and then Test_Run_2.Exit_Code = 0 and then
           Normalize_Test_Output (To_String (Test_Run_1.Output)) =
             Normalize_Test_Output (To_String (Test_Run_2.Output)) and then
           Test_Artifact_1 = Test_Artifact_2, TST_04,
           "test execution, normalized output, and artifacts are deterministic across two runs",
           "test runs differed in execution, normalized output, or project artifacts",
           "two AUnit runs restored from one post-build baseline with normalized output and state fingerprints"));
      end if;
   else
      Add (Blocked_Result (TST_01, "test subcrate unavailable", Test_Manifest));
      Add (Blocked_Result (TST_02, "test subcrate unavailable", Test_Manifest));
      Add (Blocked_Result (TST_04, "test subcrate unavailable", Test_Manifest));
   end if;

   end Measure_Tests;

   procedure Measure_Coverage is
   begin
      if not Coverage_Evidence_Enabled then
         Add (Blocked_Result
           (TST_03, "coverage evidence disabled for coverage-driver self-assessment",
            "canonical coverage evidence remains unchanged until final publication"));
      elsif Test_Run_1.Status /= Ada_Quality.Execution.Completed or else Test_Run_1.Exit_Code /= 0 then
      Add (Blocked_Result (TST_03, "coverage prerequisite test execution did not pass", "requires TST-01"));
   elsif Project_Tools.Files.File_Exists (Coverage_File) then
      declare
         Covered_Text : constant String := Project_Tools.Files.Value_Of (Coverage_File, "covered");
         Total_Text   : constant String := Project_Tools.Files.Value_Of (Coverage_File, "total");
         Coverage_Fingerprint : constant String :=
           Project_Tools.Files.Value_Of (Coverage_File, "source_fingerprint");
         Coverage_Toolchain : constant String :=
           Project_Tools.Files.Value_Of (Coverage_File, "toolchain_fingerprint");
         Coverage_Complete : constant String :=
           Lower (Project_Tools.Files.Value_Of (Coverage_File, "complete"));
         Coverage_Inventory : constant String :=
           Project_Tools.Files.Value_Of (Coverage_File, "inventory");
         Summary : constant Project_Tools.Gcov.Coverage_Summary :=
           Project_Tools.Gcov.Parse_Lines_Executed_Output
             (Project_Tools.Files.Read_Raw_File (Coverage_File));
         Covered : constant Natural :=
           (if Covered_Text'Length > 0 then Natural'Value (Covered_Text)
            else Project_Tools.Gcov.Covered_Lines (Summary));
         Total   : constant Natural :=
           (if Total_Text'Length > 0 then Natural'Value (Total_Text)
            else Project_Tools.Gcov.Total_Lines (Summary));
      begin
         if Coverage_Complete /= "true" or else Coverage_Inventory /= "gcov-production-lines-v3" then
            Add (Blocked_Result (TST_03, "coverage evidence does not claim a complete production inventory",
              "complete=true and inventory=gcov-production-lines-v3 are required"));
         elsif Coverage_Fingerprint'Length = 0 or else Coverage_Fingerprint /= Before then
            Add (Blocked_Result (TST_03, "coverage evidence does not match the assessed source",
              "expected=" & Before & " recorded=" & Coverage_Fingerprint));
         elsif Coverage_Toolchain'Length = 0 or else
           Coverage_Toolchain /= To_String (Result.Toolchain_Fingerprint)
         then
            Add (Blocked_Result (TST_03, "coverage evidence does not match the assessed toolchain",
              "expected=" & To_String (Result.Toolchain_Fingerprint) & " recorded=" & Coverage_Toolchain));
         else
            declare
               Item : Indicator_Result :=
                 Present (Coverage_Passes (Covered, Total, Policy.Coverage_Minimum_Basis_Points), TST_03,
                   "production line coverage meets policy", "production line coverage is below policy or empty",
                   Natural'Image (Covered) & "/" & Natural'Image (Total) & " lines");
            begin
               Item.Measurement :=
                 (Kind => Decimal_Value,
                  Basis_Points =>
                    (if Total = 0 then 0
                     else Long_Long_Integer (Covered) * 10_000 / Long_Long_Integer (Total)));
               Add (Item);
            end;
         end if;
      exception
         when Constraint_Error =>
            Add (Blocked_Result (TST_03, "coverage evidence is malformed", Coverage_File));
      end;
   else
      Add (Blocked_Result (TST_03, "complete production coverage evidence unavailable",
        "expected complete gcov inventory at " & Coverage_File));
   end if;

   end Measure_Coverage;

   procedure Measure_Source is
   begin
   Add (Integer_Result (Metrics.Long_Lines = 0, SRC_01,
     "source formatting passes", "source lines exceed 120 columns",
     Natural'Image (Metrics.Long_Lines) & " long lines", Metrics.Long_Lines));
   Add (Integer_Result (Metrics.Naming_Errors = 0, SRC_02,
     "source file naming passes", "source file naming violations",
     Natural'Image (Metrics.Naming_Errors) & " files", Metrics.Naming_Errors));
   Add (Integer_Result (Metrics.Complexity_Violations = 0, SRC_03,
     "complexity within policy", "complexity exceeds policy", Natural'Image (Metrics.Maximum_Complexity),
     Metrics.Maximum_Complexity));
   Add (Integer_Result (Metrics.Hygiene_Errors = 0, SRC_04,
     "source hygiene passes", "source hygiene violations",
     Natural'Image (Metrics.Hygiene_Errors) & " findings", Metrics.Hygiene_Errors));
   Add (Integer_Result (Metrics.Broad_Handlers = 0, SRC_05,
     "exception handling passes", "broad exception handlers found",
     Natural'Image (Metrics.Broad_Handlers) & " handlers", Metrics.Broad_Handlers));
   Add (Integer_Result (Metrics.Oversized_Files = 0, SRC_06,
     "source sizes within policy", "oversized source files found",
     Natural'Image (Metrics.Oversized_Files) & " files", Metrics.Oversized_Files));

   end Measure_Source;

   procedure Measure_Documentation is
   begin
   if Any_GPR'Length > 0 then
      declare
         Project_File : constant String :=
           Project_Tools.Files.Join
             (To_String (Execution_Root), Relative
                (Root, (if GPR'Length > 0 then GPR else To_String (Any_GPR (Any_GPR'First)))));
         Output_Dir : constant String := Ada_Quality.Workspaces.Scratch_Path (Stage, "gnatdoc");
      begin
         if Project_Tools.Files.Exists (Output_Dir) then
            Project_Tools.Files.Delete_Tree (Output_Dir);
         end if;
         Doc_Run := Execute
           ("gnatdoc", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
            Args ([Project_Tools.Processes.Argument ("exec"),
            Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("gnatdoc"),
            Project_Tools.Processes.Argument ("-P"), Project_Tools.Processes.Argument (Project_File),
            Project_Tools.Processes.Argument ("-O"), Project_Tools.Processes.Argument (Output_Dir),
            Project_Tools.Processes.Argument ("--warnings")]));
         declare
            Warning_Count : constant Natural :=
              Documentation_Warning_Count (To_String (Doc_Run.Output));
         begin
            if Doc_Run.Status /= Ada_Quality.Execution.Completed or else Doc_Run.Exit_Code /= 0 then
               Add
                 (Blocked_Result
                    (DOC_01, "public declaration documentation could not be evaluated",
                     To_String (Doc_Run.Command)));
            elsif Doc_Run.Truncated then
               Add
                 (Blocked_Result
                    (DOC_01, "GNATdoc diagnostics were truncated before documentation completeness was known",
                     To_String (Doc_Run.Command) & " output-truncated"));
            elsif Metrics.Spec_Count = 0 then
               Add (Violated (DOC_01, "no public specifications were available for documentation audit", Root));
            else
               Add
                 (Integer_Result
                    (Warning_Count = 0, DOC_01,
                     "every public declaration passes the GNATdoc documentation audit",
                     "GNATdoc reported undocumented public declarations",
                     Natural'Image (Warning_Count) & " undocumented declarations", Warning_Count));
            end if;
         end;
         Add
           (Inspected_Output_Result
              (DOC_02, Doc_Run, not Contains (Lower (To_String (Doc_Run.Output)), "warning:"),
               "GNATdoc generation passes without warnings", "GNATdoc reported documentation warnings"));
         if Project_Tools.Files.Exists (Output_Dir) then
            Project_Tools.Files.Delete_Tree (Output_Dir);
         end if;
      end;
   else
      Add (Blocked_Result (DOC_01, "public declaration documentation requires a GPR project", Root));
      Add (Blocked_Result (DOC_02, "GNATdoc cannot run without a GPR project", Root));
   end if;
   Add (Present (Project_Tools.Files.File_Exists (Project_Tools.Files.Join (Root, "README.md")), DOC_03,
     "required documentation present", "README.md missing", Root));

   end Measure_Documentation;

   procedure Measure_Dependencies_And_Security is
   begin
   Add (Tool_Result (DEP_01, Build_Run, "dependencies resolve", "dependency resolution/build failed"));
   Add (Present (not Matches (Local_Pin_Pattern, Without_TOML_Comments (Manifest_Data)), DEP_02,
     "manifest contains no local path pins", "manifest contains local path pins", Manifest));
   if Build_Run.Status /= Ada_Quality.Execution.Completed or else Build_Run.Exit_Code /= 0 then
      Add (Blocked_Result
        (DEP_03, "dependency consistency requires a resolved solution", "DEP-01 did not resolve successfully"));
   else
      declare
         Lock_Path : constant String := Project_Tools.Files.Join
           (To_String (Execution_Root), "alire/alire.lock");
         Status : constant Dependency_Evidence_Status :=
           (if Project_Tools.Files.File_Exists (Lock_Path)
            then Dependency_Consistency (Manifest_Data, Project_Tools.Files.Read_Raw_File (Lock_Path))
            else Dependency_Unavailable);
      begin
         case Status is
            when Dependency_Consistent =>
               Add (Passed
                 (DEP_03, "declared dependencies match the solved Alire direct-dependency state", Lock_Path));
            when Dependency_Inconsistent =>
               Add (Violated
                 (DEP_03, "declared and solved direct dependencies are inconsistent", Lock_Path));
            when Dependency_Unavailable =>
               Add (Blocked_Result
                 (DEP_03, "resolved dependency consistency evidence is unavailable", Lock_Path));
         end case;
      end;
   end if;

   Add (Integer_Result (Metrics.Secret_Matches = 0, SEC_01, "no embedded secret patterns found",
     "possible embedded secrets found", Natural'Image (Metrics.Secret_Matches) & " matches",
     Metrics.Secret_Matches));
   Add (Integer_Result (Metrics.Unsafe_Processes = 0, SEC_02, "no shell process patterns found",
     "unsafe shell process patterns found", Natural'Image (Metrics.Unsafe_Processes) & " matches",
     Metrics.Unsafe_Processes));
   declare
      Artifacts : Natural := 0;
      Links     : constant Natural := Natural (All_Links (Root).Length);
   begin
      for Path of All_Files (Root) loop
         declare
            Name : constant String := Lower (To_String (Path));
         begin
            if (Name'Length >= 2 and then Name (Name'Last - 1 .. Name'Last) = ".o") or else
              (Name'Length >= 4 and then Name (Name'Last - 3 .. Name'Last) = ".pyc")
            then Artifacts := Artifacts + 1; end if;
         end;
      end loop;
      Add (Integer_Result (Artifacts = 0 and then Links = 0, SEC_03,
        "no forbidden artifacts or symbolic links",
        "forbidden artifacts or symbolic links found",
        Natural'Image (Artifacts) & " artifacts," & Natural'Image (Links) & " links", Artifacts + Links));
   end;

   end Measure_Dependencies_And_Security;

   procedure Measure_Release is
   begin
   if Release_Checker'Length > 0 then
      declare
         Staged_Checker : constant String := Project_Tools.Files.Join
           (To_String (Execution_Root), Relative (Root, Release_Checker));
      begin
         if Project_Tools.Files.File_Exists (Staged_Checker) then
            Release_Run := Execute
              ("release-checker", To_String (Execution_Root), Staged_Checker,
               Project_Tools.Processes.No_Arguments);
            --  During coverage generation only, the staged release checker
            --  reserves exit 2 for the canonical evidence that this run is
            --  replacing. Normalize that bootstrap state so first and later
            --  same-source coverage runs exercise identical assessment paths.
            if not Coverage_Evidence_Enabled then
               Release_Run.Exit_Code :=
                 (if Release_Run.Status = Ada_Quality.Execution.Completed and then
                     Release_Run.Exit_Code = 2
                  then 0
                  else Release_Run.Exit_Code);
            end if;
            Add (Tool_Result (REL_01, Release_Run, "release checker passes", "release checker failed"));
         else
            Add (Blocked_Result (REL_01, "release checker absent from staged build", Staged_Checker));
         end if;
      end;
   else
      Add (Blocked_Result (REL_01, "release checker missing", Root));
   end if;
   case License_Evidence (Root, Manifest_Data) is
      when Metadata_Matches =>
         Add (Passed (REL_02, "declared SPDX license matches repository license", Manifest));
      when Metadata_Mismatch =>
         Add (Violated (REL_02, "declared SPDX license conflicts with repository license", Manifest));
      when Metadata_Missing =>
         Add (Violated (REL_02, "license declaration or license file is missing", Manifest));
      when Metadata_Unsupported =>
         Add (Blocked_Result (REL_02, "license evidence is unrecognized or unsupported", Manifest));
   end case;
   Add (Present (Valid_Release_Manifest (Manifest_Data), REL_03,
     "canonical Alire release manifest is complete",
     "canonical Alire release manifest fields are missing or invalid", Manifest));

   end Measure_Release;

   procedure Measure_Proof is
      Dedicated : constant Project_Tools.Files.Path_List := Dedicated_Proof_Projects (Root);

      function Prove (Project_File : String) return Ada_Quality.Execution.Run_Result is
        (Execute
           ("gnatprove", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
            Args ([Project_Tools.Processes.Argument ("exec"),
            Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("gnatprove"),
            Project_Tools.Processes.Argument ("-P"), Project_Tools.Processes.Argument (Project_File),
            Project_Tools.Processes.Argument ("--mode=prove"),
            Project_Tools.Processes.Argument ("--level=2")])));
   begin
   Has_SPARK := Declares_SPARK (Root);
   if Has_SPARK and then Dedicated'Length > 0 then
      --  Dedicated proof projects name exactly the SPARK units; each must prove.
      for Project of Dedicated loop
         Proof_Run := Prove
           (Project_Tools.Files.Join (To_String (Execution_Root), Relative (Root, To_String (Project))));
         exit when Proof_Run.Status /= Ada_Quality.Execution.Completed or else Proof_Run.Exit_Code /= 0;
      end loop;
      Add (Tool_Result (PRF_01, Proof_Run, "declared SPARK units proved", "SPARK proof failed or is incomplete"));
   elsif Has_SPARK and then Any_GPR'Length > 0 then
      declare
         Project_File : constant String :=
           Project_Tools.Files.Join
             (To_String (Execution_Root), Relative
                (Root, (if GPR'Length > 0 then GPR else To_String (Any_GPR (Any_GPR'First)))));
      begin
         Proof_Run := Prove (Project_File);
         Add (Tool_Result (PRF_01, Proof_Run, "declared SPARK units proved", "SPARK proof failed or is incomplete"));
      end;
   elsif Classify_Proof_Applicability (Has_SPARK, Project_Available => False) = Proof_Blocked then
      Add (Blocked_Result
        (PRF_01, "SPARK is declared but no usable GPR project exists",
         "GNATprove requires a selected project file"));
   else
      Add (Not_Applicable_Result (PRF_01, "no source unit declares SPARK_Mode"));
   end if;

   end Measure_Proof;

   procedure Finalize_Assessment is
   begin
   declare
      After : constant String := Source_Fingerprint (Root);
   begin
      if Before /= After then
         Add (Violated (REL_04, "assessment modified source inputs",
           "before=" & Before & " after=" & After));
      elsif not Policy.Require_Clean_Worktree then
         Add (Passed (REL_04, "source fingerprint unchanged", "clean-worktree policy disabled"));
      else
         Git_After := Execute
           ("git-status-after", Root, Ada_Quality.Tools.Program (Ada_Quality.Tools.Git),
            Args ([Project_Tools.Processes.Argument ("-C"),
            Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("status"),
            Project_Tools.Processes.Argument ("--porcelain"),
            Project_Tools.Processes.Argument ("--untracked-files=all")]));
         if Git_Before.Status /= Ada_Quality.Execution.Completed or else
           Git_After.Status /= Ada_Quality.Execution.Completed or else
           Git_Before.Exit_Code /= 0 or else Git_After.Exit_Code /= 0
         then
            Add (Blocked_Result (REL_04, "clean worktree evidence unavailable",
              "git status must succeed before and after assessment"));
         elsif Git_Before.Truncated or else Git_After.Truncated then
            Add (Blocked_Result (REL_04, "Git status output was truncated",
              "complete status output is required before and after assessment"));
         elsif Length (Git_Before.Output) > 0 or else Length (Git_After.Output) > 0 then
            Add (Violated (REL_04, "Git worktree is not clean",
              "git status reported tracked or untracked changes"));
         else
            Add (Passed (REL_04, "clean staged source remained unchanged",
              "git status clean before and after; fingerprint=" & Before));
         end if;
      end if;
      if Before = After then Result.Status := Assessment_Completed; else Result.Status := Assessment_Invalid; end if;
   end;

   end Finalize_Assessment;

begin
   Measure_Build;
   Measure_Tests;
   Measure_Coverage;
   Measure_Source;
   Measure_Documentation;
   Measure_Dependencies_And_Security;
   Measure_Release;
   Measure_Proof;
   Finalize_Assessment;

   pragma Assert (Result.Results.Length = Ada.Containers.Count_Type (Indicator_Count'Last));
   Ada_Quality.Workspaces.Cleanup (Stage);
   return Result;
exception
   when others =>  --  AQ: audited exception boundary
      Ada_Quality.Workspaces.Cleanup (Stage);
      raise;
end Assess;
