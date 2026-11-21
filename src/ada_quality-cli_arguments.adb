with Ada.Command_Line;

package body Ada_Quality.CLI_Arguments is
   use Ada.Strings.Unbounded;

   function Create (Values : Argument_Array) return Argument_Set is
      Result : Argument_Set;
   begin
      for Value of Values loop
         Result.Values.Append (Value);
      end loop;
      return Result;
   end Create;

   function Capture return Argument_Set is
      Empty : Argument_Set;
   begin
      if Ada.Command_Line.Argument_Count = 0 then
         return Empty;
      end if;
      declare
         Values : Argument_Array (1 .. Ada.Command_Line.Argument_Count);
      begin
         for Index in Values'Range loop
            Values (Index) := To_Unbounded_String
              (Ada.Command_Line.Argument (Index));
         end loop;
         return Create (Values);
      end;
   end Capture;

   function Count (Arguments : Argument_Set) return Natural is
     (Natural (Arguments.Values.Length));

   function Element
     (Arguments : Argument_Set; Index : Positive) return String
   is
     (if Index > Arguments.Values.Last_Index
      then ""
      else To_String (Arguments.Values.Element (Index)));

   function Option
     (Arguments : Argument_Set; Name, Default : String) return String
   is
   begin
      if Count (Arguments) < 2 then
         return Default;
      end if;
      for Index in 1 .. Count (Arguments) - 1 loop
         if Element (Arguments, Index) = Name then
            return Element (Arguments, Index + 1);
         end if;
      end loop;
      return Default;
   end Option;

   function Has_Flag
     (Arguments : Argument_Set; Name : String) return Boolean
   is
     (for some Index in 1 .. Count (Arguments) =>
        Element (Arguments, Index) = Name);
end Ada_Quality.CLI_Arguments;
