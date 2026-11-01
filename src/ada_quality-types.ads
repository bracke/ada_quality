with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Typed domain model shared by measurement, persistence, history, and reporting.
package Ada_Quality.Types is
   --  Typed domain model shared by measurement, persistence, history, and reporting.
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized domain and evidence text.

   type Indicator_Id is
     (STR_01, STR_02, STR_03, STR_04, STR_05,
      BLD_01, BLD_02, BLD_03, BLD_04,
      TST_01, TST_02, TST_03, TST_04,
      SRC_01, SRC_02, SRC_03, SRC_04, SRC_05, SRC_06,
      DOC_01, DOC_02, DOC_03,
      DEP_01, DEP_02, DEP_03,
      SEC_01, SEC_02, SEC_03,
      REL_01, REL_02, REL_03, REL_04,
      PRF_01);
   --  Stable identifiers for the complete quality contract.
   --  @enum STR_01 Valid Alire manifest is present.
   --  @enum STR_02 A GPR project is present.
   --  @enum STR_03 Standard source layout is present.
   --  @enum STR_04 Test subcrate is present.
   --  @enum STR_05 Release checker is present.
   --  @enum BLD_01 Project builds successfully.
   --  @enum BLD_02 Validation build succeeds.
   --  @enum BLD_03 Compiler warning gate succeeds.
   --  @enum BLD_04 Selected GNAT toolchain is identified.
   --  @enum TST_01 AUnit test action succeeds.
   --  @enum TST_02 Registered tests are present.
   --  @enum TST_03 Production line coverage meets policy.
   --  @enum TST_04 Test output is deterministic.
   --  @enum SRC_01 Source formatting meets policy.
   --  @enum SRC_02 Source filenames match Ada units.
   --  @enum SRC_03 Decision complexity meets policy.
   --  @enum SRC_04 Source hygiene meets policy.
   --  @enum SRC_05 Exception handling is explicitly audited.
   --  @enum SRC_06 Source file sizes meet policy.
   --  @enum DOC_01 Public package documentation is present.
   --  @enum DOC_02 GNATdoc generation succeeds without warnings.
   --  @enum DOC_03 Required project documentation is present.
   --  @enum DEP_01 Dependencies resolve.
   --  @enum DEP_02 Manifest contains no local path pins.
   --  @enum DEP_03 Resolved dependency solution builds.
   --  @enum SEC_01 No embedded secret assignment is found.
   --  @enum SEC_02 No shell process execution is found.
   --  @enum SEC_03 No forbidden artifact or symbolic link is found.
   --  @enum REL_01 Release checker succeeds.
   --  @enum REL_02 License metadata and file are present.
   --  @enum REL_03 Release manifest fields are present.
   --  @enum REL_04 Source fingerprint remains unchanged during assessment.
   --  @enum PRF_01 SPARK proof succeeds when proof is applicable.

   subtype Indicator_Count is Natural range 0 .. 33;
   --  Bounded number of indicators or indicator results.

   type Execution_Status is (Not_Run, Running, Succeeded, Blocked, Failed, Errored, Not_Applicable);
   --  Execution state, independent of compliance.
   --  @enum Not_Run Adapter has not run.
   --  @enum Running Adapter is currently running.
   --  @enum Succeeded Adapter produced usable terminal evidence.
   --  @enum Blocked Required evidence could not be obtained.
   --  @enum Failed Adapter completed and reported a tool failure.
   --  @enum Errored Adapter or internal processing raised an error.
   --  @enum Not_Applicable Requirement does not apply to this project.

   type Compliance_Status is (Unknown, Pass, Violation, Not_Applicable);
   --  Policy compliance state, independent of execution.
   --  @enum Unknown Evidence is insufficient for a policy conclusion.
   --  @enum Pass Requirement is satisfied.
   --  @enum Violation Requirement is not satisfied.
   --  @enum Not_Applicable Requirement does not apply.

   type Severity is (Info, Low, Medium, High, Critical);
   --  Finding severity.
   --  @enum Info Informational finding.
   --  @enum Low Low-impact finding.
   --  @enum Medium Material but noncritical finding.
   --  @enum High Release-significant finding.
   --  @enum Critical Critical release-blocking finding.

   type Value_Kind is (Unavailable_Value, Boolean_Value, Integer_Value, Decimal_Value, Text_Value, Enum_Value);
   --  Persisted measurement representation.
   --  @enum Unavailable_Value Measurement is unavailable with a reason.
   --  @enum Boolean_Value Boolean measurement.
   --  @enum Integer_Value Signed integer measurement.
   --  @enum Decimal_Value Fixed basis-point measurement.
   --  @enum Text_Value Free text measurement.
   --  @enum Enum_Value Stable enumerated text measurement.

   type Measurement_Value (Kind : Value_Kind := Unavailable_Value) is record
      case Kind is
         when Unavailable_Value =>
            Reason : Unbounded_String;
         when Boolean_Value =>
            Boolean_Data : Boolean := False;
         when Integer_Value =>
            Integer_Data : Long_Long_Integer := 0;
         when Decimal_Value =>
            Basis_Points : Long_Long_Integer := 0;
         when Text_Value | Enum_Value =>
            Text_Data : Unbounded_String;
      end case;
   end record;
   --  Typed indicator measurement selected by Kind.
   --  @field Kind Measurement representation discriminator.
   --  @field Reason Explanation for unavailable evidence.
   --  @field Boolean_Data Boolean measurement value.
   --  @field Integer_Data Signed integer measurement value.
   --  @field Basis_Points Fixed hundredths-of-a-percent value.
   --  @field Text_Data Text or enumeration measurement value.

   type Finding is record
      Indicator  : Indicator_Id := STR_01;
      Rule        : Unbounded_String;
      Level       : Severity := Medium;
      Message     : Unbounded_String;
      Relative_Path : Unbounded_String;
      Line        : Natural := 0;
      Fingerprint : Unbounded_String;
   end record;
   --  Structured source, tool, or policy finding.
   --  @field Indicator Owning indicator.
   --  @field Rule Stable rule identifier.
   --  @field Level Finding severity.
   --  @field Message Human-readable diagnostic.
   --  @field Relative_Path Project-relative source path when applicable.
   --  @field Line One-based line number, or zero when not applicable.
   --  @field Fingerprint Stable finding identity across path and line movement.

   package Finding_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Finding);
   --  Ordered finding collection.

   type Indicator_Result is record
      Indicator  : Indicator_Id := STR_01;
      Execution  : Execution_Status := Not_Run;
      Compliance : Compliance_Status := Unknown;
      Applicable : Boolean := True;
      Summary     : Unbounded_String;
      Evidence    : Unbounded_String;
      Measurement : Measurement_Value;
      Findings    : Finding_Vectors.Vector;
   end record;
   --  Complete execution, compliance, measurement, and finding evidence for one indicator.
   --  @field Indicator Stable indicator identity.
   --  @field Execution Adapter execution state.
   --  @field Compliance Policy compliance state.
   --  @field Applicable Whether the requirement applies.
   --  @field Summary Human-readable conclusion.
   --  @field Evidence Stable evidence description.
   --  @field Measurement Typed measurement.
   --  @field Findings Structured findings owned by this indicator.

   package Result_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Indicator_Result);
   --  Ordered indicator-result collection.

   type Tool_Run_Status is (Tool_Completed, Tool_Timed_Out, Tool_Spawn_Error);
   --  Persisted terminal state of an external tool execution.
   --  @enum Tool_Completed Process exited before its deadline.
   --  @enum Tool_Timed_Out Process exceeded its deadline.
   --  @enum Tool_Spawn_Error Process could not be started or monitored.

   type Tool_Execution is record
      Tool          : Unbounded_String;
      Command       : Unbounded_String;
      Status        : Tool_Run_Status := Tool_Spawn_Error;
      Exit_Code     : Integer := -1;
      Output_Digest : Unbounded_String;
      Output_Bytes  : Natural := 0;
      Truncated     : Boolean := False;
   end record;
   --  Bounded, immutable execution evidence.
   --  @field Tool Stable adapter label.
   --  @field Command Auditable executable and argument summary.
   --  @field Status Terminal tool state.
   --  @field Exit_Code Child exit code, or minus one when unavailable.
   --  @field Output_Digest Stable digest of captured output.
   --  @field Output_Bytes Number of captured output bytes before truncation.
   --  @field Truncated Whether output exceeded its configured limit.

   package Tool_Execution_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Tool_Execution);
   --  Ordered external-execution evidence collection.

   type Assessment_Status is (Assessment_Running, Assessment_Completed, Assessment_Invalid, Assessment_Interrupted);
   --  Assessment lifecycle state.
   --  @enum Assessment_Running External checks may still be active.
   --  @enum Assessment_Completed Complete evidence was atomically published.
   --  @enum Assessment_Invalid Terminal evidence failed publication validation.
   --  @enum Assessment_Interrupted Execution ended before terminal publication.

   type Assessment is record
      Id                 : Natural := 0;
      Project_Id         : Natural := 0;
      Project_Path       : Unbounded_String;
      Source_Fingerprint : Unbounded_String;
      Policy_Fingerprint : Unbounded_String;
      Toolchain_Fingerprint : Unbounded_String;
      Status             : Assessment_Status := Assessment_Running;
      Results            : Result_Vectors.Vector;
      Executions         : Tool_Execution_Vectors.Vector;
   end record;
   --  Complete in-memory or published assessment.
   --  @field Id Persistent assessment identity, or zero before start.
   --  @field Project_Id Owning project identity.
   --  @field Project_Path Canonical assessed project root.
   --  @field Source_Fingerprint Assessed source identity.
   --  @field Policy_Fingerprint Applied policy identity.
   --  @field Toolchain_Fingerprint Selected toolchain identity.
   --  @field Status Assessment lifecycle state.
   --  @field Results Exactly one result for each applicable contract identifier at publication.
   --  @field Executions Bounded external-tool evidence.

   function Image (Id : Indicator_Id) return String;
   --  Return the stable external indicator spelling.
   --  @param Id Indicator identity.
   --  @return Group prefix, hyphen, and two-digit ordinal.

   function Image (Status : Execution_Status) return String;
   --  Return the stable external execution-state spelling.
   --  @param Status Execution state.
   --  @return Lowercase hyphenated image.

   function Image (Status : Compliance_Status) return String;
   --  Return the stable external compliance-state spelling.
   --  @param Status Compliance state.
   --  @return Lowercase hyphenated image.

   function Image (Status : Tool_Run_Status) return String;
   --  Return the stable external tool-state spelling.
   --  @param Status Tool state.
   --  @return Lowercase hyphenated image.

   function Image (Value : Measurement_Value) return String;
   --  Return a stable persisted image of a typed measurement.
   --  @param Value Measurement value.
   --  @return Representation-specific text.

   function Is_Valid (Item : Indicator_Result) return Boolean;
   --  Validate execution, compliance, applicability, and measurement consistency.
   --  @param Item Indicator result to validate.
   --  @return True when every state invariant holds.

   function Is_Publishable (Item : Assessment) return Boolean;
   --  Validate terminal status and exact unique 33-result cardinality.
   --  @param Item Assessment to validate.
   --  @return True when Item may be atomically published.

   function Coverage_Passes (Covered, Total : Natural; Minimum_Basis_Points : Natural := 9_000) return Boolean;
   --  Compare exact line counts against a basis-point threshold without overflow.
   --  @param Covered Executed production lines.
   --  @param Total Eligible production lines.
   --  @param Minimum_Basis_Points Required hundredths of a percent.
   --  @return True when Total is nonzero and the exact ratio meets the threshold.
end Ada_Quality.Types;
