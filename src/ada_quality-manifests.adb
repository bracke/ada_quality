with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Project_Tools.TOML;

package body Ada_Quality.Manifests is
   --  AQ-WAIVER: SRC-03 target=begin_value owner=aq expires=2099-12-31 justification=toml-state-machine
   use Ada.Strings.Unbounded;
   use type Project_Tools.TOML.String_Parse_Status;

   Maximum_Depth : constant := 64;

   function Without_Comments (Text : String) return String is
      Result    : String := Text;
      In_String : Boolean := False;
      Quote     : Character := Character'Val (0);
      Escaped   : Boolean := False;
      Position  : Natural := Text'First;
   begin
      while Position <= Text'Last loop
         if not In_String and then Text (Position) = '#' then
            while Position <= Text'Last and then Text (Position) /= Ada.Characters.Latin_1.LF loop
               Result (Position) := ' ';
               Position := Position + 1;
            end loop;
         elsif Text (Position) = Ada.Characters.Latin_1.LF then
            Position := Position + 1;
         elsif In_String then
            if Text (Position) = Quote and then (Quote = ''' or else not Escaped) then
               In_String := False;
            end if;
            Escaped := Quote = '"' and then Text (Position) = '\' and then not Escaped;
            Position := Position + 1;
         elsif Text (Position) in ''' | '"' then
            In_String := True;
            Quote := Text (Position);
            Escaped := False;
            Position := Position + 1;
         else
            Position := Position + 1;
         end if;
      end loop;
      return Result;
   end Without_Comments;

   function Is_Valid (Text : String) return Boolean is
      Clean       : constant String := Without_Comments (Text);
      Square      : Natural := 0;
      Curly       : Natural := 0;
      In_String   : Boolean := False;
      Quote       : Character := Character'Val (0);
      Escaped     : Boolean := False;
      Position    : Natural := Clean'First;
      Line_Start  : Natural := Clean'First;
      Header_Mode : Boolean := False;
      Saw_Equals  : Boolean := False;
      Line_Started_Nested : Boolean := False;
      type Boolean_Stack is array (Positive range 1 .. Maximum_Depth) of Boolean;
      Expect_Value : Boolean_Stack := [others => True];
      Had_Value    : Boolean_Stack := [others => False];

      function First_Nonblank (First, Last : Natural) return Natural is
      begin
         for Index in First .. Last loop
            if Clean (Index) not in ' ' | Ada.Characters.Latin_1.HT | Ada.Characters.Latin_1.CR then
               return Index;
            end if;
         end loop;
         return 0;
      end First_Nonblank;

      function Complete_Line (Last : Natural) return Boolean is
         First : constant Natural := First_Nonblank (Line_Start, Last);
         Equal : constant Natural :=
           (if First = 0 then 0 else Ada.Strings.Fixed.Index (Clean (First .. Last), "="));
      begin
         if First = 0 or else Line_Started_Nested or else Square > 0 or else Curly > 0 then
            return True;
         elsif Clean (First) = '[' then
            return Clean (Last) = ']';
         else
            return Equal > First and then Equal < Last;
         end if;
      end Complete_Line;

      procedure Begin_Value is
      begin
         if Square > 0 then
            if not Expect_Value (Square) then
               raise Constraint_Error;
            end if;
            Expect_Value (Square) := False;
            Had_Value (Square) := True;
         end if;
      end Begin_Value;
   begin
      if Text'Length = 0 then return False; end if;
      while Position <= Clean'Last loop
         if In_String then
            if Clean (Position) = Ada.Characters.Latin_1.LF and then Quote /= Character'Val (0) then
               return False;
            elsif Clean (Position) = Quote and then (Quote = ''' or else not Escaped) then
               In_String := False;
               Quote := Character'Val (0);
            end if;
            Escaped := Clean (Position) = '\' and then not Escaped;
         elsif Clean (Position) = Ada.Characters.Latin_1.LF then
            if not Complete_Line (Position - 1) then return False; end if;
            Line_Start := Position + 1;
            Line_Started_Nested := Square > 0 or else Curly > 0;
            Header_Mode := False;
            Saw_Equals := False;
         elsif Clean (Position) in ''' | '"' then
            if Square > 0 then Begin_Value; end if;
            In_String := True;
            Quote := Clean (Position);
            Escaped := False;
         elsif Clean (Position) = '=' then
            Saw_Equals := True;
         elsif Clean (Position) = '[' then
            if not Header_Mode then
               declare
                  First : constant Natural := First_Nonblank (Line_Start, Position);
               begin
                  Header_Mode := Square = 0 and then Curly = 0 and then not Saw_Equals and then First = Position;
                  if not Header_Mode then
                     Begin_Value;
                     if Square = Maximum_Depth then return False; end if;
                     Square := Square + 1;
                     Expect_Value (Square) := True;
                     Had_Value (Square) := False;
                  end if;
               end;
            end if;
         elsif Clean (Position) = ']' then
            if Header_Mode and then Square = 0 then
               null;
            elsif Square = 0 then
               return False;
            else
               Square := Square - 1;
            end if;
         elsif Clean (Position) = '{' then
            Begin_Value;
            if Curly = Maximum_Depth then return False; end if;
            Curly := Curly + 1;
         elsif Clean (Position) = '}' then
            if Curly = 0 then return False; end if;
            Curly := Curly - 1;
         elsif Clean (Position) = ',' and then Square > 0 and then Curly = 0 then
            if Expect_Value (Square) or else not Had_Value (Square) then return False; end if;
            Expect_Value (Square) := True;
         elsif Square > 0 and then Curly = 0 and then
           Clean (Position) not in ' ' | Ada.Characters.Latin_1.HT | Ada.Characters.Latin_1.CR
         then
            if Expect_Value (Square) then
               Expect_Value (Square) := False;
               Had_Value (Square) := True;
            end if;
         end if;
         Position := Position + 1;
      end loop;
      return not In_String and then Square = 0 and then Curly = 0 and then
        Complete_Line (Clean'Last);
   exception
      when Constraint_Error => return False;
   end Is_Valid;

   function Top_Level_Assignment
     (Text, Key : String;
      First, Last : out Natural) return Boolean
   is
      Clean : constant String := Without_Comments (Text);
      Start : Natural := Clean'First;
   begin
      First := 0;
      Last := 0;
      while Start <= Clean'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index (Clean, [Ada.Characters.Latin_1.LF], From => Start);
            Head : Natural := Start;
         begin
            if Stop = 0 then Stop := Clean'Last + 1; end if;
            while Head < Stop and then Clean (Head) in ' ' | Ada.Characters.Latin_1.HT | Ada.Characters.Latin_1.CR loop
               Head := Head + 1;
            end loop;
            if Head < Stop and then Clean (Head) = '[' then return False; end if;
            if Head + Key'Length <= Stop and then Clean (Head .. Head + Key'Length - 1) = Key then
               declare
                  Cursor : Natural := Head + Key'Length;
               begin
                  while Cursor < Stop and then Clean (Cursor) in ' ' | Ada.Characters.Latin_1.HT loop
                     Cursor := Cursor + 1;
                  end loop;
                  if Cursor < Stop and then Clean (Cursor) = '=' then
                     First := Head;
                     Last := Stop - 1;
                     return True;
                  end if;
               end;
            end if;
            exit when Stop > Clean'Last;
            Start := Stop + 1;
         end;
      end loop;
      return False;
   end Top_Level_Assignment;

   function Top_Level_String
     (Text, Key : String;
      Value     : out Unbounded_String) return Boolean
   is
      First, Last : Natural;
   begin
      Value := Null_Unbounded_String;
      if not Is_Valid (Text) or else not Top_Level_Assignment (Text, Key, First, Last) then
         return False;
      end if;
      declare
         Parsed : constant Project_Tools.TOML.String_Parse_Result :=
           Project_Tools.TOML.Parse_String_After (Text (First .. Last), Key, First);
      begin
         if Parsed.Status /= Project_Tools.TOML.Parsed_String or else Length (Parsed.Value) = 0 then
            return False;
         end if;
         Value := Parsed.Value;
         return True;
      end;
   end Top_Level_String;

   function Top_Level_String_Array
     (Text, Key : String;
      Values    : out String_Vectors.Vector) return Boolean
   is
      Clean : constant String := Without_Comments (Text);
      First, Line_Last : Natural;
      Open_At, Position : Natural;
      Expect_Value : Boolean := True;
   begin
      Values.Clear;
      if not Is_Valid (Text) or else not Top_Level_Assignment (Text, Key, First, Line_Last) then
         return False;
      end if;
      Open_At := Ada.Strings.Fixed.Index (Clean, "[", From => First);
      if Open_At = 0 then return False; end if;
      Position := Open_At + 1;
      while Position <= Clean'Last loop
         while Position <= Clean'Last and then
           Clean (Position) in ' ' | Ada.Characters.Latin_1.HT | Ada.Characters.Latin_1.CR |
             Ada.Characters.Latin_1.LF
         loop
            Position := Position + 1;
         end loop;
         if Position > Clean'Last then return False;
         elsif Clean (Position) = ']' then
            return not Values.Is_Empty;
         elsif not Expect_Value or else Clean (Position) not in ''' | '"' then
            return False;
         end if;
         declare
            Quote : constant Character := Clean (Position);
            Start : constant Natural := Position + 1;
         begin
            Position := Start;
            while Position <= Clean'Last and then Clean (Position) /= Quote loop
               if Quote = '"' and then Clean (Position) = '\' and then Position < Clean'Last then
                  Position := Position + 1;
               end if;
               Position := Position + 1;
            end loop;
            if Position > Clean'Last or else Position = Start then return False; end if;
            Values.Append (To_Unbounded_String (Clean (Start .. Position - 1)));
            Position := Position + 1;
            Expect_Value := False;
         end;
         while Position <= Clean'Last and then
           Clean (Position) in ' ' | Ada.Characters.Latin_1.HT | Ada.Characters.Latin_1.CR |
             Ada.Characters.Latin_1.LF
         loop
            Position := Position + 1;
         end loop;
         if Position > Clean'Last then return False;
         elsif Clean (Position) = ',' then
            Expect_Value := True;
            Position := Position + 1;
         elsif Clean (Position) /= ']' then
            return False;
         end if;
      end loop;
      return False;
   end Top_Level_String_Array;
end Ada_Quality.Manifests;
