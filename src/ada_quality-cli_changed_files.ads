with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Ada_Quality.CLI_Arguments;

--  Bounded parsing of changed-source paths supplied directly or through a list.
package Ada_Quality.CLI_Changed_Files is
   package String_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   Input_Error : exception;

   function Read
     (Arguments : Ada_Quality.CLI_Arguments.Argument_Set)
      return String_Vectors.Vector;
end Ada_Quality.CLI_Changed_Files;
