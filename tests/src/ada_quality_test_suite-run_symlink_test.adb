separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_symlink_test owner=core expires=2027-11-21 justification=one-component-fixture-matrix
procedure Run_Symlink_Test is
begin
declare
   Root       : constant String := Fixture_Root & "/symlink_test";
   Outside    : constant String := Fixture_Root & "/symlink_outside";
   Before     : Ada.Strings.Unbounded.Unbounded_String;
   With_Links : Ada.Strings.Unbounded.Unbounded_String;
   State_Before : Ada.Strings.Unbounded.Unbounded_String;
   Link_Run   : Ada_Quality.Execution.Run_Result;
   Stage      : Ada_Quality.Workspaces.Workspace;
   Other_Stage : Ada_Quality.Workspaces.Workspace;
   First_Scratch : Ada.Strings.Unbounded.Unbounded_String;
   Second_Scratch : Ada.Strings.Unbounded.Unbounded_String;
   Raised     : Boolean := False;
   Deep_Root  : constant String := Fixture_Root & "/deep_tree_test";
   Deep_Path  : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String (Deep_Root);
begin
   declare
      type Concurrent_Paths is array (Positive range 1 .. 2) of
        Ada.Strings.Unbounded.Unbounded_String;
      Paths : Concurrent_Paths;
   begin
      declare
         task type Creator (Index : Positive);
         task body Creator is
            Directory : Ada_Quality.Temporary_Directories.Temporary_Directory;
         begin
            Ada_Quality.Temporary_Directories.Create
              (Directory, "concurrent-temporary-directory-allocation");
            Paths (Index) := To_Unbounded_String
              (Ada_Quality.Temporary_Directories.Path (Directory));
            delay 0.05;
         end Creator;
         First  : Creator (1);
         Second : Creator (2);
      begin
         null;
      end;
      Assert
        (Length (Paths (1)) > 0 and then Length (Paths (2)) > 0 and then
         Paths (1) /= Paths (2),
         "concurrent temporary-directory allocations are distinct");
      Assert
        (not Project_Tools.Files.Exists (To_String (Paths (1))) and then
         not Project_Tools.Files.Exists (To_String (Paths (2))),
         "task-owned temporary directories are finalized independently");
   end;
   Project_Tools.Files.Delete_Tree (Root);
   Project_Tools.Files.Delete_Tree (Outside);
   Ada.Directories.Create_Path (Root & "/src");
   Ada.Directories.Create_Path (Root & "/alire");
   Ada.Directories.Create_Path (Outside);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/local.adb", "procedure Local is begin null; end Local;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Outside & "/outside.ads", "pragma SPARK_Mode (On);" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/alire.toml",
      "name = ""local""" & ASCII.LF & "version = ""0.1.0""" & ASCII.LF &
      "# path = ""../../../comment-is-not-a-pin""" & ASCII.LF &
      "description = """"""an unrelated multiline value" & ASCII.LF &
      "path = '../../../multiline-is-not-a-pin'""""""" & ASCII.LF &
      "[[pins]]" & ASCII.LF &
      "dependency = { ""\u0070ath"" = ""../symlink_\u006futside"" }" & ASCII.LF &
      "[configuration.values]" & ASCII.LF &
      "path = ""../../../unrelated-key-is-not-a-pin""" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Outside & "/alire.toml", "name = ""dependency""" & ASCII.LF &
      "version = ""0.1.0""" & ASCII.LF);
   Ada_Quality.Workspaces.Prepare (Stage, Root, "toml-pin-test");
   Assert (Project_Tools.Files.File_Exists
     (Ada_Quality.Workspaces.Path (Stage) & "/../symlink_outside/outside.ads"),
     "staging accepts quoted path keys and Unicode escapes in TOML basic strings");
   Ada_Quality.Workspaces.Cleanup (Stage);
   declare
      Oversized : constant String := Outside & "/oversized.bin";
      File      : Ada.Streams.Stream_IO.File_Type;
      Byte      : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 0];
   begin
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Oversized);
      Ada.Streams.Stream_IO.Set_Index
        (File,
         Ada.Streams.Stream_IO.Count
           (Ada_Quality.Resource_Limits.Maximum_Staging_File_Bytes + 1));
      Ada.Streams.Stream_IO.Write (File, Byte);
      Ada.Streams.Stream_IO.Close (File);
      Raised := False;
      begin
         Ada_Quality.Workspaces.Prepare (Stage, Root, "oversized-pin-test");
      exception
         when Ada_Quality.Workspaces.Workspace_Error => Raised := True;
      end;
      Assert (Raised, "staging enforces file-size limits across local pin dependencies");
      Ada.Directories.Delete_File (Oversized);
   end;
   Project_Tools.Files.Write_Text_File
     (Root & "/alire/alire.lock",
      "[solution.state.link]" & ASCII.LF &
      "path = '../symlink_outside'" & ASCII.LF &
      "[solution.state.release.configuration]" & ASCII.LF &
      "path = '../../../unrelated-key-is-not-a-pin'" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/alire/build_hash_inputs", "generated and stale" & ASCII.LF);
   Before := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Root));
   Link_Run := Ada_Quality.Execution.Run
     (Root, "ln",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Outside),
          Project_Tools.Processes.Argument (Root & "/src/outside")]),
      Timeout_Seconds => 2, Maximum_Bytes => 128);
   Assert (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
     "external-directory symlink fixture is created");
   Link_Run := Ada_Quality.Execution.Run
     (Root, "ln",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("-s"), Project_Tools.Processes.Argument (Root),
          Project_Tools.Processes.Argument (Root & "/src/cycle")]),
      Timeout_Seconds => 2, Maximum_Bytes => 128);
   Assert (Link_Run.Status = Ada_Quality.Execution.Completed and then Link_Run.Exit_Code = 0,
     "cyclic symlink fixture is created");
   With_Links := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Root));
   Assert (Before /= With_Links, "symbolic-link paths participate in the source identity");
   Assert (not Ada_Quality.Checks.Declares_SPARK (Root),
     "source discovery does not follow an external symbolic link");
   Project_Tools.Files.Write_Text_File
     (Outside & "/outside.ads", "pragma SPARK_Mode (Off);" & ASCII.LF);
   Assert (To_String (With_Links) = Ada_Quality.Checks.Source_Fingerprint (Root),
     "external link-target content cannot change the project fingerprint");
   begin
      Ada_Quality.Workspaces.Prepare (Stage, Root, "symlink-test");
   exception
      when Ada_Quality.Workspaces.Workspace_Error => Raised := True;
   end;
   Assert (Raised, "staging rejects symbolic links instead of following them");
   Project_Tools.Files.Delete_Tree (Root & "/src/outside");
   Project_Tools.Files.Delete_Tree (Root & "/src/cycle");
   State_Before := To_Unbounded_String (Ada_Quality.Checks.Project_State_Fingerprint (Root));
   Ada.Directories.Create_Path (Root & "/obj");
   Ada.Directories.Create_Path (Root & "/coverage");
   Project_Tools.Files.Write_Text_File (Root & "/obj/generated.o", "generated");
   Project_Tools.Files.Write_Text_File (Root & "/coverage/generated.txt", "generated");
   Project_Tools.Files.Write_Text_File (Root & "/coverage/gcov-summary.txt", "summary");
   Project_Tools.Files.Write_Text_File (Root & "/coverage/gcov-stability.txt", "stability");
   Project_Tools.Files.Write_Text_File (Root & "/loose.ali", "compiler artifact");
   Project_Tools.Files.Write_Text_File (Root & "/test.stdout", "test output");
   Project_Tools.Files.Write_Text_File (Root & "/.ada-quality.db", "assessment database");
   Assert
     (State_Before /= To_Unbounded_String (Ada_Quality.Checks.Project_State_Fingerprint (Root)),
      "generated build artifacts participate in the deterministic project-state fingerprint");
   Ada_Quality.Workspaces.Prepare (Stage, Root, "safe/test");
   Assert (Project_Tools.Files.File_Exists
     (Ada_Quality.Workspaces.Path (Stage) & "/src/local.adb"), "staging copies source files");
   Assert (Project_Tools.Files.File_Exists
     (Ada_Quality.Workspaces.Path (Stage) & "/../symlink_outside/outside.ads"),
     "staging recursively copies local pin targets without using the original dependency tree");
   Assert (not Project_Tools.Files.Exists (Ada_Quality.Workspaces.Path (Stage) & "/obj"),
     "staging excludes generated build trees");
   Assert
     (not Project_Tools.Files.File_Exists (Ada_Quality.Workspaces.Path (Stage) & "/loose.ali") and then
      not Project_Tools.Files.File_Exists (Ada_Quality.Workspaces.Path (Stage) & "/test.stdout") and then
      not Project_Tools.Files.File_Exists (Ada_Quality.Workspaces.Path (Stage) & "/.ada-quality.db"),
      "staging and source identity share generated-file exclusions");
   Assert
     (Project_Tools.Files.File_Exists
        (Ada_Quality.Workspaces.Path (Stage) & "/coverage/gcov-summary.txt") and then
      Project_Tools.Files.File_Exists
        (Ada_Quality.Workspaces.Path (Stage) & "/coverage/gcov-stability.txt") and then
      not Project_Tools.Files.File_Exists
        (Ada_Quality.Workspaces.Path (Stage) & "/coverage/generated.txt"),
      "staging retains canonical coverage evidence without copying generated coverage trees");
   Assert (Project_Tools.Files.File_Exists
     (Ada_Quality.Workspaces.Path (Stage) & "/alire/alire.lock") and then
     not Project_Tools.Files.File_Exists
       (Ada_Quality.Workspaces.Path (Stage) & "/alire/build_hash_inputs"),
     "staging retains the dependency lock but omits mutable Alire build state");
   Ada_Quality.Workspaces.Prepare (Other_Stage, Root, "safe/test");
   Raised := False;
   begin
      declare
         Escaped : constant String := Ada_Quality.Workspaces.Scratch_Path (Stage, "../escape");
      begin
         Assert (Escaped'Length = 0, "unreachable traversal result");
      end;
   exception
      when Ada_Quality.Temporary_Directories.Temporary_Directory_Error => Raised := True;
   end;
   Assert (Raised, "temporary workspace paths reject parent traversal");
   First_Scratch := To_Unbounded_String (Ada_Quality.Workspaces.Scratch_Path (Stage, "marker"));
   Second_Scratch := To_Unbounded_String (Ada_Quality.Workspaces.Scratch_Path (Other_Stage, "marker"));
   Assert (Ada_Quality.Workspaces.Path (Stage) /= Ada_Quality.Workspaces.Path (Other_Stage) and then
     First_Scratch /= Second_Scratch,
     "same-identity assessments receive distinct private workspaces");
   Project_Tools.Files.Write_Text_File (To_String (First_Scratch), "first");
   Project_Tools.Files.Write_Text_File (To_String (Second_Scratch), "second");
   declare
      Permissions : constant Ada_Quality.Execution.Run_Result := Ada_Quality.Execution.Run
        (Root, "stat",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("-c"), Project_Tools.Processes.Argument ("%a"),
             Project_Tools.Processes.Argument
               (Ada_Quality.Workspaces.Scratch_Path (Stage, "."))]),
         Timeout_Seconds => 2, Maximum_Bytes => 32);
   begin
      Assert (Permissions.Status = Ada_Quality.Execution.Completed and then
        Permissions.Exit_Code = 0 and then
        Ada.Strings.Fixed.Index (To_String (Permissions.Output), "700") > 0,
        "assessment workspaces are owner-only; observed=" & To_String (Permissions.Output));
   end;
   Ada_Quality.Workspaces.Cleanup (Stage);
   Assert (Project_Tools.Files.File_Exists (To_String (Second_Scratch)) and then
     Ada_Quality.Workspaces.Is_Active (Other_Stage),
     "cleaning one assessment cannot remove another assessment workspace");
   Ada_Quality.Workspaces.Cleanup (Other_Stage);
   Assert (not Project_Tools.Files.Exists (To_String (First_Scratch)) and then
     not Project_Tools.Files.Exists (To_String (Second_Scratch)),
     "private workspaces are removed after use");
   Raised := False;
   begin
      declare
         Inactive_Path : constant String := Ada_Quality.Workspaces.Scratch_Path (Stage, "marker");
      begin
         Assert (Inactive_Path'Length = 0, "unreachable inactive workspace path");
      end;
   exception
      when Ada_Quality.Temporary_Directories.Temporary_Directory_Error => Raised := True;
   end;
   Assert (Raised, "inactive temporary owners cannot produce relative paths");
   Project_Tools.Files.Write_Text_File
     (Root & "/alire.toml",
      "name = ""local""" & ASCII.LF & "version = ""0.1.0""" & ASCII.LF &
      "[[pins]]" & ASCII.LF &
      "dependency = { path = ""../../../etc"" }" & ASCII.LF);
   Raised := False;
   begin
      Ada_Quality.Workspaces.Prepare (Stage, Root, "escape-test");
   exception
      when Ada_Quality.Workspaces.Workspace_Error => Raised := True;
   end;
   Assert (Raised, "staging rejects local pins that escape its isolated container");
   Project_Tools.Files.Delete_Tree (Root);
   Project_Tools.Files.Delete_Tree (Outside);
   Project_Tools.Files.Delete_Tree (Deep_Root);
   for J in 1 .. 129 loop
      Append (Deep_Path, "/d" & Natural'Image (J));
   end loop;
   Ada.Directories.Create_Path (To_String (Deep_Path));
   Project_Tools.Files.Write_Text_File
     (To_String (Deep_Path) & "/leaf.adb", "procedure Leaf is begin null; end Leaf;" & ASCII.LF);
   Raised := False;
   begin
      Before := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Deep_Root));
   exception
      when Constraint_Error => Raised := True;
   end;
   Assert (Raised, "source inventory rejects trees beyond the configured depth bound");
   Project_Tools.Files.Delete_Tree (Deep_Root);
end;
end Run_Symlink_Test;
