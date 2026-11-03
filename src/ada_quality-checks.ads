with Ada_Quality.Policy;
with Ada_Quality.Types;
with Project_Tools.Files;

--  Native and external quality measurements for one isolated project assessment.
package Ada_Quality.Checks is
   --  Native and external measurements for an isolated project assessment.
   type Source_Analysis is record
      File_Count          : Natural := 0;
      Production_Files    : Natural := 0;
      Test_Files          : Natural := 0;
      Generated_Files     : Natural := 0;
      Spec_Count          : Natural := 0;
      Lines               : Natural := 0;
      Long_Lines          : Natural := 0;
      Hygiene_Errors      : Natural := 0;
      Naming_Errors       : Natural := 0;
      Oversized_Files     : Natural := 0;
      Undocumented_Specs  : Natural := 0;
      Broad_Handlers      : Natural := 0;
      Maximum_Complexity  : Natural := 0;
      Secret_Matches      : Natural := 0;
      Unsafe_Processes    : Natural := 0;
      Test_Registrations  : Natural := 0;
      Findings            : Ada_Quality.Types.Finding_Vectors.Vector;
   end record;
   --  Aggregate native source metrics collected during one bounded traversal.
   --  @field File_Count Number of ordinary project files traversed.
   --  @field Production_Files Number of production Ada source files.
   --  @field Test_Files Number of test Ada source files.
   --  @field Generated_Files Number of recognized generated files.
   --  @field Spec_Count Number of production Ada specifications.
   --  @field Lines Total physical lines across analyzed source files.
   --  @field Long_Lines Lines exceeding the configured width.
   --  @field Hygiene_Errors Tabs and trailing-whitespace findings.
   --  @field Naming_Errors Ada unit/file naming mismatches.
   --  @field Oversized_Files Files exceeding the configured line limit.
   --  @field Undocumented_Specs Public specifications without package documentation.
   --  @field Broad_Handlers Broad exception handlers lacking an audited-boundary marker.
   --  @field Maximum_Complexity Highest measured subprogram decision complexity.
   --  @field Secret_Matches Possible embedded credential assignments.
   --  @field Unsafe_Processes Possible shell-based process execution patterns.
   --  @field Test_Registrations Registered test routines found in test sources.
   --  @field Findings Structured source findings produced during traversal.

   function Assess
     (Project_Id : Natural;
      Root       : String;
      Policy     : Ada_Quality.Policy.Quality_Policy) return Ada_Quality.Types.Assessment;
   --  Execute all applicable native and external checks for one project.
   --  @param Project_Id Persistent project identity.
   --  @param Root Canonical project root.
   --  @param Policy Validated policy controlling limits and gates.
   --  @return Complete in-memory assessment ready for atomic publication.

   function Source_Fingerprint (Root : String) return String;
   --  Hash the bounded, sorted project inventory while excluding generated build evidence.
   --  @param Root Canonical project root.
   --  @return Stable hexadecimal source fingerprint.

   function Project_State_Fingerprint (Root : String) return String;
   --  Hash source state and conventional generated artifact directories.
   --  @param Root Canonical project root.
   --  @return Stable source and artifact fingerprint for determinism comparisons.

   function Test_Project_File (Root : String) return String;
   --  Locate the project file of a project's AUnit tests crate from Root/tests/alire.toml.
   --  @param Root Canonical project root.
   --  @return The manifest's first existing `project-files` entry, or Root/tests/`<name>.gpr` for the tests crate's
   --  `name`; an empty string when the tests crate has no manifest.

   function Test_Suite_Executable (Root : String) return String;
   --  Locate the AUnit suite executable of a project's tests crate from Root/tests/alire.toml.
   --  @param Root Canonical project root.
   --  @return Root/tests/bin/ followed by the manifest's first `executables` entry, or by the tests crate's `name`;
   --  an empty string when the tests crate has no manifest.

   function Dedicated_Proof_Projects (Root : String) return Project_Tools.Files.Path_List;
   --  List the dedicated proof projects of a project: `spark*.gpr` files directly in Root, which name only the SPARK
   --  units to prove. PRF-01 proves these instead of the main project when there are any.
   --  @param Root Canonical project root.
   --  @return Project file paths in name order; empty when the project has no dedicated proof project.

   function Declares_SPARK (Root : String) return Boolean;
   --  Determine whether any project source declares `SPARK_Mode` outside comments and strings.
   --  @param Root Canonical project root.
   --  @return True when proof checks are applicable.

   function Analyze_Source
     (Root   : String;
      Policy : Ada_Quality.Policy.Quality_Policy) return Source_Analysis;
   --  Perform the bounded native source traversal and policy analysis.
   --  @param Root Canonical project root.
   --  @param Policy Validated source limits.
   --  @return Aggregate metrics and findings.
end Ada_Quality.Checks;
