separate (Ada_Quality.Checks)
   procedure Parse_SPDX
     (Text : String;
      Valid, Supported : out Boolean;
      Licenses, Exceptions : out Text_Vectors.Vector)
   is
      Tokens  : Text_Vectors.Vector;
      Current : Ada.Strings.Unbounded.Unbounded_String;
      Position : Natural := 1;

      procedure Flush is
      begin
         if Length (Current) > 0 then
            Tokens.Append (Current);
            Current := Null_Unbounded_String;
         end if;
      end Flush;

      function Token return String is (To_String (Tokens (Positive (Position))));
      function Available return Boolean is (Position <= Natural (Tokens.Length));
      function Supported_License (Value : String) return Boolean is
        (Value in "MIT" | "Apache-2.0" | "BSD-3-Clause" | "CC0-1.0");
      function Supported_Exception (Value : String) return Boolean is
        (Value = "LLVM-exception");

      procedure Parse_Or;

      procedure Parse_Primary is
      begin
         if not Available then
            Valid := False;
         elsif Token = "(" then
            Position := Position + 1;
            Parse_Or;
            if not Available or else Token /= ")" then
               Valid := False;
            else
               Position := Position + 1;
            end if;
         elsif Token in ")" | "AND" | "OR" | "WITH" then
            Valid := False;
         else
            Supported := Supported and then Supported_License (Token);
            Licenses.Append (To_Unbounded_String (Token));
            Position := Position + 1;
         end if;
      end Parse_Primary;

      procedure Parse_With is
      begin
         Parse_Primary;
         if Valid and then Available and then Token = "WITH" then
            Position := Position + 1;
            if not Available or else Token in "(" | ")" | "AND" | "OR" | "WITH" then
               Valid := False;
            else
               Supported := Supported and then Supported_Exception (Token);
               Exceptions.Append (To_Unbounded_String (Token));
               Position := Position + 1;
            end if;
         end if;
      end Parse_With;

      procedure Parse_And is
      begin
         Parse_With;
         while Valid and then Available and then Token = "AND" loop
            Position := Position + 1;
            Parse_With;
         end loop;
      end Parse_And;

      procedure Parse_Or is
      begin
         Parse_And;
         while Valid and then Available and then Token = "OR" loop
            Position := Position + 1;
            Parse_And;
         end loop;
      end Parse_Or;
   begin
      for C of Text loop
         if C in ' ' | Character'Val (9) | ASCII.CR | ASCII.LF then
            Flush;
         elsif C in '(' | ')' then
            Flush;
            Tokens.Append (To_Unbounded_String ([C]));
         else
            Append (Current, C);
         end if;
      end loop;
      Flush;
      Valid := not Tokens.Is_Empty;
      Supported := True;
      if Valid then Parse_Or; end if;
      Valid := Valid and then not Available;
   end Parse_SPDX;
