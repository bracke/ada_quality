with Ada.Containers;
with Ada_Quality.Types;

--  Immutable registry and dependency graph for the 33 quality indicators.
package Ada_Quality.Indicators is
   --  Immutable registry and prerequisite graph for all 33 quality indicators.
   use Ada_Quality.Types;

   type Indicator_Category is (Structure, Build, Test, Source, Documentation, Dependency, Security, Release, Proof);
   --  Reporting group for a quality indicator.
   --  @enum Structure Project structure and manifest checks.
   --  @enum Build Compilation and toolchain checks.
   --  @enum Test Test registration, execution, determinism, and coverage checks.
   --  @enum Source Native source-quality checks.
   --  @enum Documentation Documentation presence and generation checks.
   --  @enum Dependency Dependency resolution and pin checks.
   --  @enum Security Filesystem, credential, and process-boundary checks.
   --  @enum Release Release metadata and evidence checks.
   --  @enum Proof Conditional SPARK proof checks.

   type Indicator_Set is array (Indicator_Id) of Boolean;
   --  Membership set indexed by all indicator identifiers.

   type Indicator_Descriptor is record
      Id       : Indicator_Id;
      Version  : Positive;
      Category : Indicator_Category;
      Name     : access constant String;
      Prerequisites : Indicator_Set;
   end record;
   --  Immutable registry metadata for one indicator.
   --  @field Id Stable indicator identifier.
   --  @field Version Indicator contract version.
   --  @field Category Reporting group.
   --  @field Name Human-readable indicator name.
   --  @field Prerequisites Indicators that must produce evidence first.

   type Descriptor_Array is array (Indicator_Id) of Indicator_Descriptor;
   --  Complete registry indexed by stable identifier.

   function Registry return Descriptor_Array;
   --  Return the immutable 33-indicator registry.
   --  @return Complete descriptor table.

   function Count return Ada.Containers.Count_Type;
   --  Return the number of registered indicators.
   --  @return Exactly 33 for the current contract.

   function Parse (Text : String; Id : out Indicator_Id) return Boolean;
   --  Parse a stable external identifier such as `TST-03`.
   --  @param Text Identifier text.
   --  @param Id Parsed identifier on success.
   --  @return True when Text names a registered indicator.

   function Measurement_Unit (Id : Indicator_Id) return String;
   --  Return the unit of the numeric measurement an indicator records.
   --  @param Id Indicator identity.
   --  @return Stable lowercase unit such as `basis_points` or `lines`, or `none` when the indicator records
   --  only a Boolean, text, or unavailable measurement.

   function Validate_Acyclic return Boolean;
   --  Validate that prerequisite relationships form an acyclic graph.
   --  @return True when every dependency is valid and no cycle exists.
end Ada_Quality.Indicators;
