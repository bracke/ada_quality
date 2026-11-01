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

   function Registry return Descriptor_Array is
      Result : Descriptor_Array;
   begin
      for Id in Indicator_Id loop
         Result (Id) :=
           (Id => Id, Version => 1, Category => Category_Of (Id), Name => Names (Id),
            Prerequisites => Dependencies (Id));
      end loop;
      return Result;
   end Registry;

   function Count return Ada.Containers.Count_Type is
   begin
      return 33;
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

   function Measurement_Unit (Id : Indicator_Id) return String is
     (case Id is
         when TST_02 => "registered_tests",
         when TST_03 => "basis_points",
         when SRC_01 => "lines",
         when SRC_02 | SRC_06 => "files",
         when SRC_03 => "decision_points",
         when SRC_04 => "findings",
         when SRC_05 => "handlers",
         when DOC_01 => "warnings",
         when SEC_01 | SEC_02 => "matches",
         when SEC_03 => "forbidden_entries",
         when others => "none");

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
