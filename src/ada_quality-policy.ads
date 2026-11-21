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

   type Key_Presence is record
      Coverage_Minimum_Basis_Points : Boolean := False;
      Maximum_Source_Lines          : Boolean := False;
      Maximum_Complexity            : Boolean := False;
      Process_Timeout_Seconds       : Boolean := False;
      Maximum_Output_Bytes          : Boolean := False;
      Require_Clean_Worktree        : Boolean := False;
   end record;

   type Policy_Key is
     (Coverage_Minimum_Key, Source_Lines_Key, Complexity_Key,
      Timeout_Key, Output_Key, Clean_Worktree_Key);
   --  Stable iteration order for every supported policy field.

   function Name (Key : Policy_Key) return String;
   function Is_Boolean (Key : Policy_Key) return Boolean;
   function Natural_Value
     (Item : Quality_Policy; Key : Policy_Key) return Natural
     with Pre => not Is_Boolean (Key);
   function Boolean_Value
     (Item : Quality_Policy; Key : Policy_Key) return Boolean
     with Pre => Is_Boolean (Key);
   function Value_Image (Item : Quality_Policy; Key : Policy_Key) return String;
   function Changed
     (Left, Right : Quality_Policy; Key : Policy_Key) return Boolean;
   function Is_Present (Sources : Key_Presence; Key : Policy_Key) return Boolean;
   function Affected_Indicators (Key : Policy_Key) return String;
   --  Canonical policy metadata shared by parsing, reporting, and impact analysis.
   --  Keys explicitly selected by one policy document.
   --  Resource limits and release requirements applied to one assessment.
   --  @field Coverage_Minimum_Basis_Points Minimum acceptable production coverage in hundredths of a percent.
   --  @field Maximum_Source_Lines Maximum permitted physical lines in one source file.
   --  @field Maximum_Complexity Maximum permitted decision complexity for one subprogram.
   --  @field Process_Timeout_Seconds Maximum wall-clock duration of an external tool.
   --  @field Maximum_Output_Bytes Maximum combined output bytes retained from one external tool.
   --  @field Require_Clean_Worktree Whether source mutation and dirty Git state fail the assessment.

   type Load_Result is record
      Success : Boolean := False;
      Value   : Quality_Policy;
      Present : Key_Presence;
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

   function Load_Overlay
     (Path : String; Base : Quality_Policy) return Load_Result;
   --  Load a partial policy overlay on top of an already validated policy.

   function Profile_Path (Base_Path, Name : String) return String;
   --  Return the sibling profile path formed by inserting Name before the file extension.

   function Is_Profile_Name (Name : String) return Boolean;
   --  Return whether Name is a safe portable profile identifier.

   function Render (Item : Quality_Policy) return String;
   --  Render a complete deterministic TOML policy document.

   function Fingerprint (Item : Quality_Policy) return String;

   function Explain
     (Item : Quality_Policy; Sources : Key_Presence;
      Base_Source, Overlay_Source : String) return String;
   --  Render every effective value together with the document that selected it.

   function Diff (Left, Right : Quality_Policy) return String;
   --  Render only policy values that differ.
   --  Compute the deterministic identity of a policy.
   --  @param Item Policy to identify.
   --  @return Stable fingerprint text.
end Ada_Quality.Policy;
