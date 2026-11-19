separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_applicability_test owner=aq expires=2099-12-31 justification=fixture-matrix
procedure Run_Applicability_Test is
begin
declare
   Root : constant String := Fixture_Root & "/spark_test";
   Path : constant String := Root & "/src/example.ads";
   Release_Manifest : constant String :=
     "name = ""example""" & ASCII.LF & "version = ""1.0.0""" & ASCII.LF &
     "description = ""fixture""" & ASCII.LF & "licenses = ""MIT""" & ASCII.LF &
     "authors = [""Example Author""]" & ASCII.LF &
     "maintainers = [""Example <example@example.invalid>""]" & ASCII.LF;
   Dependency_Manifest : constant String :=
     "# [[depends-on]] in a comment is not structure" & ASCII.LF &
     "description = ""[[depends-on]] in a string is not structure""" & ASCII.LF &
     "[[depends-on]]" & ASCII.LF & "fixture_dependency = ""^1.0""" & ASCII.LF;
   Consistent_Lock : constant String :=
     "[solution.context]" & ASCII.LF & "solved = true" & ASCII.LF &
     "note = ""[[solution.state]] is not a section""" & ASCII.LF &
     "[[solution.state]]" & ASCII.LF & "crate = ""fixture_dependency""" & ASCII.LF &
     "versions = ""^1.0""" & ASCII.LF & "transitivity = ""direct""" & ASCII.LF &
     "[[solution.state]]" & ASCII.LF & "crate = ""transitive_dependency""" & ASCII.LF &
     "versions = ""~2.0""" & ASCII.LF & "transitivity = ""direct""" & ASCII.LF;
   Inconsistent_Lock : constant String :=
     "[solution.context]" & ASCII.LF & "solved = true" & ASCII.LF &
     "[[solution.state]]" & ASCII.LF & "crate = ""fixture_dependency""" & ASCII.LF &
     "versions = ""^2.0""" & ASCII.LF & "transitivity = ""direct""" & ASCII.LF;
begin
   if Project_Tools.Files.Exists (Root) then Project_Tools.Files.Delete_Tree (Root); end if;
   Ada.Directories.Create_Path (Root & "/src");
   Assert (Ada_Quality.Checks.Valid_Release_Manifest (Release_Manifest) and then
     not Ada_Quality.Checks.Valid_Release_Manifest
       ("name = ""example""" & ASCII.LF & "version = ""1.0.0""" & ASCII.LF &
        "description = ""fixture""" & ASCII.LF & "licenses = ""MIT""" & ASCII.LF),
     "REL-03 explicitly validates the canonical Alire release metadata contract");
   Assert
     (not Ada_Quality.Checks.Valid_Release_Manifest
        ("name = ""example""" & ASCII.LF & "version = ""1.0.0""" & ASCII.LF &
         "description = ""fixture""" & ASCII.LF & "licenses = ""MIT""" & ASCII.LF &
         "authors = [""A"" ""B""]" & ASCII.LF & "maintainers = [""M""]" & ASCII.LF) and then
      not Ada_Quality.Checks.Valid_Release_Manifest
        ("name = ""example""" & ASCII.LF & "version = ""1.0.0""" & ASCII.LF &
         "description = ""fixture""" & ASCII.LF & "licenses = ""MIT""" & ASCII.LF &
         "authors = [""""]" & ASCII.LF & "maintainers = [""M""]" & ASCII.LF),
      "REL-03 rejects malformed array separators and empty release identities");
   Assert (Ada_Quality.Checks.License_Evidence (Root, Release_Manifest) =
     Ada_Quality.Checks.Metadata_Missing,
     "REL-02 distinguishes a missing license file from inconsistent evidence");
   Project_Tools.Files.Write_Text_File
     (Root & "/LICENSE",
      "MIT License" & ASCII.LF & "Permission is hereby granted, free of charge" & ASCII.LF);
   Assert (Ada_Quality.Checks.License_Evidence (Root, Release_Manifest) =
     Ada_Quality.Checks.Metadata_Matches,
     "matching Alire SPDX metadata and license text pass REL-02");
   Project_Tools.Files.Write_Text_File
     (Root & "/LICENSE", "Apache License" & ASCII.LF & "Version 2.0" & ASCII.LF);
   Assert (Ada_Quality.Checks.License_Evidence (Root, Release_Manifest) =
     Ada_Quality.Checks.Metadata_Mismatch,
     "a declared MIT license with Apache-2.0 contents is inconsistent");
   Project_Tools.Files.Write_Text_File (Root & "/LICENSE", "unrecognized license evidence" & ASCII.LF);
   Assert (Ada_Quality.Checks.License_Evidence (Root, Release_Manifest) =
     Ada_Quality.Checks.Metadata_Unsupported,
     "unrecognized license contents block rather than pass consistency");
   Project_Tools.Files.Write_Text_File
     (Root & "/LICENSE", "MIT OR Apache-2.0 WITH LLVM-exception" & ASCII.LF);
   Assert
     (Ada_Quality.Checks.License_Evidence
        (Root,
         Ada.Strings.Fixed.Replace_Slice
           (Release_Manifest,
            Ada.Strings.Fixed.Index (Release_Manifest, "MIT"),
            Ada.Strings.Fixed.Index (Release_Manifest, "MIT") + 2,
            "MIT OR Apache-2.0 WITH LLVM-exception")) = Ada_Quality.Checks.Metadata_Matches,
      "supported SPDX OR/WITH expressions match explicit repository license evidence");
   Assert
     (Ada_Quality.Checks.Dependency_Consistency
        (Dependency_Manifest, Consistent_Lock) = Ada_Quality.Checks.Dependency_Consistent and then
      Ada_Quality.Checks.Dependency_Consistency
        (Dependency_Manifest, Inconsistent_Lock) = Ada_Quality.Checks.Dependency_Inconsistent and then
      Ada_Quality.Checks.Dependency_Consistency
        (Dependency_Manifest, "") = Ada_Quality.Checks.Dependency_Unavailable,
      "DEP-03 independently detects a solved lock whose direct constraint differs from the manifest");
   Project_Tools.Files.Write_Text_File
     (Path,
      "--  SPARK_Mode in a comment" & ASCII.LF &
      "package Example is" & ASCII.LF &
      "   Label : constant String := ""SPARK_Mode"";" & ASCII.LF &
      "end Example;" & ASCII.LF);
   Assert (not Ada_Quality.Checks.Declares_SPARK (Root),
     "comments and string literals do not declare SPARK");
   Project_Tools.Files.Write_Text_File
     (Path,
      "package Example is" & ASCII.LF &
      "   Not_SPARK_Mode : constant Boolean := False;" & ASCII.LF &
      "end Example;" & ASCII.LF);
   Assert (not Ada_Quality.Checks.Declares_SPARK (Root),
     "SPARK applicability requires an exact language token");
   Project_Tools.Files.Write_Text_File
     (Path,
      "pragma SPARK_Mode (On);" & ASCII.LF &
      "package Example is end Example;" & ASCII.LF);
   Assert (Ada_Quality.Checks.Declares_SPARK (Root), "SPARK pragma is detected in Ada code");
   Project_Tools.Files.Write_Text_File (Path, "package Example is end Example;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/spark.adc", "pragma SPARK_Mode (On);" & ASCII.LF);
   Assert (Ada_Quality.Checks.Declares_SPARK (Root),
     "project configuration pragmas make SPARK proof applicable");
   Assert
     (Ada_Quality.Checks.Classify_Proof_Applicability
        (SPARK_Declared => True, Project_Available => False) =
        Ada_Quality.Checks.Proof_Blocked and then
      Ada_Quality.Checks.Classify_Proof_Applicability
        (SPARK_Declared => False, Project_Available => False) =
        Ada_Quality.Checks.Proof_Not_Applicable and then
      Ada_Quality.Checks.Classify_Proof_Applicability
        (SPARK_Declared => True, Project_Available => True) = Ada_Quality.Checks.Proof_Ready,
      "SPARK without a usable GPR is blocked, not classified as inapplicable");
   Assert (Ada_Quality.Checks.Test_Project_File (Root) = "" and then
     Ada_Quality.Checks.Test_Suite_Executable (Root) = "",
     "a project without a tests crate has no test suite");
   Ada.Directories.Create_Path (Root & "/tests");
   Project_Tools.Files.Write_Text_File
     (Root & "/tests/alire.toml",
      "name = ""example_tests""" & ASCII.LF &
      "executables = [""example_suite"", ""example_tool""]  # the suite comes first" & ASCII.LF);
   Assert (Ada_Quality.Checks.Test_Project_File (Root) = Root & "/tests/example_tests.gpr",
     "the tests project defaults to the tests crate's name");
   Assert (Ada_Quality.Checks.Test_Suite_Executable (Root) = Root & "/tests/bin/example_suite",
     "the suite is the tests crate's first executable");
   Project_Tools.Files.Write_Text_File
     (Root & "/tests/suite.gpr", "project Suite is end Suite;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/tests/alire.toml",
      "name = ""example_tests""" & ASCII.LF & "project-files = [""suite.gpr""]" & ASCII.LF &
      "executables = [""top_level_suite""]" & ASCII.LF &
      "[tool.fixture]" & ASCII.LF & "project-files = [""wrong.gpr""]" & ASCII.LF &
      "executables = [""wrong_suite""]" & ASCII.LF);
   Assert (Ada_Quality.Checks.Test_Project_File (Root) = Root & "/tests/suite.gpr",
     "only the top-level project-files array names the tests project");
   Assert (Ada_Quality.Checks.Test_Suite_Executable (Root) = Root & "/tests/bin/top_level_suite",
     "only the top-level executables array names the test suite");
   Project_Tools.Files.Write_Text_File
     (Root & "/tests/alire.toml",
      "name = ""example_tests""" & ASCII.LF & "[tool.fixture]" & ASCII.LF &
      "project-files = [""wrong.gpr""]" & ASCII.LF &
      "executables = [""wrong_suite""]" & ASCII.LF);
   Assert (Ada_Quality.Checks.Test_Project_File (Root) = Root & "/tests/example_tests.gpr" and then
     Ada_Quality.Checks.Test_Suite_Executable (Root) = Root & "/tests/bin/example_tests",
     "nested arrays cannot impersonate absent top-level project and executable declarations");
   Assert (Ada_Quality.Checks.Dedicated_Proof_Projects (Root)'Length = 0,
     "a project without spark*.gpr files proves its main project");
   Project_Tools.Files.Write_Text_File
     (Root & "/spark_b.gpr", "project Spark_B is end Spark_B;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/spark_a.gpr", "project Spark_A is end Spark_A;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/example.gpr", "project Example is end Example;" & ASCII.LF);
   declare
      Proofs : constant Project_Tools.Files.Path_List := Ada_Quality.Checks.Dedicated_Proof_Projects (Root);
   begin
      Assert (Proofs'Length = 2 and then
        Ada.Strings.Unbounded.To_String (Proofs (Proofs'First)) = Root & "/spark_a.gpr" and then
        Ada.Strings.Unbounded.To_String (Proofs (Proofs'Last)) = Root & "/spark_b.gpr",
        "dedicated proof projects are found in name order");
   end;
   Ada.Directories.Create_Path (Root & "/bin");
   declare
      Chunk : constant String (1 .. 1_024 * 1_024) := [others => 'x'];
      Large : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (Large, Ada.Text_IO.Out_File, Root & "/bin/large");
      for Megabyte in 1 .. 65 loop
         Ada.Text_IO.Put (Large, Chunk);
      end loop;
      Ada.Text_IO.Close (Large);
   end;
   Assert (Ada_Quality.Checks.Project_State_Fingerprint (Root)'Length = 16 + 1 + 16,
     "artifacts larger than the source-file limit are hashed as a stream");
   Project_Tools.Files.Delete_Tree (Root);
end;
end Run_Applicability_Test;
