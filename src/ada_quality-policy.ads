with Ada.Strings.Unbounded;

--  Strict loading and deterministic fingerprinting of the central quality policy.
package Ada_Quality.Policy is
   --  Strict central resource and release policy.
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized text used by policy load diagnostics.

   type Quality_Policy is record
      Coverage_Minimum_Basis_Points : Natural := 9_000;
      Maximum_Source_Lines          : Positive := 1_000;
      Maximum_Complexity            : Positive := 15;
      Process_Timeout_Seconds       : Positive := 600;
      Maximum_Output_Bytes          : Positive := 1_048_576;
      Require_Clean_Worktree        : Boolean := True;
   end record;
   --  Resource limits and release requirements applied to one assessment.
   --  @field Coverage_Minimum_Basis_Points Minimum acceptable production coverage in hundredths of a percent.
   --  @field Maximum_Source_Lines Maximum permitted physical lines in one source file.
   --  @field Maximum_Complexity Maximum permitted decision complexity for one subprogram.
   --  @field Process_Timeout_Seconds Maximum wall-clock duration of an external tool.
   --  @field Maximum_Output_Bytes Maximum captured bytes from one external tool.
   --  @field Require_Clean_Worktree Whether source mutation and dirty Git state fail the assessment.

   type Load_Result is record
      Success : Boolean := False;
      Value   : Quality_Policy;
      Error   : Unbounded_String;
   end record;
   --  Structured result of strict policy parsing.
   --  @field Success True only when the complete policy was accepted.
   --  @field Value Parsed policy, or safe defaults after failure.
   --  @field Error Diagnostic text after failure.

   function Default return Quality_Policy;
   --  Return the built-in resource and release policy.
   --  @return Default policy value.

   function Load (Path : String) return Load_Result;
   --  Load a complete policy, rejecting unknown, duplicate, malformed, or unsafe values.
   --  @param Path Policy TOML file to read.
   --  @return Structured parse result.

   function Fingerprint (Item : Quality_Policy) return String;
   --  Compute the deterministic identity of a policy.
   --  @param Item Policy to identify.
   --  @return Stable fingerprint text.
end Ada_Quality.Policy;
