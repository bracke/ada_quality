with Ada.Strings;
with Ada.Strings.Fixed;
with Interfaces;

package body Ada_Quality.CLI_Cursors is
   use type Interfaces.Unsigned_32;

   type Component_Array is array (Positive range 1 .. 5) of Natural;

   function Trimmed (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Component (Text : String) return Natural is
   begin
      if Text = "" or else
        (for some Character_Item of Text => Character_Item not in '0' .. '9')
      then
         raise Cursor_Error with "invalid cursor";
      end if;
      return Natural'Value (Text);
   exception
      when Constraint_Error =>
         raise Cursor_Error with "invalid cursor";
   end Component;

   function Parsed_Version (Text : String) return Cursor_Version is
   begin
      if Text'Length < 4 or else Text (Text'First) /= 'v' or else
        Text (Text'First + 2) /= ':' or else
        Text (Text'First + 1) not in '1' .. '5'
      then
         raise Cursor_Error with "invalid cursor";
      end if;
      return Character'Pos (Text (Text'First + 1)) - Character'Pos ('0');
   end Parsed_Version;

   function Parsed_Components
     (Text : String; Version : Cursor_Version) return Component_Array
   is
      Result : Component_Array := [others => 0];
      Start  : Natural := Text'First + 3;
   begin
      for Index in 1 .. Version loop
         declare
            Separator : constant Natural :=
              Ada.Strings.Fixed.Index (Text, ":", From => Start);
            Last : constant Natural :=
              (if Separator = 0 then Text'Last else Separator - 1);
         begin
            if Last < Start or else
              (Index < Version and then Separator = 0) or else
              (Index = Version and then Separator /= 0)
            then
               raise Cursor_Error with "invalid cursor";
            end if;
            Result (Index) := Component (Text (Start .. Last));
            if Separator /= 0 then
               Start := Separator + 1;
            end if;
         end;
      end loop;
      return Result;
   end Parsed_Components;

   procedure Populate
     (Result     : in out Cursor_State;
      Components : Component_Array) is
   begin
      case Result.Version is
         when 1 =>
            Result.Offset := Components (1);
         when 2 =>
            Result.Primary := Components (1);
            Result.Offset := Components (2);
         when 3 =>
            Result.Primary := Components (1);
            Result.Secondary := Components (2);
            Result.Offset := Components (3);
         when 4 =>
            Result.Primary := Components (1);
            Result.Secondary := Components (2);
            Result.Tertiary := Components (3);
            Result.Offset := Components (4);
         when 5 =>
            Result.Binding := Components (1);
            Result.Primary := Components (2);
            Result.Secondary := Components (3);
            Result.Tertiary := Components (4);
            Result.Offset := Components (5);
         when 0 =>
            null;
      end case;
   end Populate;

   function Decode (Text : String) return Cursor_State is
      Result : Cursor_State;
   begin
      if Text = "" then
         return Result;
      end if;
      Result.Version := Parsed_Version (Text);
      declare
         Components : constant Component_Array :=
           Parsed_Components (Text, Result.Version);
      begin
         Populate (Result, Components);
      end;
      return Result;
   end Decode;

   function Encode (State : Cursor_State; Offset : Natural) return String is
   begin
      if State.Binding > 0 then
         return
           "v5:" & Trimmed (State.Binding) & ":" &
           Trimmed (State.Primary) & ":" & Trimmed (State.Secondary) & ":" &
           Trimmed (State.Tertiary) & ":" & Trimmed (Offset);
      elsif State.Tertiary > 0 then
         return
           "v4:" & Trimmed (State.Primary) & ":" &
           Trimmed (State.Secondary) & ":" & Trimmed (State.Tertiary) & ":" &
           Trimmed (Offset);
      elsif State.Secondary > 0 then
         return
           "v3:" & Trimmed (State.Primary) & ":" &
           Trimmed (State.Secondary) & ":" & Trimmed (Offset);
      elsif State.Primary > 0 then
         return "v2:" & Trimmed (State.Primary) & ":" & Trimmed (Offset);
      else
         return "v1:" & Trimmed (Offset);
      end if;
   end Encode;

   function Query_Binding (Query : String) return Positive is
      Hash : Interfaces.Unsigned_32 := 16#811C9DC5#;
   begin
      for Character_Item of Query loop
         Hash :=
           (Hash xor Interfaces.Unsigned_32 (Character'Pos (Character_Item))) *
           16#01000193#;
      end loop;
      declare
         Value : constant Natural := Natural (Hash and 16#7FFF_FFFF#);
      begin
         return (if Value = 0 then 1 else Value);
      end;
   end Query_Binding;

   function Belongs_To
     (State : Cursor_State; Binding : Positive) return Boolean is
     (State.Version < 5 or else State.Binding = Binding);
end Ada_Quality.CLI_Cursors;
