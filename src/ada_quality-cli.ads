--  Command-line dispatch and stable process exit-status handling.
package Ada_Quality.CLI is
   function Run return Natural;
   --  Parse the process arguments, execute one command, and return its stable exit code.
   --  @return Exit class from zero through four as documented by the command-line contract.
end Ada_Quality.CLI;
