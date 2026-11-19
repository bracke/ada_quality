with Ada.Characters.Handling;

package body Ada_Quality.Indicators is
   Names : constant array (Indicator_Id) of access constant String :=
     [STR_01 => new String'("Alire manifest"),
      STR_02 => new String'("GPR structure"),
      STR_03 => new String'("Standard layout"),
      STR_04 => new String'("Test subcrate"),
      STR_05 => new String'("Release tooling"),
      BLD_01 => new String'("Compilation"),
      BLD_02 => new String'("Validation build"),
      BLD_03 => new String'("Compiler warnings"),
      BLD_04 => new String'("Toolchain"),
      TST_01 => new String'("AUnit execution"),
      TST_02 => new String'("Test registration"),
      TST_03 => new String'("Line coverage >=90%"),
      TST_04 => new String'("Test determinism"),
      SRC_01 => new String'("Formatting"),
      SRC_02 => new String'("Naming"),
      SRC_03 => new String'("Cyclomatic complexity"),
      SRC_04 => new String'("Source hygiene"),
      SRC_05 => new String'("Exception handling"),
      SRC_06 => new String'("Source size"),
      DOC_01 => new String'("Public API documentation"),
      DOC_02 => new String'("GNATdoc generation"),
      DOC_03 => new String'("Required documentation"),
      DEP_01 => new String'("Dependency resolution"),
      DEP_02 => new String'("Local pins"),
      DEP_03 => new String'("Dependency consistency"),
      SEC_01 => new String'("Embedded secrets"),
      SEC_02 => new String'("Process execution safety"),
      SEC_03 => new String'("Artifact hygiene"),
      REL_01 => new String'("Release checker"),
      REL_02 => new String'("License consistency"),
      REL_03 => new String'("Release manifest"),
      REL_04 => new String'("Clean staging"),
      PRF_01 => new String'("SPARK proof verification")];

   Units : constant array (Indicator_Id) of access constant String :=
     [TST_02 => new String'("registered_tests"),
      TST_03 => new String'("basis_points"),
      SRC_01 => new String'("lines"),
      SRC_02 | SRC_06 => new String'("files"),
      SRC_03 => new String'("decision_points"),
      SRC_04 => new String'("findings"),
      SRC_05 => new String'("handlers"),
      DOC_01 => new String'("warnings"),
      SEC_01 | SEC_02 => new String'("matches"),
      SEC_03 => new String'("forbidden_entries"),
      others => new String'("none")];

   function Category_Of (Id : Indicator_Id) return Indicator_Category is
   begin
      case Id is
         when STR_01 .. STR_05 => return Structure;
         when BLD_01 .. BLD_04 => return Build;
         when TST_01 .. TST_04 => return Test;
         when SRC_01 .. SRC_06 => return Source;
         when DOC_01 .. DOC_03 => return Documentation;
         when DEP_01 .. DEP_03 => return Dependency;
         when SEC_01 .. SEC_03 => return Security;
         when REL_01 .. REL_04 => return Release;
         when PRF_01 => return Proof;
      end case;
   end Category_Of;

   function Dependencies (Id : Indicator_Id) return Indicator_Set is
      Result : Indicator_Set := [others => False];
   begin
      case Id is
         when BLD_01 | BLD_04 | DEP_01 =>
            Result (STR_01) := True;
            Result (STR_02) := True;
         when BLD_02 | BLD_03 | DEP_03 => Result (BLD_01) := True;
         when TST_01 | TST_02 | TST_04 =>
            Result (STR_04) := True;
            Result (BLD_01) := True;
         when TST_03 => Result (TST_01) := True;
         when DOC_02 => Result (STR_02) := True;
         when REL_01 => Result (STR_05) := True;
         when PRF_01 => Result (STR_02) := True;
         when others => null;
      end case;
      return Result;
   end Dependencies;

   function Gate_Of (Id : Indicator_Id) return Boolean is
     (Id in BLD_01 .. BLD_04 or else Id in TST_01 .. TST_04 or else
      Id in REL_01 .. REL_04 or else Id = PRF_01);

   function Trend_Of (Id : Indicator_Id) return Metric_Direction is
     (case Id is
         when TST_02 | TST_03 => Higher_Is_Better,
         when SRC_01 | SRC_02 | SRC_03 | SRC_04 | SRC_05 | SRC_06 |
              SEC_01 | SEC_02 | SEC_03 => Lower_Is_Better,
         when others => No_Trend);

   function Build_Registry return Descriptor_Array is
      Result : Descriptor_Array;
   begin
      for Id in Indicator_Id loop
         Result (Id) :=
           (Id => Id, Version => 1, Measurement_Version => 1,
            Category => Category_Of (Id), Name => Names (Id), Unit_Name => Units (Id),
            Gate => Gate_Of (Id), Trend => Trend_Of (Id),
            Prerequisites => Dependencies (Id));
      end loop;
      return Result;
   end Build_Registry;

   Descriptors : constant Descriptor_Array := Build_Registry;

   function Registry return Descriptor_Array is (Descriptors);

   function Count return Ada.Containers.Count_Type is
   begin
      return Ada.Containers.Count_Type (Indicator_Count'Last);
   end Count;

   function Parse (Text : String; Id : out Indicator_Id) return Boolean is
      Canonical : String := Ada.Characters.Handling.To_Upper (Text);
   begin
      for C of Canonical loop
         if C = '-' then
            C := '_';
         end if;
      end loop;
      Id := Indicator_Id'Value (Canonical);
      return True;
   exception
      when Constraint_Error =>
         Id := STR_01;
         return False;
   end Parse;

   function Parse_Canonical (Text : String; Id : out Indicator_Id) return Boolean is
     (Parse (Text, Id) and then Image (Id) = Text);

   function Measurement_Unit (Id : Indicator_Id) return String is
     (Descriptors (Id).Unit_Name.all);

   function Is_Gate (Id : Indicator_Id) return Boolean is
     (Descriptors (Id).Gate);

   function Direction_Of (Id : Indicator_Id) return Metric_Direction is
     (Descriptors (Id).Trend);

   Remediations : constant array (Indicator_Id) of access constant String :=
     [STR_01 => new String'("Add a valid alire.toml with the required crate name and version."),
      STR_02 => new String'("Add a usable GPR project file and declare it in the manifest."),
      STR_03 => new String'("Use the conventional src, tests, and documentation layout."),
      STR_04 => new String'("Add an AUnit tests subcrate under tests/."),
      STR_05 => new String'("Provide the release-check tooling required by the quality contract."),
      BLD_01 => new String'("Fix compilation errors in the normal project build."),
      BLD_02 => new String'("Fix errors exposed by the validation build configuration."),
      BLD_03 => new String'("Resolve compiler warnings or narrowly document an intentional exception."),
      BLD_04 => new String'("Run with a supported, discoverable GNAT toolchain."),
      TST_01 => new String'("Fix the AUnit suite so every registered test completes successfully."),
      TST_02 => new String'("Register executable AUnit test routines in the suite."),
      TST_03 => new String'("Add tests for uncovered production paths until policy coverage is met."),
      TST_04 => new String'("Remove nondeterministic output, state, ordering, or generated artifacts."),
      SRC_01 => new String'("Wrap overlong lines and apply the configured source formatting rules."),
      SRC_02 => new String'("Rename Ada source files to match their declared library units."),
      SRC_03 => new String'("Split complex decision logic or add a narrowly scoped audited waiver."),
      SRC_04 => new String'("Remove tabs, trailing whitespace, and other source hygiene findings."),
      SRC_05 => new String'("Handle specific exceptions or mark and justify an audited boundary."),
      SRC_06 => new String'("Split oversized source files or add a narrowly scoped audited waiver."),
      DOC_01 => new String'("Document every public declaration with useful API comments."),
      DOC_02 => new String'("Resolve GNATdoc generation errors and documentation warnings."),
      DOC_03 => new String'("Add the required project, contributor, security, and release documents."),
      DEP_01 => new String'("Correct dependency constraints until Alire resolves the dependency graph."),
      DEP_02 => new String'("Replace local path pins with reproducible published dependencies."),
      DEP_03 => new String'("Regenerate the lock file so it matches direct manifest dependencies."),
      SEC_01 => new String'("Remove embedded credentials and load secrets from a protected provider."),
      SEC_02 => new String'("Invoke programs with structured arguments instead of a command shell."),
      SEC_03 => new String'("Remove forbidden artifacts and symbolic links from the project tree."),
      REL_01 => new String'("Run the release checker and resolve every reported gate failure."),
      REL_02 => new String'("Align the manifest SPDX expression with the repository license text."),
      REL_03 => new String'("Complete the canonical release metadata in alire.toml."),
      REL_04 => new String'("Prevent source mutation while an assessment is running."),
      PRF_01 => new String'("Resolve applicable SPARK proof checks or supply a dedicated proof project.")];

   function Remediation (Id : Indicator_Id) return String is (Remediations (Id).all);

   function Validate_Acyclic return Boolean is
      type Visit_State is (Unseen, Visiting, Complete);
      State : array (Indicator_Id) of Visit_State := [others => Unseen];

      function Visit (Id : Indicator_Id) return Boolean is
      begin
         if State (Id) = Visiting then return False;
         elsif State (Id) = Complete then return True;
         end if;
         State (Id) := Visiting;
         for Dependency in Indicator_Id loop
            if Dependencies (Id) (Dependency) and then not Visit (Dependency) then return False; end if;
         end loop;
         State (Id) := Complete;
         return True;
      end Visit;
   begin
      for Id in Indicator_Id loop
         if not Visit (Id) then return False; end if;
      end loop;
      return True;
   end Validate_Acyclic;
end Ada_Quality.Indicators;
