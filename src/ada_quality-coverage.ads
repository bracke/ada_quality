with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package Ada_Quality.Coverage is
   --  Independent production-source inventory for coverage completeness checks.
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized path or unit text.

   type Production_Unit is record
      Stem      : Unbounded_String;
      Body_Path : Unbounded_String;
      Spec_Path : Unbounded_String;
   end record;
   --  One production Ada unit and its independently discovered source files.
   --  @field Stem GNAT object basename shared by the unit sources.
   --  @field Body_Path Absolute body path, or empty when the unit has no body.
   --  @field Spec_Path Absolute specification path, or empty when the unit has no specification.

   package Production_Unit_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Production_Unit);
   --  Deterministically ordered production-unit collection.

   function Production_Units (Root : String) return Production_Unit_Vectors.Vector;
   --  Enumerate production units from the standard source tree independently of coverage data.
   --  The self-hosting coverage driver is explicitly excluded because it owns the active gcov files
   --  and is verification tooling rather than a shipped Alire executable.
   --  @param Root Project root containing `src`.
   --  @return Sorted unique units found under `src`.

   function Missing_Objects
     (Units      : Production_Unit_Vectors.Vector;
      Object_Dir : String) return Production_Unit_Vectors.Vector;
   --  Select units without their required GNAT coverage-note file.
   --  @param Units Independently enumerated production units.
   --  @param Object_Dir Instrumented GNAT object directory.
   --  @return Units for which `<stem>.gcno` is absent.

   function Has_Source_Record (Output, Source : String) return Boolean;
   --  Test whether gcov output contains a complete per-file record for Source.
   --  @param Output Captured per-file gcov output.
   --  @param Source Absolute inventoried source path.
   --  @return True when a matching file header has a valid line summary.
end Ada_Quality.Coverage;
