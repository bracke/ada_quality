with Ada.Characters.Latin_1;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Interfaces;
with Project_Tools.Files;

package body Ada_Quality.Policy is
   use Ada.Strings.Unbounded;
   use type Interfaces.Unsigned_64;

   function Default return Quality_Policy is (others => <>);

   function Trim (Text : String) return String is
     (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));

   function Load_Overlay
     (Path : String; Base : Quality_Policy) return Load_Result is
      Result  : Load_Result :=
        (Success => True, Value => Base, Present => (others => False),
         Error => Null_Unbounded_String);
      Content : Unbounded_String;
      Start   : Positive := 1;
      type Policy_Key is
        (Coverage_Key, Source_Lines_Key, Complexity_Key, Timeout_Key, Output_Key, Clean_Key);
      Seen : array (Policy_Key) of Boolean := [others => False];

      procedure Mark (Key : Policy_Key) is
      begin
         if Seen (Key) then raise Constraint_Error with "duplicate policy key"; end if;
         Seen (Key) := True;
         case Key is
            when Coverage_Key => Result.Present.Coverage_Minimum_Basis_Points := True;
            when Source_Lines_Key => Result.Present.Maximum_Source_Lines := True;
            when Complexity_Key => Result.Present.Maximum_Complexity := True;
            when Timeout_Key => Result.Present.Process_Timeout_Seconds := True;
            when Output_Key => Result.Present.Maximum_Output_Bytes := True;
            when Clean_Key => Result.Present.Require_Clean_Worktree := True;
         end case;
      end Mark;

      function Parse_Key (Text : String) return Policy_Key is
      begin
         if Text = "coverage_minimum_basis_points" then return Coverage_Key;
         elsif Text = "maximum_source_lines" then return Source_Lines_Key;
         elsif Text = "maximum_complexity" then return Complexity_Key;
         elsif Text = "process_timeout_seconds" then return Timeout_Key;
         elsif Text = "maximum_output_bytes" then return Output_Key;
         elsif Text = "require_clean_worktree" then return Clean_Key;
         else raise Constraint_Error with "unknown policy key: " & Text;
         end if;
      end Parse_Key;

      procedure Assign (Key : Policy_Key; Value : String) is
      begin
         Mark (Key);
         case Key is
            when Coverage_Key =>
               Result.Value.Coverage_Minimum_Basis_Points := Natural'Value (Value);
               if Result.Value.Coverage_Minimum_Basis_Points > 10_000 then raise Constraint_Error; end if;
            when Source_Lines_Key =>
               Result.Value.Maximum_Source_Lines := Positive'Value (Value);
               if Result.Value.Maximum_Source_Lines > 1_000_000 then raise Constraint_Error; end if;
            when Complexity_Key =>
               Result.Value.Maximum_Complexity := Positive'Value (Value);
               if Result.Value.Maximum_Complexity > 10_000 then raise Constraint_Error; end if;
            when Timeout_Key =>
               Result.Value.Process_Timeout_Seconds := Positive'Value (Value);
               if Result.Value.Process_Timeout_Seconds > 3_600 then raise Constraint_Error; end if;
            when Output_Key =>
               Result.Value.Maximum_Output_Bytes := Positive'Value (Value);
               if Result.Value.Maximum_Output_Bytes > 16 * 1_024 * 1_024 then raise Constraint_Error; end if;
            when Clean_Key =>
               if Value not in "true" | "false" then
                  raise Constraint_Error with "policy booleans must be TOML true or false";
               end if;
               Result.Value.Require_Clean_Worktree := Boolean'Value (Value);
         end case;
      end Assign;

      function Without_Comment (Line : String) return String is
         In_String : Boolean := False;
         Quote     : Character := Character'Val (0);
         Escaped   : Boolean := False;
      begin
         for J in Line'Range loop
            if In_String then
               if Line (J) = Quote and then not Escaped then
                  In_String := False;
               end if;
               Escaped := Line (J) = '\' and then not Escaped;
            elsif Line (J) in ''' | '"' then
               In_String := True;
               Quote := Line (J);
               Escaped := False;
            elsif Line (J) = '#' then
               return (if J = Line'First then "" else Line (Line'First .. J - 1));
            end if;
         end loop;
         if In_String then
            raise Constraint_Error with "unterminated TOML string";
         end if;
         return Line;
      end Without_Comment;

      procedure Apply (Line : String) is
         Clean : constant String := Trim (Without_Comment (Line));
         Eq    : Natural := 0;
      begin
         if Clean'Length = 0 then
            return;
         elsif Clean (Clean'First) = '[' then
            raise Constraint_Error with "policy sections are not supported";
         end if;
         for J in Clean'Range loop
            if Clean (J) = '=' then Eq := J; exit; end if;
         end loop;
         if Eq = 0 then
            raise Constraint_Error with "expected key = value";
         end if;
         declare
            Key : constant Policy_Key := Parse_Key (Trim (Clean (Clean'First .. Eq - 1)));
            Val : constant String := Trim (Clean (Eq + 1 .. Clean'Last));
         begin
            Assign (Key, Val);
         end;
      end Apply;
   begin
      if not Project_Tools.Files.File_Exists (Path) then
         return
           (Success => False, Value => Base, Present => (others => False),
            Error => To_Unbounded_String ("policy file not found: " & Path));
      end if;

      Content := To_Unbounded_String (Project_Tools.Files.Read_Raw_File (Path));
      declare
         Text : constant String := To_String (Content);
      begin
         if Text'Length > 0 then
            for J in Text'Range loop
               if Text (J) = Ada.Characters.Latin_1.LF then
                  if J > Start then Apply (Text (Start .. J - 1)); end if;
                  Start := J + 1;
               end if;
            end loop;
            if Start <= Text'Last then Apply (Text (Start .. Text'Last)); end if;
         end if;
      end;
      return Result;
   exception
      when E : others =>  --  AQ: audited exception boundary
         Result.Success := False;
         Result.Error := To_Unbounded_String (Ada.Exceptions.Exception_Message (E));
         return Result;
   end Load_Overlay;

   function Load (Path : String) return Load_Result is
     (Load_Overlay (Path, Default));

   function Profile_Path (Base_Path, Name : String) return String is
      Dot : Natural := 0;
   begin
      if Name = "" then return Base_Path; end if;
      for Index in reverse Base_Path'Range loop
         if Base_Path (Index) = '.' then Dot := Index; exit; end if;
      end loop;
      return
        (if Dot > Base_Path'First
         then Base_Path (Base_Path'First .. Dot - 1) & "." & Name & Base_Path (Dot .. Base_Path'Last)
         else Base_Path & "." & Name);
   end Profile_Path;

   function Is_Profile_Name (Name : String) return Boolean is
     (Name'Length in 1 .. 64 and then
      (for all C of Name => C in 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '-'));

   function Render (Item : Quality_Policy) return String is
      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
   begin
      return
        ("coverage_minimum_basis_points = " & Image (Item.Coverage_Minimum_Basis_Points) & ASCII.LF &
         "maximum_source_lines = " & Image (Item.Maximum_Source_Lines) & ASCII.LF &
         "maximum_complexity = " & Image (Item.Maximum_Complexity) & ASCII.LF &
         "process_timeout_seconds = " & Image (Item.Process_Timeout_Seconds) & ASCII.LF &
         "maximum_output_bytes = " & Image (Item.Maximum_Output_Bytes) & ASCII.LF &
         "require_clean_worktree = " &
           (if Item.Require_Clean_Worktree then "true" else "false") & ASCII.LF);
   end Render;

   function Explain
     (Item : Quality_Policy; Sources : Key_Presence;
      Base_Source, Overlay_Source : String) return String
   is
      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
      function Source (Overlay : Boolean) return String is
        (if Overlay then Overlay_Source else Base_Source);
   begin
      return
        "coverage_minimum_basis_points = " & Image (Item.Coverage_Minimum_Basis_Points) &
          "    # from " & Source (Sources.Coverage_Minimum_Basis_Points) & ASCII.LF &
        "maximum_source_lines = " & Image (Item.Maximum_Source_Lines) &
          "    # from " & Source (Sources.Maximum_Source_Lines) & ASCII.LF &
        "maximum_complexity = " & Image (Item.Maximum_Complexity) &
          "    # from " & Source (Sources.Maximum_Complexity) & ASCII.LF &
        "process_timeout_seconds = " & Image (Item.Process_Timeout_Seconds) &
          "    # from " & Source (Sources.Process_Timeout_Seconds) & ASCII.LF &
        "maximum_output_bytes = " & Image (Item.Maximum_Output_Bytes) &
          "    # from " & Source (Sources.Maximum_Output_Bytes) & ASCII.LF &
        "require_clean_worktree = " &
          (if Item.Require_Clean_Worktree then "true" else "false") &
          "    # from " & Source (Sources.Require_Clean_Worktree) & ASCII.LF;
   end Explain;

   function Diff (Left, Right : Quality_Policy) return String is
      Result : Unbounded_String;
      procedure Add (Key, Before, After : String) is
      begin
         Append (Result, Key & ": " & Before & " -> " & After & ASCII.LF);
      end Add;
      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
   begin
      if Left.Coverage_Minimum_Basis_Points /= Right.Coverage_Minimum_Basis_Points then
         Add ("coverage_minimum_basis_points", Image (Left.Coverage_Minimum_Basis_Points),
              Image (Right.Coverage_Minimum_Basis_Points));
      end if;
      if Left.Maximum_Source_Lines /= Right.Maximum_Source_Lines then
         Add ("maximum_source_lines", Image (Left.Maximum_Source_Lines), Image (Right.Maximum_Source_Lines));
      end if;
      if Left.Maximum_Complexity /= Right.Maximum_Complexity then
         Add ("maximum_complexity", Image (Left.Maximum_Complexity), Image (Right.Maximum_Complexity));
      end if;
      if Left.Process_Timeout_Seconds /= Right.Process_Timeout_Seconds then
         Add ("process_timeout_seconds", Image (Left.Process_Timeout_Seconds),
              Image (Right.Process_Timeout_Seconds));
      end if;
      if Left.Maximum_Output_Bytes /= Right.Maximum_Output_Bytes then
         Add ("maximum_output_bytes", Image (Left.Maximum_Output_Bytes), Image (Right.Maximum_Output_Bytes));
      end if;
      if Left.Require_Clean_Worktree /= Right.Require_Clean_Worktree then
         Add ("require_clean_worktree", Boolean'Image (Left.Require_Clean_Worktree),
              Boolean'Image (Right.Require_Clean_Worktree));
      end if;
      return (if Length (Result) = 0 then "no policy differences" & ASCII.LF else To_String (Result));
   end Diff;

   function Fingerprint (Item : Quality_Policy) return String is
      Text : constant String :=
        Natural'Image (Item.Coverage_Minimum_Basis_Points) & ":" &
        Positive'Image (Item.Maximum_Source_Lines) & ":" & Positive'Image (Item.Maximum_Complexity) & ":" &
        Positive'Image (Item.Process_Timeout_Seconds) & ":" & Positive'Image (Item.Maximum_Output_Bytes) & ":" &
        Boolean'Image (Item.Require_Clean_Worktree);
      Hash : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
   begin
      for C of Text loop
         Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
      end loop;
      return Interfaces.Unsigned_64'Image (Hash);
   end Fingerprint;
end Ada_Quality.Policy;
