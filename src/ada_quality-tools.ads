--  Canonical external-tool identities used by assessment adapters.
package Ada_Quality.Tools is
   type Tool_Id is (Alire, GNATls, AUnit, Gcov, GNATdoc, GNATprove, Git, Release_Checker);
   --  External tools that may contribute assessment evidence.
   --  @enum Alire Alire package manager and build driver.
   --  @enum GNATls GNAT toolchain identity command.
   --  @enum AUnit AUnit test framework and test action.
   --  @enum Gcov GNU line-coverage analyzer.
   --  @enum GNATdoc GNAT API documentation generator.
   --  @enum GNATprove SPARK proof tool.
   --  @enum Git Git source-control client.
   --  @enum Release_Checker Project release-structure checker.

   type Tool_Descriptor is record
      Id      : Tool_Id;
      Program : access constant String;
      Required : Boolean;
   end record;
   --  Immutable adapter metadata for an external tool.
   --  @field Id Stable tool identity.
   --  @field Program Executable name used for lookup.
   --  @field Required Whether absence blocks an applicable assessment.

   type Tool_Descriptor_Array is array (Tool_Id) of Tool_Descriptor;
   --  Complete descriptor table indexed by tool identity.

   function Registry return Tool_Descriptor_Array;
   --  Return the immutable external-tool registry.
   --  @return One descriptor for each tool identity.

   function Program (Id : Tool_Id) return String;
   --  Return the canonical executable name for a tool.
   --  @param Id Tool identity to resolve.
   --  @return Executable name.
end Ada_Quality.Tools;
