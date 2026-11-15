with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body Ada_Quality.Source_Safety is
   use Ada.Strings.Unbounded;

   function Lower (Text : String) return String is
     (Ada.Characters.Handling.To_Lower (Text));

   function Is_Identifier_Character (Value : Character) return Boolean is
     (Value in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' or else Value = '_');

   function Ends_With (Text, Suffix : String) return Boolean is
     (Text'Length >= Suffix'Length and then
      Text (Text'Last - Suffix'Length + 1 .. Text'Last) = Suffix);

   function Is_Shell_Literal (Value : String) return Boolean is
      Text : constant String := Lower (Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both));
      type String_Access is access constant String;
      Suffixes : constant array (Positive range <>) of String_Access :=
        [new String'("/sh"), new String'("/bash"), new String'("/dash"), new String'("/ksh"),
         new String'("/zsh"), new String'("/csh"), new String'("/tcsh"), new String'("/fish")];
   begin
      if Text in "sh" | "bash" | "dash" | "ksh" | "zsh" | "csh" | "tcsh" |
          "fish" | "cmd" | "cmd.exe" | "powershell" | "powershell.exe" | "pwsh"
      then
         return True;
      end if;
      for Suffix of Suffixes loop
         if Ends_With (Text, Suffix.all) then return True; end if;
      end loop;
      return
        (Text'Length > 3 and then Text (Text'First .. Text'First + 2) = "sh ") or else
        (Text'Length > 5 and then Text (Text'First .. Text'First + 4) = "bash ") or else
        (Text'Length > 11 and then Text (Text'First .. Text'First + 10) = "powershell ") or else
        (Text'Length > 5 and then Text (Text'First .. Text'First + 4) = "pwsh ");
   end Is_Shell_Literal;

   function Is_Shell_API (Value : String) return Boolean is
      Name : constant String := Lower (Value);
   begin
      return Name in "run_shell" | "spawn_shell" | "shell_execute" | "system" |
        "popen" | "execlp";
   end Is_Shell_API;

   function Is_Process_Context (Value : String) return Boolean is
      Name : constant String := Lower (Value);
   begin
      return Name in "argument" | "arguments" | "capture" | "spawn" | "run" |
        "execute" | "program" | "command";
   end Is_Process_Context;

   function Consume_String (Line : String; Position : in out Natural) return Boolean is
      Value  : Unbounded_String;
      Closed : Boolean := False;
   begin
      Position := Position + 1;
      while Position <= Line'Last loop
         if Line (Position) = '"' then
            if Position < Line'Last and then Line (Position + 1) = '"' then
               Append (Value, '"');
               Position := Position + 2;
            else
               Closed := True;
               Position := Position + 1;
               exit;
            end if;
         else
            Append (Value, Line (Position));
            Position := Position + 1;
         end if;
      end loop;
      return Closed and then Is_Shell_Literal (To_String (Value));
   end Consume_String;

   procedure Consume_Identifier
     (Line            : String;
      Position        : in out Natural;
      Shell_API       : out Boolean;
      Process_Context : out Boolean)
   is
      First : constant Natural := Position;
   begin
      while Position <= Line'Last and then Is_Identifier_Character (Line (Position)) loop
         Position := Position + 1;
      end loop;
      Shell_API := Is_Shell_API (Line (First .. Position - 1));
      Process_Context := Is_Process_Context (Line (First .. Position - 1));
   end Consume_Identifier;

   function Contains_Shell_Invocation (Line : String) return Boolean is
      Position        : Natural := Line'First;
      Shell_Literal   : Boolean := False;
      Process_Context : Boolean := False;
   begin
      while Position <= Line'Last loop
         if Position < Line'Last and then Line (Position .. Position + 1) = "--" then
            exit;
         elsif Line (Position) = '"' then
            Shell_Literal := Consume_String (Line, Position) or else Shell_Literal;
         elsif Is_Identifier_Character (Line (Position)) then
            declare
               Found_API, Found_Context : Boolean;
            begin
               Consume_Identifier (Line, Position, Found_API, Found_Context);
               if Found_API then return True; end if;
               Process_Context := Found_Context or else Process_Context;
            end;
         else
            Position := Position + 1;
         end if;
      end loop;
      return Shell_Literal and then Process_Context;
   end Contains_Shell_Invocation;
end Ada_Quality.Source_Safety;
