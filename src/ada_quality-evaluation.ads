with Ada_Quality.Types;

--  Central conversion of execution evidence into compliance results.
package Ada_Quality.Evaluation is
   --  Central conversion of execution evidence into compliance results.
   function Evaluate
     (Indicator         : Ada_Quality.Types.Indicator_Id;
      Execution         : Ada_Quality.Types.Execution_Status;
      Applicable        : Boolean;
      Requirement_Met   : Boolean;
      Success_Summary   : String;
      Violation_Summary : String;
      Evidence          : String) return Ada_Quality.Types.Indicator_Result;
   --  Convert execution and requirement evidence into a validated indicator result.
   --  @param Indicator Indicator being evaluated.
   --  @param Execution Terminal execution state of its adapter.
   --  @param Applicable Whether the requirement applies to this project.
   --  @param Requirement_Met Whether applicable evidence satisfies the requirement.
   --  @param Success_Summary Summary used for a passing result.
   --  @param Violation_Summary Summary used for a violation.
   --  @param Evidence Stable evidence description.
   --  @return Consistent execution/compliance result.
end Ada_Quality.Evaluation;
