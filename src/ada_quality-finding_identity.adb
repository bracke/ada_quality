with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces;
with Ada_Quality.Indicators;

package body Ada_Quality.Finding_Identity is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Interfaces.Unsigned_64;

   subtype UString is Ada.Strings.Unbounded.Unbounded_String;

   Context_Marker : constant String := ":ctx:";
   Legacy_Context_Marker : constant String := "@aq-context=";

   function Field (Value : String) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value'Length), Ada.Strings.Both) & ":" & Value);

   function Hash_Image (Value : Interfaces.Unsigned_64) return String is
      Hex    : constant String := "0123456789abcdef";
      Work   : Interfaces.Unsigned_64 := Value;
      Result : String (1 .. 16);
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Hex (Natural (Work and 15) + 1);
         Work := Interfaces.Shift_Right (Work, 4);
      end loop;
      return Result;
   end Hash_Image;

   function Create
     (Indicator : Indicator_Id;
      Rule, Path, Message : String;
      Context : String := "") return String
   is
      Normalized : constant String := Ada.Strings.Fixed.Trim (Context, Ada.Strings.Both);
      Hash : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Base : constant String :=
        Image (Indicator) & ":v2:" & Field (Rule) & Field (Path) & Field (Message);
   begin
      for Value of Normalized loop
         Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (Value))) * 16#100000001B3#;
      end loop;
      return Base & (if Normalized'Length = 0 then "" else Context_Marker & Hash_Image (Hash));
   end Create;

   function Decimal_Suffix_Is_Valid (Text : String; First : Natural) return Boolean is
   begin
      if First > Text'Last or else Text (First) = '0' then
         return False;
      end if;
      for Index in First .. Text'Last loop
         if Text (Index) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return Text'Last > First or else Text (First) in '2' .. '9';
   end Decimal_Suffix_Is_Valid;

   function Parse_Field
     (Text : String; Cursor : in out Natural; Value : out UString) return Boolean
   is
      Colon : Natural;
      Count : Natural;
   begin
      Value := Null_Unbounded_String;
      if Cursor > Text'Last then
         return False;
      end if;
      Colon := Ada.Strings.Fixed.Index (Text, ":", From => Cursor);
      if Colon = 0 or else Colon = Cursor or else
        (Text (Cursor) = '0' and then Colon > Cursor + 1)
      then
         return False;
      end if;
      for Index in Cursor .. Colon - 1 loop
         if Text (Index) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      Count := Natural'Value (Text (Cursor .. Colon - 1));
      if Count > Text'Last - Colon then
         return False;
      elsif Count > 0 then
         Value := To_Unbounded_String (Text (Colon + 1 .. Colon + Count));
      end if;
      Cursor := Colon + Count + 1;
      return True;
   exception
      when Constraint_Error =>
         return False;
   end Parse_Field;

   function Hash_Is_Valid (Text : String; First : Natural) return Boolean is
   begin
      if First > Text'Last or else Text'Last - First < 15 then
         return False;
      end if;
      declare
         Last : constant Natural := First + 15;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' | 'a' .. 'f' then
               return False;
            end if;
         end loop;
         return Last = Text'Last or else
           (Text (Last + 1) = '#' and then Decimal_Suffix_Is_Valid (Text, Last + 2));
      end;
   end Hash_Is_Valid;

   function V2_Suffix_Is_Valid (Text : String; Cursor : Natural) return Boolean is
   begin
      if Cursor > Text'Last then
         return True;
      elsif Text (Cursor) = '#' then
         return Decimal_Suffix_Is_Valid (Text, Cursor + 1);
      elsif Cursor + Context_Marker'Length - 1 > Text'Last or else
        Text (Cursor .. Cursor + Context_Marker'Length - 1) /= Context_Marker
      then
         return False;
      end if;
      return Hash_Is_Valid (Text, Cursor + Context_Marker'Length);
   end V2_Suffix_Is_Valid;

   function Parse_V2
     (Key : String;
      Indicator : out Indicator_Id;
      Rule, Path, Message : out UString;
      Cursor : out Natural) return Boolean
   is
   begin
      Indicator := Indicator_Id'First;
      Rule := Null_Unbounded_String;
      Path := Null_Unbounded_String;
      Message := Null_Unbounded_String;
      Cursor := Key'First;
      if Key'Length < 10 or else Key (Key'First + 6 .. Key'First + 9) /= ":v2:" or else
        not Ada_Quality.Indicators.Parse_Canonical
          (Key (Key'First .. Key'First + 5), Indicator)
      then
         return False;
      end if;
      Cursor := Key'First + 10;
      return Parse_Field (Key, Cursor, Rule) and then Parse_Field (Key, Cursor, Path) and then
        Parse_Field (Key, Cursor, Message) and then V2_Suffix_Is_Valid (Key, Cursor);
   exception
      when Constraint_Error =>
         return False;
   end Parse_V2;

   function Matches
     (Key       : String;
      Indicator : Indicator_Id;
      Rule, Path, Message : String) return Boolean
   is
      Parsed_Indicator : Indicator_Id;
      Parsed_Rule, Parsed_Path, Parsed_Message : UString;
      Cursor : Natural;
   begin
      return Key'Length >= 10 and then Key (Key'First + 6 .. Key'First + 9) = ":v2:" and then
        Parse_V2 (Key, Parsed_Indicator, Parsed_Rule, Parsed_Path, Parsed_Message, Cursor) and then
        Parsed_Indicator = Indicator and then To_String (Parsed_Rule) = Rule and then
        To_String (Parsed_Path) = Path and then To_String (Parsed_Message) = Message;
   end Matches;

   function Legacy_Key (Key : String) return String is
      Parsed_Indicator : Indicator_Id;
      Rule, Path, Message : UString;
      Cursor : Natural;
      Position : Natural;
   begin
      if Key'Length >= 10 and then Key (Key'First + 6 .. Key'First + 9) = ":v2:" then
         if not Parse_V2 (Key, Parsed_Indicator, Rule, Path, Message, Cursor) then
            return Key;
         end if;
         declare
            Base : constant String := Image (Parsed_Indicator) & ":" & To_String (Rule) & ":" &
              To_String (Path) & ":" & To_String (Message);
         begin
            return
              (if Cursor <= Key'Last and then Key (Cursor) = '#'
               then Base & Key (Cursor .. Key'Last) else Base);
         end;
      end if;
      Position := Ada.Strings.Fixed.Index (Key, Legacy_Context_Marker, Going => Ada.Strings.Backward);
      if Position = 0 or else not Hash_Is_Valid (Key, Position + Legacy_Context_Marker'Length) then
         return Key;
      end if;
      return Key (Key'First .. Position - 1);
   end Legacy_Key;
end Ada_Quality.Finding_Identity;
