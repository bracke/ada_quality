with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Immutable command-line snapshot used by CLI request parsers.
package Ada_Quality.CLI_Arguments is
   type Argument_Set is private;
   type Argument_Array is array (Positive range <>) of
     Ada.Strings.Unbounded.Unbounded_String;

   function Capture return Argument_Set;
   function Create (Values : Argument_Array) return Argument_Set;
   function Count (Arguments : Argument_Set) return Natural;
   function Element
     (Arguments : Argument_Set; Index : Positive) return String;
   function Option
     (Arguments : Argument_Set; Name, Default : String) return String;
   function Has_Flag
     (Arguments : Argument_Set; Name : String) return Boolean;

private
   package Argument_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "="          => Ada.Strings.Unbounded."=");
   type Argument_Set is record
      Values : Argument_Vectors.Vector;
   end record;
end Ada_Quality.CLI_Arguments;
