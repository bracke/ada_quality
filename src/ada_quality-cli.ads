with Ada_Quality.CLI_Arguments;

--  Command-line dispatch and stable process exit-status handling.
package Ada_Quality.CLI is
   function Run return Natural;
   --  Parse the process arguments, execute one command, and return its stable exit code.
   --  @return Exit class from zero through four as documented by the command-line contract.

   function Run
     (Arguments : Ada_Quality.CLI_Arguments.Argument_Set) return Natural;
   --  Execute an explicitly supplied immutable argument set.
   --  This overload supports in-process front ends and isolated command tests.
end Ada_Quality.CLI;
