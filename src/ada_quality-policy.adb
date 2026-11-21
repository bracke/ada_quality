with Ada.Characters.Latin_1;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Interfaces;
with Project_Tools.Files;
with Ada_Quality.Bounded_Files;
with Ada_Quality.Resource_Limits;

package body Ada_Quality.Policy is
   use Ada.Strings.Unbounded;
   use type Interfaces.Unsigned_64;

   function Default return Quality_Policy is (others => <>);

   function Trim (Text : String) return String is
     (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));

   function Name (Key : Policy_Key) return String is
     (case Key is
         when Coverage_Minimum_Key => "coverage_minimum_basis_points",
         when Source_Lines_Key     => "maximum_source_lines",
         when Complexity_Key       => "maximum_complexity",
         when Timeout_Key          => "process_timeout_seconds",
         when Output_Key           => "maximum_output_bytes",
         when Clean_Worktree_Key   => "require_clean_worktree");

   function Is_Boolean (Key : Policy_Key) return Boolean is
     (Key = Clean_Worktree_Key);

   function Natural_Value
     (Item : Quality_Policy; Key : Policy_Key) return Natural is
     (case Key is
         when Coverage_Minimum_Key => Item.Coverage_Minimum_Basis_Points,
         when Source_Lines_Key     => Item.Maximum_Source_Lines,
         when Complexity_Key       => Item.Maximum_Complexity,
         when Timeout_Key          => Item.Process_Timeout_Seconds,
         when Output_Key           => Item.Maximum_Output_Bytes,
         when Clean_Worktree_Key   => raise Constraint_Error);

   function Boolean_Value
     (Item : Quality_Policy; Key : Policy_Key) return Boolean is
     (case Key is
         when Clean_Worktree_Key => Item.Require_Clean_Worktree,
         when others             => raise Constraint_Error);

   function Value_Image (Item : Quality_Policy; Key : Policy_Key) return String is
     (if Is_Boolean (Key)
      then (if Boolean_Value (Item, Key) then "true" else "false")
      else Trim (Natural'Image (Natural_Value (Item, Key))));

   function Changed
     (Left, Right : Quality_Policy; Key : Policy_Key) return Boolean is
     (if Is_Boolean (Key)
      then Boolean_Value (Left, Key) /= Boolean_Value (Right, Key)
      else Natural_Value (Left, Key) /= Natural_Value (Right, Key));

   function Is_Present (Sources : Key_Presence; Key : Policy_Key) return Boolean is
     (case Key is
         when Coverage_Minimum_Key => Sources.Coverage_Minimum_Basis_Points,
         when Source_Lines_Key     => Sources.Maximum_Source_Lines,
         when Complexity_Key       => Sources.Maximum_Complexity,
         when Timeout_Key          => Sources.Process_Timeout_Seconds,
         when Output_Key           => Sources.Maximum_Output_Bytes,
         when Clean_Worktree_Key   => Sources.Require_Clean_Worktree);

   function Affected_Indicators (Key : Policy_Key) return String is
     (case Key is
         when Coverage_Minimum_Key => "TST-03",
         when Source_Lines_Key     => "SRC-06",
         when Complexity_Key       => "SRC-03",
         when Timeout_Key | Output_Key =>
           "BLD-01,BLD-02,TST-01,TST-03,TST-04,DOC-02,DEP-01,REL-01,PRF-01",
         when Clean_Worktree_Key => "REL-04");

   function Load_Overlay
     (Path : String; Base : Quality_Policy) return Load_Result is
      Result  : Load_Result :=
        (Success => True, Value => Base, Present => (others => False),
         Error => Null_Unbounded_String);
      Content : Unbounded_String;
      Start   : Positive := 1;
      Seen : array (Policy_Key) of Boolean := [others => False];

      procedure Mark (Key : Policy_Key) is
      begin
         if Seen (Key) then raise Constraint_Error with "duplicate policy key"; end if;
         Seen (Key) := True;
         case Key is
            when Coverage_Minimum_Key => Result.Present.Coverage_Minimum_Basis_Points := True;
            when Source_Lines_Key => Result.Present.Maximum_Source_Lines := True;
            when Complexity_Key => Result.Present.Maximum_Complexity := True;
            when Timeout_Key => Result.Present.Process_Timeout_Seconds := True;
            when Output_Key => Result.Present.Maximum_Output_Bytes := True;
            when Clean_Worktree_Key => Result.Present.Require_Clean_Worktree := True;
         end case;
      end Mark;

      function Parse_Key (Text : String) return Policy_Key is
      begin
         for Key in Policy_Key loop
            if Text = Name (Key) then return Key; end if;
         end loop;
         raise Constraint_Error with "unknown policy key: " & Text;
      end Parse_Key;

      procedure Assign (Key : Policy_Key; Value : String) is
      begin
         Mark (Key);
         case Key is
            when Coverage_Minimum_Key =>
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
            when Clean_Worktree_Key =>
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

      Content := To_Unbounded_String
        (Ada_Quality.Bounded_Files.Read
           (Path, Ada_Quality.Resource_Limits.Maximum_File_Bytes));
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
      Result : Unbounded_String;
   begin
      for Key in Policy_Key loop
         Append (Result, Name (Key) & " = " & Value_Image (Item, Key) & ASCII.LF);
      end loop;
      return To_String (Result);
   end Render;

   function Explain
     (Item : Quality_Policy; Sources : Key_Presence;
      Base_Source, Overlay_Source : String) return String
   is
      function Source (Overlay : Boolean) return String is
        (if Overlay then Overlay_Source else Base_Source);
      Result : Unbounded_String;
   begin
      for Key in Policy_Key loop
         Append
           (Result, Name (Key) & " = " & Value_Image (Item, Key) &
              "    # from " & Source (Is_Present (Sources, Key)) & ASCII.LF);
      end loop;
      return To_String (Result);
   end Explain;

   function Diff (Left, Right : Quality_Policy) return String is
      Result : Unbounded_String;
      procedure Add (Key, Before, After : String) is
      begin
         Append (Result, Key & ": " & Before & " -> " & After & ASCII.LF);
      end Add;
      function Diff_Image (Item : Quality_Policy; Key : Policy_Key) return String is
        (if Is_Boolean (Key)
         then Boolean'Image (Boolean_Value (Item, Key))
         else Value_Image (Item, Key));
   begin
      for Key in Policy_Key loop
         if Changed (Left, Right, Key) then
            Add (Name (Key), Diff_Image (Left, Key), Diff_Image (Right, Key));
         end if;
      end loop;
      return (if Length (Result) = 0 then "no policy differences" & ASCII.LF else To_String (Result));
   end Diff;

   function Fingerprint (Item : Quality_Policy) return String is
      Text : Unbounded_String;
      Hash : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
   begin
      for Key in Policy_Key loop
         if Key /= Policy_Key'First then Append (Text, ":"); end if;
         Append
           (Text,
            (if Is_Boolean (Key)
             then Boolean'Image (Boolean_Value (Item, Key))
             else Natural'Image (Natural_Value (Item, Key))));
      end loop;
      for C of To_String (Text) loop
         Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
      end loop;
      return Interfaces.Unsigned_64'Image (Hash);
   end Fingerprint;
end Ada_Quality.Policy;
