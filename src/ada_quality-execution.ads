with Ada.Strings.Unbounded;
with Project_Tools.Processes;

--  Bounded, timeout-controlled child-process execution in a clean environment.
package Ada_Quality.Execution is
   --  Bounded child-process execution under an explicit clean environment.
   subtype Unbounded_String is Ada.Strings.Unbounded.Unbounded_String;
   --  Dynamically sized captured process text.

   subtype Argument_Vector is Project_Tools.Processes.Argument_Vectors.Vector;
   --  Explicit child-process argument vector.

   type Run_Status is (Completed, Timed_Out, Spawn_Error);
   --  Terminal state of a bounded child process.
   --  @enum Completed Process exited before its deadline.
   --  @enum Timed_Out Process exceeded its deadline and was terminated.
   --  @enum Spawn_Error Process could not be started or monitored.

   type Run_Result is record
      Status     : Run_Status := Spawn_Error;
      Exit_Code  : Integer := -1;
      Output     : Unbounded_String;
      Truncated  : Boolean := False;
      Command    : Unbounded_String;
   end record;
   --  Bounded evidence returned by one child-process execution.
   --  @field Status Terminal process state.
   --  @field Exit_Code Child exit code, or minus one when unavailable.
   --  @field Output Captured stdout and stderr within the configured limit.
   --  @field Truncated Whether output exceeded the configured limit.
   --  @field Command Auditable executable and argument summary.

   function Run
     (Directory      : String;
      Program        : String;
      Arguments      : Argument_Vector;
      Timeout_Seconds : Positive;
      Maximum_Bytes  : Positive) return Run_Result;
   --  Execute a program without a shell, under a clean environment and hard limits.
   --  @param Directory Working directory for the child.
   --  @param Program Executable path or resolved program name.
   --  @param Arguments Explicit arguments, excluding the executable itself.
   --  @param Timeout_Seconds Wall-clock deadline.
   --  @param Maximum_Bytes Maximum combined output retained.
   --  @return Terminal process status and bounded evidence.
end Ada_Quality.Execution;
