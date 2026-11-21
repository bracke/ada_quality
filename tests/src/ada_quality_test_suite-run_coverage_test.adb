separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_coverage_test owner=core expires=2027-11-21 justification=one-component-fixture-matrix
procedure Run_Coverage_Test is
begin
Assert
  (Ada.Strings.Fixed.Index
     (Ada_Quality.CLI_Metadata.Completion_Words ("policy", "profiles"), "--database") = 0 and then
   Ada.Strings.Fixed.Index
     (Ada_Quality.CLI_Metadata.Completion_Words ("policy", "effective"), "--database") > 0 and then
   Ada.Strings.Fixed.Index
     (Ada_Quality.CLI_Metadata.Completion_Words ("database", "trust"), "add") > 0,
   "completion metadata exposes only options accepted by each command and subcommand");
Assert
  (Ada_Quality.CLI_Metadata.Classify_Option ("--database") =
     Ada_Quality.CLI_Metadata.Value_Option and then
   Ada_Quality.CLI_Metadata.Classify_Option ("--dry-run") =
     Ada_Quality.CLI_Metadata.Flag_Option and then
   Ada_Quality.CLI_Metadata.Classify_Option ("--unknown") =
     Ada_Quality.CLI_Metadata.Not_An_Option,
   "option classification and command validation share the centralized CLI metadata");
Assert
  (Ada_Quality.CLI_Metadata.Repeatable ("--changed-file") and then
   not Ada_Quality.CLI_Metadata.Repeatable ("--project"),
   "option metadata distinguishes repeatable inputs from accidental duplicates");
Assert
  (Ada_Quality.CLI_Metadata.Maximum_Positional_Count
     (Ada_Quality.CLI_Metadata.Version_Command,
      Ada_Quality.CLI_Metadata.No_Subcommand) = 1 and then
   Ada_Quality.CLI_Metadata.Maximum_Positional_Count
     (Ada_Quality.CLI_Metadata.Database_Command,
      Ada_Quality.CLI_Metadata.Database_Merge) = Natural'Last,
   "command metadata defines bounded positional arity and explicit variadic commands");
Assert
  (Ada_Quality.CLI_Metadata.Is_Command ("report") and then
   not Ada_Quality.CLI_Metadata.Is_Command ("unknown") and then
   Ada_Quality.CLI_Metadata.Is_Subcommand ("database", "merge") and then
   not Ada_Quality.CLI_Metadata.Is_Subcommand ("database", "unknown"),
   "command dispatch validates names through centralized CLI metadata");
Assert
  (Ada_Quality.CLI_Metadata.Identify ("report") =
     Ada_Quality.CLI_Metadata.Report_Command and then
   Ada_Quality.CLI_Metadata.Identify ("unknown") =
     Ada_Quality.CLI_Metadata.Unknown_Command and then
   Ada_Quality.CLI_Metadata.Requires_Store
     (Ada_Quality.CLI_Metadata.Check_Command,
      Ada_Quality.CLI_Metadata.No_Subcommand) and then
   Ada_Quality.CLI_Metadata.Requires_Store
     (Ada_Quality.CLI_Metadata.Project_Command,
      Ada_Quality.CLI_Metadata.Project_Add) and then
   not Ada_Quality.CLI_Metadata.Requires_Store
     (Ada_Quality.CLI_Metadata.Project_Command,
      Ada_Quality.CLI_Metadata.Project_List) and then
   not Ada_Quality.CLI_Metadata.Requires_Store
     (Ada_Quality.CLI_Metadata.Report_Command,
      Ada_Quality.CLI_Metadata.No_Subcommand),
   "typed command metadata drives both dispatch and store ownership");
for Index in 1 .. Ada_Quality.CLI_Metadata.Command_Count loop
   Assert
     (Ada.Strings.Fixed.Index
        (Ada_Quality.CLI_Metadata.Help_Text,
         Ada_Quality.CLI_Metadata.Command_Name (Index)) > 0,
      "every registered command is represented in centralized help metadata");
   declare
      Command : constant String :=
        Ada_Quality.CLI_Metadata.Command_Name (Index);
      Command_Id : constant Ada_Quality.CLI_Metadata.Command_Id :=
        Ada_Quality.CLI_Metadata.Identify (Command);
   begin
      for Subcommand_Index in
        1 .. Ada_Quality.CLI_Metadata.Subcommand_Count (Command)
      loop
         declare
            Name : constant String :=
              Ada_Quality.CLI_Metadata.Subcommand_Name
                (Command, Subcommand_Index);
            Id : constant Ada_Quality.CLI_Metadata.Subcommand_Id :=
              Ada_Quality.CLI_Metadata.Identify_Subcommand (Command_Id, Name);
         begin
            Assert
              (Id /= Ada_Quality.CLI_Metadata.Unknown_Subcommand and then
               Ada_Quality.CLI_Metadata.Command_Of (Id) = Command_Id and then
               Ada_Quality.CLI_Metadata.Image (Id) = Name,
               "every registered subcommand has one command-owned typed identity");
         end;
      end loop;
   end;
end loop;
Assert
  (Ada.Strings.Fixed.Index
     (Ada_Quality.CLI_Metadata.Help_Text,
      "report --format json|html [--project ID | --tag NAME]") > 0,
   "generated help documents the report tag selector accepted by metadata");
declare
   Saved : constant Terminal_Styles.Color_Policy :=
     Terminal_Styles.Current_Color_Policy;
   Exit_Code : Natural;
begin
   Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Always);
   Exit_Code := Ada_Quality.CLI.Run
     (Ada_Quality.CLI_Arguments.Create
        ([To_Unbounded_String ("version"),
          To_Unbounded_String ("--color"),
          To_Unbounded_String ("never")]));
   Assert
     (Exit_Code = 0 and then
      Terminal_Styles.Current_Color_Policy = Terminal_Styles.Color_Always,
      "embedded CLI requests restore process-global presentation state");
   Exit_Code := Ada_Quality.CLI.Run
     (Ada_Quality.CLI_Arguments.Create
        ([To_Unbounded_String ("version"),
          To_Unbounded_String ("unexpected")]));
   Assert (Exit_Code = 2, "commands reject unexpected positional arguments");
   Terminal_Styles.Set_Color_Policy (Saved);
exception
   when others =>
      Terminal_Styles.Set_Color_Policy (Saved);
      raise;
end;
declare
   List_Path : constant String := Fixture_Root & "/changed-files.txt";
   Arguments : constant Ada_Quality.CLI_Arguments.Argument_Set :=
     Ada_Quality.CLI_Arguments.Create
       ([To_Unbounded_String ("--changed-file"),
         To_Unbounded_String ("src/direct.adb"),
         To_Unbounded_String ("--files-from"),
         To_Unbounded_String (List_Path)]);
begin
   Project_Tools.Files.Write_Text_File
     (List_Path, ASCII.LF & "src/listed.ads" & ASCII.LF &
      "src/second.adb" & ASCII.LF);
   declare
      Files : constant Ada_Quality.CLI_Changed_Files.String_Vectors.Vector :=
        Ada_Quality.CLI_Changed_Files.Read (Arguments);
   begin
      Assert
        (Files.Length = 3 and then
         To_String (Files.First_Element) = "src/direct.adb" and then
         To_String (Files.Last_Element) = "src/second.adb",
         "changed-file parsing combines direct and bounded list inputs");
   end;
   declare
      Rejected : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Ada_Quality.CLI_Changed_Files.String_Vectors.Vector :=
                Ada_Quality.CLI_Changed_Files.Read
                  (Ada_Quality.CLI_Arguments.Create
                     ([To_Unbounded_String ("--changed-file"),
                       To_Unbounded_String ("")]));
         begin
            Rejected := not Ignored.Is_Empty;
         end;
      exception
         when Ada_Quality.CLI_Changed_Files.Input_Error => Rejected := True;
      end;
      Assert (Rejected, "changed-file parsing rejects empty direct paths");
   end;
   declare
      Rejected : Boolean := False;
      Long_Path : constant String
        (1 .. Ada_Quality.Resource_Limits.Maximum_Path_Input_Bytes + 1) :=
          [others => 'x'];
   begin
      begin
         declare
            Ignored : constant
              Ada_Quality.CLI_Changed_Files.String_Vectors.Vector :=
                Ada_Quality.CLI_Changed_Files.Read
                  (Ada_Quality.CLI_Arguments.Create
                     ([To_Unbounded_String ("--changed-file"),
                       To_Unbounded_String (Long_Path)]));
         begin
            Rejected := not Ignored.Is_Empty;
         end;
      exception
         when Ada_Quality.CLI_Changed_Files.Input_Error => Rejected := True;
      end;
      Assert (Rejected, "changed-file parsing rejects overlong direct paths");
   end;
   declare
      Empty : constant Ada_Quality.CLI_Changed_Files.String_Vectors.Vector :=
        Ada_Quality.CLI_Changed_Files.Read
          (Ada_Quality.CLI_Arguments.Create
             ([To_Unbounded_String ("scan")]));
   begin
      Assert (Empty.Is_Empty, "changed-file parsing accepts an omitted list");
   end;
   declare
      Rejected : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Ada_Quality.CLI_Changed_Files.String_Vectors.Vector :=
                Ada_Quality.CLI_Changed_Files.Read
                  (Ada_Quality.CLI_Arguments.Create
                     ([To_Unbounded_String ("--files-from"),
                       To_Unbounded_String
                         (Fixture_Root & "/missing-changed-files.txt")]));
         begin
            Rejected := not Ignored.Is_Empty;
         end;
      exception
         when Ada_Quality.CLI_Changed_Files.Input_Error => Rejected := True;
      end;
      Assert (Rejected, "changed-file parsing maps missing lists to input errors");
   end;
   Project_Tools.Files.Write_Text_File
     (List_Path,
      [1 .. Ada_Quality.Resource_Limits.Maximum_Path_Input_Bytes => 'x'] &
      ASCII.LF);
   declare
      Files : constant Ada_Quality.CLI_Changed_Files.String_Vectors.Vector :=
        Ada_Quality.CLI_Changed_Files.Read
          (Ada_Quality.CLI_Arguments.Create
             ([To_Unbounded_String ("--files-from"),
               To_Unbounded_String (List_Path)]));
   begin
      Assert
        (Files.Length = 1 and then
         Length (Files.First_Element) =
           Ada_Quality.Resource_Limits.Maximum_Path_Input_Bytes,
         "changed-file parsing accepts a path exactly at the input limit");
   end;
   Ada.Directories.Delete_File (List_Path);
end;
Assert (not Coverage_Passes (8_999, 10_000), "89.99 percent fails");
Assert (Coverage_Passes (9_000, 10_000), "90 percent passes");
Assert (Coverage_Passes (9_001, 10_000), "above 90 percent passes");
Assert (not Coverage_Passes (0, 0), "zero eligible lines cannot pass");
Assert
  (Coverage_Passes (Natural'Last, Natural'Last), "multiplication uses overflow-safe wide arithmetic");
declare
   Plain : constant String := Ada_Quality.Checks.Toolchain_Fingerprint
     ("GNATLS 15.2.0" & ASCII.LF & "Copyright changes are not compiler identity" & ASCII.LF);
   With_Setup_Chatter : constant String := Ada_Quality.Checks.Toolchain_Fingerprint
     ("Note: Synchronizing workspace..." & ASCII.CR & ASCII.LF &
      "  GNATLS 15.2.0  " & ASCII.CR & ASCII.LF & "one-time Alire diagnostic" & ASCII.LF);
   Other_Version : constant String := Ada_Quality.Checks.Toolchain_Fingerprint
     ("GNATLS 16.1.0" & ASCII.LF);
begin
   Assert
     (Plain'Length = 16 and then Plain = With_Setup_Chatter,
      "toolchain identity ignores Alire chatter, surrounding space, trailing output, and line endings");
   Assert
     (Other_Version'Length = 16 and then Other_Version /= Plain,
      "toolchain identity changes with the GNATLS version banner");
   Assert
     (Ada_Quality.Checks.Toolchain_Fingerprint ("GNAT setup did not complete")'Length = 0,
      "toolchain identity requires an actual GNATLS version banner");
end;
declare
   Root    : constant String := Fixture_Root & "/coverage_inventory";
   Objects : constant String := Root & "/objects";
begin
   Project_Tools.Files.Delete_Tree (Root);
   Ada.Directories.Create_Path (Root & "/src");
   Ada.Directories.Create_Path (Objects);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/alpha.ads", "package Alpha is end Alpha;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/alpha.adb", "package body Alpha is end Alpha;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/alpha-extra.adb",
      "separate (Alpha)" & ASCII.LF & "procedure Extra is begin null; end Extra;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/alpha-case.adb",
      "pragma Annotate (X, ""a""""b"");" & ASCII.LF &
      "Separate(Alpha) -- mixed case, tight parentheses" & ASCII.LF &
      "procedure Case_Form is begin null; end Case_Form;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/alpha-multiline.adb",
      "separate" & ASCII.LF & "  ( Alpha" & ASCII.LF & "    . Child )" & ASCII.LF &
      "procedure Multiline is begin null; end Multiline;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/alpha-commented.adb",
      "-- context comment" & ASCII.LF & "separate (-- parent follows" & ASCII.LF &
      " Alpha) -- trailing comment" & ASCII.LF &
      "procedure Commented is begin null; end Commented;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/beta.ads", "package Beta is end Beta;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/ada_quality_coverage.adb", "package body Ada_Quality_Coverage is end;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/ada_quality_coverage-helper.adb",
      "separate (Ada_Quality_Coverage)" & ASCII.LF &
      "procedure Helper is begin null; end Helper;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Root & "/src/ada_quality_coverage-helper-nested.adb",
      "separate (Ada_Quality_Coverage.Helper)" & ASCII.LF &
      "procedure Nested is begin null; end Nested;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File (Objects & "/alpha.gcno", "fixture");
   Project_Tools.Files.Write_Text_File (Objects & "/alpha-child.gcno", "fixture");
   declare
      Units : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
        Ada_Quality.Coverage.Production_Units (Root);
      Missing : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
        Ada_Quality.Coverage.Missing_Objects (Units, Objects);
   begin
      Assert (Units.Length = 3 and then Units.First_Element.Subunit_Paths.Length = 3 and then
        Units (Units.First_Index + 1).Subunit_Paths.Length = 1 and then
        Missing.Length = 1 and then
        To_String (Missing.First_Element.Stem) = "beta",
        "coverage inventory parses Ada subunit syntax, excludes nested driver subunits, " &
        "and detects missing instrumentation");
      Project_Tools.Files.Write_Text_File (Objects & "/beta.gcno", "fixture");
      Assert (Ada_Quality.Coverage.Missing_Objects (Units, Objects).Is_Empty,
        "coverage inventory is complete only when every production unit has instrumentation");
      Assert
        (Ada_Quality.Coverage.Has_Source_Record
           ("File '" & Root & "/src/alpha.adb'" & ASCII.LF &
            "Lines executed:100.00% of 0" & ASCII.CR & ASCII.LF,
            Root & "/src/alpha.adb") and then
         not Ada_Quality.Coverage.Has_Source_Record
           ("File '" & Root & "/src/alpha.adb'" & ASCII.LF,
            Root & "/src/alpha.adb") and then
         Ada_Quality.Coverage.Has_Source_Record
           ("File '" & Root & "/src/alpha.ads'" & ASCII.LF &
            "No executable lines" & ASCII.LF,
            Root & "/src/alpha.ads") and then
         not Ada_Quality.Coverage.Has_Source_Record
           ("File '" & Root & "/src/alpha.adb'" & ASCII.LF &
            "Lines executed:malformed" & ASCII.LF,
            Root & "/src/alpha.adb") and then
         not Ada_Quality.Coverage.Has_Source_Record
           ("File '" & Root & "/src/alpha.adb'" & ASCII.LF &
            "Lines executed:100.00% of 0" & ASCII.LF,
            Root & "/src/alpha.ads"),
         "coverage completeness requires a parsed summary and distinguishes zero-line evidence");
      declare
         Alpha : constant Ada_Quality.Coverage.Production_Unit := Units.First_Element;
         Child : constant Ada_Quality.Coverage.Production_Unit := Units (Units.First_Index + 1);
         Body_Only : constant String :=
           "File '" & Root & "/src/alpha.adb'" & ASCII.LF &
           "Lines executed:100.00% of 1" & ASCII.LF;
         Both : constant String :=
           Body_Only & "File '" & Root & "/src/alpha.ads'" & ASCII.LF &
           "No executable lines" & ASCII.LF;
         Both_Notes : constant String :=
           "block 2:`" & Root & "/src/alpha.adb':1" & ASCII.LF &
           "block 3:`" & Root & "/src/alpha.ads':1" & ASCII.LF;
      begin
         Assert
           (not Ada_Quality.Coverage.Has_Complete_Source_Records
              (Body_Only, Both_Notes, Alpha),
           "one combined-unit source record cannot stand in for a missing specification");
         Assert (Ada_Quality.Coverage.Has_Complete_Source_Records (Both, Both_Notes, Alpha),
           "combined-unit coverage is complete only when body and specification are represented");
         Assert
           (Ada_Quality.Coverage.Has_Complete_Source_Records
              (Body_Only, "block 2:`alpha.adb':1" & ASCII.LF, Alpha),
            "a source absent from compiler notes is recognized as having no executable lines");
         Assert
           (Ada_Quality.Coverage.Has_Complete_Source_Records
              ("File '" & Root & "/src/alpha-multiline.adb'" & ASCII.LF &
                 "Lines executed:100.00% of 1" & ASCII.LF,
               "block 2:`alpha-multiline.adb':1" & ASCII.LF, Child),
            "a subunit-only parent accepts absent body and specification records");
      end;
   end;
   Ada.Directories.Create_Path (Root & "/src/nested");
   declare
      Rejected : Boolean := False;
   begin
      Project_Tools.Files.Write_Text_File
        (Root & "/src/nested/alpha.adb", "package body Alpha is end Alpha;" & ASCII.LF);
      begin
         declare
            Duplicate_Units : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
              Ada_Quality.Coverage.Production_Units (Root);
         begin
            Rejected := Duplicate_Units.Is_Empty;
         end;
      exception
         when Constraint_Error => Rejected := True;
      end;
      Assert (Rejected, "coverage inventory rejects duplicate production body stems");
      Ada.Directories.Delete_File (Root & "/src/nested/alpha.adb");
      Project_Tools.Files.Write_Text_File
        (Root & "/src/nested/alpha.ads", "package Alpha is end Alpha;" & ASCII.LF);
      begin
         declare
            Duplicate_Units : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
              Ada_Quality.Coverage.Production_Units (Root);
         begin
            Rejected := Duplicate_Units.Is_Empty;
         end;
      exception
         when Constraint_Error => Rejected := True;
      end;
      Assert (Rejected, "coverage inventory rejects duplicate production specification stems");
   end;
   Project_Tools.Files.Delete_Tree (Root);
   declare
      Project_Root : constant String :=
        Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
      Project_Policy  : constant Ada_Quality.Policy.Quality_Policy := Ada_Quality.Policy.Default;
      Project_Metrics : constant Ada_Quality.Checks.Source_Analysis :=
        Ada_Quality.Checks.Analyze_Source (Project_Root, Project_Policy);

      function Complexity_Evidence return String is
      begin
         for Finding of Project_Metrics.Findings loop
            if Finding.Indicator = SRC_03 and then
              To_String (Finding.Rule) /= "review-waiver"
            then
               return " in " & To_String (Finding.Relative_Path) &
                 ":" & Natural'Image (Finding.Line) & " (" &
                 To_String (Finding.Message) & ")";
            end if;
         end loop;
         return "";
      end Complexity_Evidence;
   begin
      Assert (Project_Metrics.Complexity_Violations = 0,
        "the integrated source tree remains within the declared complexity contract; measured" &
        Natural'Image (Project_Metrics.Maximum_Complexity) & Complexity_Evidence);
      Assert (Ada_Quality.Checks.Project_State_Fingerprint (Project_Root)'Length > 0,
        "project-state fingerprinting streams large generated artifacts without exhausting the stack");
   end;
end;
end Run_Coverage_Test;
