with Ada.Strings.Unbounded;

package body Ada_Quality.Evaluation is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;

   function Evaluate
     (Indicator         : Indicator_Id;
      Execution         : Execution_Status;
      Applicable        : Boolean;
      Requirement_Met   : Boolean;
      Success_Summary   : String;
      Violation_Summary : String;
      Evidence          : String) return Indicator_Result
   is
      Result : Indicator_Result;
   begin
      Result.Indicator := Indicator;
      Result.Execution := Execution;
      Result.Applicable := Applicable;
      Result.Evidence := To_Unbounded_String (Evidence);
      if not Applicable then
         Result.Execution := Not_Applicable;
         Result.Compliance := Not_Applicable;
         Result.Summary := To_Unbounded_String ("not applicable");
         Result.Measurement :=
           (Kind => Unavailable_Value, Reason => To_Unbounded_String (Evidence));
      elsif Execution = Succeeded then
         Result.Compliance := (if Requirement_Met then Pass else Violation);
         Result.Summary := To_Unbounded_String
           ((if Requirement_Met then Success_Summary else Violation_Summary));
         Result.Measurement := (Kind => Boolean_Value, Boolean_Data => Requirement_Met);
      else
         Result.Compliance := Unknown;
         Result.Summary := To_Unbounded_String (Violation_Summary);
         Result.Measurement :=
           (Kind => Unavailable_Value, Reason => To_Unbounded_String (Violation_Summary));
      end if;
      return Result;
   end Evaluate;
end Ada_Quality.Evaluation;
