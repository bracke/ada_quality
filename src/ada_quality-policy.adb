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

   function Load (Path : String) return Load_Result is
      Result  : Load_Result := (Success => True, Value => Default, Error => Null_Unbounded_String);
      Content : Unbounded_String;
      Start   : Positive := 1;
      type Policy_Key is
        (Coverage_Key, Source_Lines_Key, Complexity_Key, Timeout_Key, Output_Key, Clean_Key);
      Seen : array (Policy_Key) of Boolean := [others => False];

      procedure Mark (Key : Policy_Key) is
      begin
         if Seen (Key) then raise Constraint_Error with "duplicate policy key"; end if;
         Seen (Key) := True;
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
               Result.Value.Require_Clean_Worktree := Boolean'Value (Value);
         end case;
      end Assign;

      procedure Apply (Line : String) is
         Clean : constant String := Trim (Line);
         Eq    : Natural := 0;
      begin
         if Clean'Length = 0 or else Clean (Clean'First) = '#' or else Clean (Clean'First) = '[' then
            return;
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
         return (Success => False, Value => Default, Error => To_Unbounded_String ("policy file not found: " & Path));
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
   end Load;

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
