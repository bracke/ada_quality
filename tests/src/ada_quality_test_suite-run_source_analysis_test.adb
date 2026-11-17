separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_source_analysis_test justification=one-component-fixture-matrix
procedure Run_Source_Analysis_Test is
begin
declare
   Root   : constant String := Fixture_Root & "/source_analysis_test";
   Policy : Ada_Quality.Policy.Quality_Policy;
   Metrics : Ada_Quality.Checks.Source_Analysis;
   Long_Line : constant String := "   Value : constant String := """ &
     [1 .. 121 => 'x'] & """;";
   Other_Long_Line : constant String := "   Other : constant String := """ &
     [1 .. 121 => 'y'] & """;";
   Example_Body : constant String :=
     "procedure Example is" & ASCII.LF &
     "begin" & ASCII.LF &
     "   if Ready and then Enabled then" & ASCII.LF &
     "      null;" & ASCII.LF &
     "   elsif Waiting then" & ASCII.LF &
     "      null;" & ASCII.LF &
     "   end if;" & ASCII.LF &
     "   Label := ""password := Run_Shell"";" & ASCII.LF &
     "   -- Password := and Run_Shell are inert in comments." & ASCII.LF &
     "   Password := ""redacted"";" & ASCII.LF &
     "   Run_Shell;" & ASCII.LF &
     "   Program := Project_Tools.Processes.Argument (""bash"");" & ASCII.LF &
     "   Register_Routine;" & ASCII.LF &
     Long_Line & ASCII.LF &
     Other_Long_Line & ASCII.LF &
     "exception" & ASCII.LF &
     "   when others => null;" & ASCII.LF &
     "end Example;" & ASCII.LF;
begin
   Project_Tools.Files.Delete_Tree (Root);
   Ada.Directories.Create_Path (Root & "/src");
   Ada.Directories.Create_Path (Root & "/tests/src");
   Ada.Directories.Create_Path (Root & "/config");
   Policy.Maximum_Source_Lines := 5;
   Policy.Maximum_Complexity := 4;
   Project_Tools.Files.Write_Text_File
     (Root & "/src/Documented.ads",
      "--  Public package documentation." & ASCII.LF &
      "package Documented is" & ASCII.LF &
      "end Documented;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/undocumented.ads",
      "package Undocumented is" & ASCII.LF &
      "end Undocumented;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/example.adb",
      "--  AQ: complexity-reviewed" & ASCII.LF &
      "--  AQ-WAIVER: SRC-03 target=wrong justification=fixture rejects broad targeting" & ASCII.LF &
      Example_Body);
   Project_Tools.Files.Write_Text_File
     (Root & "/tests/src/example_tests.adb",
      "procedure Example_Tests is begin Register_Routine; end Example_Tests;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/nested.adb",
      "--  AQ-WAIVER: SRC-06 target=file justification=fixture exercises reviewed source size" & ASCII.LF &
      "--  AQ-WAIVER: SRC-03 target=wrong justification=fixture skips unrelated waiver targets" &
      ASCII.LF &
      "--  AQ-WAIVER: SRC-03 target=inner justification=fixture reviews the measured nested segment" &
      ASCII.LF &
      "procedure Nested is" & ASCII.LF &
      "   function Expression (Flag : Boolean) return Boolean is (Flag and then Ready);" & ASCII.LF &
      "   procedure Inner is" & ASCII.LF &
      "   begin" & ASCII.LF &
      "      case Value is" & ASCII.LF &
      "         when One => null;" & ASCII.LF &
      "         when others => null;" & ASCII.LF &
      "      end case;" & ASCII.LF &
      "   end Inner;" & ASCII.LF &
      "begin" & ASCII.LF &
      "   while Ready loop exit; end loop;" & ASCII.LF &
      "end Nested;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/config/example_config.ads", "package Example_Config is end Example_Config;" & ASCII.LF);
   Metrics := Ada_Quality.Checks.Analyze_Source (Root, Policy);
   Assert (Metrics.File_Count = 5 and then Metrics.Spec_Count = 2 and then
     Metrics.Production_Files = 4 and then Metrics.Test_Files = 1 and then
     Metrics.Generated_Files = 1,
     "native inventory distinguishes production, test, and generated Ada sources");
   Assert (Metrics.Naming_Errors = 1, "non-lowercase Ada file names are findings");
   declare
      Subunit_Root : constant String := Root & "/subunits";
      Subunits     : Ada_Quality.Checks.Source_Analysis;
   begin
      Ada.Directories.Create_Path (Subunit_Root & "/src");
      Project_Tools.Files.Write_Text_File
        (Subunit_Root & "/src/example-part.adb",
         "separate (Example)" & ASCII.LF & "procedure Part (Value : Integer) is" & ASCII.LF &
         "begin" & ASCII.LF &
         "   null;" & ASCII.LF & "end Part;" & ASCII.LF);
      Project_Tools.Files.Write_Text_File
        (Subunit_Root & "/src/example-wrong.adb",
         "separate (Example)" & ASCII.LF & "procedure Other is" & ASCII.LF & "begin" & ASCII.LF &
         "   null;" & ASCII.LF & "end Other;" & ASCII.LF);
      Subunits := Ada_Quality.Checks.Analyze_Source (Subunit_Root, Policy);
      Assert (Subunits.Naming_Errors = 1,
        "a subunit file is named after its parent and subunit; a mismatched subunit is a finding");
   end;
   Assert (Metrics.Undocumented_Specs = 1,
     "a standalone package documentation comment is required");
   Assert (Metrics.Maximum_Complexity = 5,
     "defined complexity covers conditionals, short circuits, alternatives, loops, " &
     "nested declarations, and expression functions");
   Assert (Metrics.Complexity_Violations > 0 and then Metrics.Review_Waivers = 2,
     "legacy and mismatched complexity markers do not waive a measured occurrence");
   Assert (Metrics.Long_Lines = 2 and then Metrics.Oversized_Files = 1,
     "line and file-size policy violations are measured");
   declare
      First_Key : Ada.Strings.Unbounded.Unbounded_String;
      Count : Natural := 0;
   begin
      for Finding of Metrics.Findings loop
         if To_String (Finding.Rule) = "line-length" then
            Count := Count + 1;
            if Count = 1 then
               First_Key := Finding.Fingerprint;
            else
               Assert (Finding.Fingerprint /= First_Key,
                 "different source contexts have different stable finding identities");
            end if;
         end if;
      end loop;
      Assert (Count = 2, "each distinct long source line remains an independently tracked finding");
   end;
   Assert (Metrics.Secret_Matches = 1 and then Metrics.Unsafe_Processes = 2,
     "credential, shell API, and shell executable patterns are detected without comment/string false positives");
   Assert (Metrics.Broad_Handlers = 1 and then Metrics.Test_Registrations = 2,
     "broad handlers and test registrations use Ada-aware source scans");
   Assert (Metrics.Findings.Length >= 7, "native violations carry structured findings");
   declare
      Changed : constant Ada_Quality.Checks.Source_Analysis :=
        Ada_Quality.Checks.Analyze_Changed_Sources
          (Root,
           [To_Unbounded_String ("src/example.adb"),
            To_Unbounded_String ("src/example.adb")],
           Policy);
      Escaped : Boolean := False;
   begin
      Assert (Changed.File_Count = 1 and then Changed.Production_Files = 1
              and then Changed.Long_Lines = 2 and then Changed.Broad_Handlers = 1,
              "change-scoped source analysis measures only the normalized explicit source set");
      Assert (Changed.Undocumented_Specs = 0 and then Changed.Test_Registrations = 1,
              "change-scoped source analysis does not import unrelated source evidence");
      begin
         Metrics := Ada_Quality.Checks.Analyze_Changed_Sources
           (Root, [To_Unbounded_String ("../outside.adb")], Policy);
      exception
         when Constraint_Error =>
            Escaped := True;
      end;
      Assert (Escaped, "change-scoped source analysis accepted a path outside the project");
   end;
   declare
      Path : constant String := Root & "/src/oversized.adb";
      File : Ada.Streams.Stream_IO.File_Type;
      Byte : constant Ada.Streams.Stream_Element_Array (1 .. 1) := [1 => 0];
      Rejected : Boolean := False;
   begin
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, Path);
      Ada.Streams.Stream_IO.Set_Index
        (File,
         Ada.Streams.Stream_IO.Count
           (Ada_Quality.Resource_Limits.Maximum_File_Bytes + 1));
      Ada.Streams.Stream_IO.Write (File, Byte);
      Ada.Streams.Stream_IO.Close (File);
      begin
         Metrics := Ada_Quality.Checks.Analyze_Changed_Sources
           (Root, [To_Unbounded_String ("src/oversized.adb")], Policy);
      exception
         when Constraint_Error => Rejected := True;
      end;
      Assert (Rejected, "change-scoped source analysis enforces the per-file byte limit");
      Ada.Directories.Delete_File (Path);
   end;
   Project_Tools.Files.Write_Text_File
     (Root & "/src/example.adb",
      "--  AQ-WAIVER: SRC-03 target=example justification=fixture reviewed this subprogram" &
      ASCII.LF & Example_Body);
   Metrics := Ada_Quality.Checks.Analyze_Source (Root, Policy);
   Assert (Metrics.Complexity_Violations = 0 and then Metrics.Review_Waivers = 3,
     "matching rule, target, and justification waive only the reviewed occurrence; violations" &
     Natural'Image (Metrics.Complexity_Violations) & ", waivers" &
     Natural'Image (Metrics.Review_Waivers));
   declare
      Visible_Waivers : Natural := 0;
   begin
      for Finding of Metrics.Findings loop
         if To_String (Finding.Rule) = "review-waiver" and then Finding.Level = Low then
            Visible_Waivers := Visible_Waivers + 1;
         end if;
      end loop;
      Assert (Visible_Waivers = 3,
        "accepted source-size and complexity waivers remain visible as low-severity evidence");
   end;
   Policy.Require_Clean_Worktree := False;
   --  A SPARK unit with a dedicated proof project: PRF-01 proves that project, which cannot pass here.
   Project_Tools.Files.Write_Text_File
     (Root & "/src/proved.ads",
      "pragma SPARK_Mode (On);" & ASCII.LF & "package Proved is end Proved;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/spark_example.gpr", "project Spark_Example is end Spark_Example;" & ASCII.LF);
   declare
      Incomplete : constant Assessment := Ada_Quality.Checks.Assess (98_765, Root, Policy);
      Proof      : Indicator_Result;
   begin
      Assert (Incomplete.Results.Length = 33 and then
        Incomplete.Status = Assessment_Completed,
        "an incomplete project still produces all 33 explicit pass, violation, or blocked results");
      for Item of Incomplete.Results loop
         if Item.Indicator = PRF_01 then
            Proof := Item;
         end if;
      end loop;
      Assert (Proof.Indicator = PRF_01 and then Proof.Applicable and then Proof.Compliance /= Pass,
        "a dedicated proof project is proved, and a failed proof cannot pass");
   end;
   declare
      First_Tree  : constant String := Fixture_Root & "/fingerprint_framing_a";
      Second_Tree : constant String := Fixture_Root & "/fingerprint_framing_b";
      First_Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Project_Tools.Files.Delete_Tree (First_Tree);
      Project_Tools.Files.Delete_Tree (Second_Tree);
      Ada.Directories.Create_Path (First_Tree);
      Ada.Directories.Create_Path (Second_Tree);
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/a", "Xb" & Character'Val (0) & "Y");
      Project_Tools.Files.Write_Text_File (Second_Tree & "/a", "X");
      Project_Tools.Files.Write_Text_File (Second_Tree & "/b", "Y");
      Assert
        (Ada_Quality.Checks.Source_Fingerprint (First_Tree) /=
           Ada_Quality.Checks.Source_Fingerprint (Second_Tree),
         "length-framed source records distinguish formerly ambiguous trees");
      First_Fingerprint := To_Unbounded_String
        (Ada_Quality.Checks.Source_Fingerprint (First_Tree));
      Ada.Directories.Create_Path (First_Tree & "/alire");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/alire/alire.lock", "machine-local resolution A");
      Assert
        (Ada_Quality.Checks.Source_Fingerprint (First_Tree) =
           To_String (First_Fingerprint),
         "generated Alire lock state does not change portable source identity");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/alire/alire.lock", "machine-local resolution B");
      Assert
        (Ada_Quality.Checks.Source_Fingerprint (First_Tree) =
           To_String (First_Fingerprint),
         "different generated Alire resolutions retain one source identity");
      Ada.Directories.Create_Path (First_Tree & "/alire_install/bin");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/alire_install/bin/alr", "runner-local Alire executable");
      Assert
        (Ada_Quality.Checks.Source_Fingerprint (First_Tree) =
           To_String (First_Fingerprint),
         "runner-local Alire installations do not change portable source identity");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/ada_quality-checks.ali", "compiler artifact");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/test.stdout", "temporary test output");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/.ada-quality.db", "local assessment database");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/.ada-quality.db.fts", "local search index");
      Assert
        (Ada_Quality.Checks.Source_Fingerprint (First_Tree) =
           To_String (First_Fingerprint),
         "generated compiler, test, and database files do not change source identity");
      Project_Tools.Files.Write_Text_File
        (First_Tree & "/alire.toml", "name = ""fingerprint_fixture""");
      Assert
        (Ada_Quality.Checks.Source_Fingerprint (First_Tree) /=
           To_String (First_Fingerprint),
         "the tracked release manifest remains part of source identity");
      Project_Tools.Files.Delete_Tree (First_Tree);
      Project_Tools.Files.Delete_Tree (Second_Tree);
   end;
   declare
      Project_Root : constant String := Project_Tools.Files.Find_Root_Upward
        (Ada.Directories.Current_Directory, "ada_quality.gpr");
      Ignore_Text : constant String := Project_Tools.Files.Read_Raw_File (Project_Root & "/.gitignore");
      Required_Patterns : constant Project_Tools.Files.Name_List :=
        [To_Unbounded_String ("/.alire/"), To_Unbounded_String ("/alire/"),
         To_Unbounded_String ("/alire_install/"), To_Unbounded_String ("/bin/"),
         To_Unbounded_String ("/obj/"), To_Unbounded_String ("/cov-bin/"),
         To_Unbounded_String ("/cov-obj/"), To_Unbounded_String ("/coverage/*"),
         To_Unbounded_String ("/lib/"), To_Unbounded_String ("/gnatprove/"),
         To_Unbounded_String ("/.ada-quality.db.*"), To_Unbounded_String ("*.ali"),
         To_Unbounded_String ("*.o"), To_Unbounded_String ("*.bexch"),
         To_Unbounded_String ("*.gcda"), To_Unbounded_String ("*.gcno"),
         To_Unbounded_String ("*.cswi"), To_Unbounded_String ("*.stdout"),
         To_Unbounded_String ("*.stderr")];
   begin
      Assert
        (Project_Root'Length > 0 and then
         not Ada_Quality.Project_Inventory.Is_Excluded_Staging_Directory ("coverage") and then
         Ada_Quality.Project_Inventory.Is_Excluded_Source_Directory ("coverage"),
         "the shared inventory retains canonical coverage only while staging");
      for Name of Ada_Quality.Project_Inventory.Excluded_Source_Directories loop
         Assert
           (Ada_Quality.Project_Inventory.Is_Excluded_Source_Directory (To_String (Name)),
            "every declared source-tree exclusion is classified by the shared inventory");
      end loop;
      for Pattern of Required_Patterns loop
         Assert
           (Ada.Strings.Fixed.Index (Ignore_Text, To_String (Pattern)) > 0,
            ".gitignore mirrors the shared generated-state inventory: " & To_String (Pattern));
      end loop;
   end;
   Project_Tools.Files.Delete_Tree (Root);
end;
end Run_Source_Analysis_Test;
