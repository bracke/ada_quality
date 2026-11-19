separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_policy_test justification=one-component-fixture-matrix
procedure Run_Policy_Test is
begin
declare
   Path : constant String := Fixture_Root & "/policy_test.toml";
   File : Ada.Text_IO.File_Type;
   Loaded : Ada_Quality.Policy.Load_Result;
begin
   if Ada.Directories.Exists (Path) then Ada.Directories.Delete_File (Path); end if;
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (not Loaded.Success, "a missing policy returns a structured load failure");
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "# resource policy");
   Ada.Text_IO.Put_Line (File, "coverage_minimum_basis_points = 9000");
   Ada.Text_IO.Put_Line (File, "maximum_source_lines = 800");
   Ada.Text_IO.Put_Line (File, "maximum_complexity = 12");
   Ada.Text_IO.Put_Line (File, "process_timeout_seconds = 30");
   Ada.Text_IO.Put_Line (File, "maximum_output_bytes = 4096");
   Ada.Text_IO.Put_Line (File, "require_clean_worktree = true");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (Loaded.Success, "valid policy loads");
   Assert (Loaded.Value.Maximum_Source_Lines = 800, "policy values are decoded");
   declare
      Base : constant Ada_Quality.Policy.Quality_Policy := Loaded.Value;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      Ada.Text_IO.Put_Line (File, "maximum_complexity = 7");
      Ada.Text_IO.Close (File);
      Loaded := Ada_Quality.Policy.Load_Overlay (Path, Base);
      Assert
        (Loaded.Success and then Loaded.Value.Maximum_Complexity = 7 and then
         Loaded.Value.Maximum_Source_Lines = 800,
         "partial policy overlays replace only explicitly supplied values");
   end;
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "maximum_source_lines = 700 # bounded source size");
   Ada.Text_IO.Put_Line (File, "require_clean_worktree = false # explicit TOML boolean");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (Loaded.Success and then Loaded.Value.Maximum_Source_Lines = 700 and then
     not Loaded.Value.Require_Clean_Worktree,
     "policy parsing accepts TOML inline comments without weakening value validation");
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "[unsupported]");
   Ada.Text_IO.Put_Line (File, "maximum_complexity = 12");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (not Loaded.Success, "unsupported TOML sections are rejected instead of ignored");
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "maximum_complexity = 12");
   Ada.Text_IO.Put_Line (File, "maximum_complexity = 13");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (not Loaded.Success, "duplicate policy keys are rejected");
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "not an assignment");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (not Loaded.Success, "malformed policy lines are rejected");
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "unknown_setting = 1");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (not Loaded.Success, "unknown policy keys are rejected");
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "maximum_complexity = ""12\""#not-a-comment""");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (not Loaded.Success,
     "quoted and escaped TOML text is scanned before invalid numeric values are rejected");
   Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
   Ada.Text_IO.Put_Line (File, "maximum_output_bytes = 16777217");
   Ada.Text_IO.Close (File);
   Loaded := Ada_Quality.Policy.Load (Path);
   Assert (not Loaded.Success, "unsafe policy resource limits are rejected");
   Ada.Directories.Delete_File (Path);
end;
end Run_Policy_Test;
