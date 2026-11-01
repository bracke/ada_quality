with Ada.Directories;
with Ada.Containers.Vectors;
with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Project_Tools.Files;
with Project_Tools.Links;

package body Ada_Quality.Workspaces is
   --  AQ: complexity-reviewed -- bounded Alire pin parsing is decomposed and fixture-covered.
   use Ada.Strings.Unbounded;
   use type Ada.Directories.File_Kind;

   package Path_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String);

   function Skipped (Name : String) return Boolean is
     (Name in ".git" | ".alire" | "obj" | "bin" | "cov-obj" | "cov-bin" | "lib" | "gnatprove");

   procedure Prepare (Item : in out Workspace; Source : String; Identity : String) is
      Canonical_Source : constant String := Ada.Directories.Full_Name (Source);
      Seen : Path_Vectors.Vector;

      procedure Copy_Tree (From, Into : String) is
         Search      : Ada.Directories.Search_Type;
         Search_Open : Boolean := False;
         Item        : Ada.Directories.Directory_Entry_Type;
      begin
         if Project_Tools.Links.Is_Link (From) then
            raise Workspace_Error with "symbolic link rejected while staging: " & From;
         end if;
         Ada.Directories.Create_Path (Into);
         Ada.Directories.Start_Search (Search, From, "");
         Search_Open := True;
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            declare
               Name        : constant String := Ada.Directories.Simple_Name (Item);
               Source_Path : constant String := From & "/" & Name;
               Target_Path : constant String := Into & "/" & Name;
            begin
               if Name = "." or else Name = ".." or else Skipped (Name) then
                  null;
               elsif Project_Tools.Links.Is_Link (Source_Path) then
                  raise Workspace_Error with "symbolic link rejected while staging: " & Source_Path;
               elsif Name = "alire" and then Ada.Directories.Kind (Item) = Ada.Directories.Directory then
                  declare
                     Lockfile : constant String := Source_Path & "/alire.lock";
                  begin
                     if Project_Tools.Files.File_Exists (Lockfile) then
                        Ada.Directories.Create_Path (Target_Path);
                        Ada.Directories.Copy_File
                          (Lockfile, Target_Path & "/alire.lock", Form => "mode=overwrite");
                     end if;
                  end;
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Directory then
                  Copy_Tree (Source_Path, Target_Path);
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Ordinary_File then
                  Ada.Directories.Copy_File (Source_Path, Target_Path, Form => "mode=overwrite");
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         Search_Open := False;
      exception
         when others =>  --  AQ: audited exception boundary
            if Search_Open then Ada.Directories.End_Search (Search); end if;
            raise;
      end Copy_Tree;

      function Seen_Before (Path : String) return Boolean is
      begin
         for Value of Seen loop
            if To_String (Value) = Path then return True; end if;
         end loop;
         return False;
      end Seen_Before;

      function Safe_Relative_Pin (Path : String) return Boolean is
         Tail : constant String :=
           (if Path'Length >= 3 and then Path (Path'First .. Path'First + 2) = "../"
            then Path (Path'First + 3 .. Path'Last) else Path);
      begin
         return Path'Length > 0 and then Path (Path'First) /= '/' and then
           Tail'Length > 0 and then Ada.Strings.Fixed.Index (Tail, "../") = 0 and then
           (Tail'Length < 2 or else Tail (Tail'Last - 1 .. Tail'Last) /= "..");
      end Safe_Relative_Pin;

      procedure Copy_Crate (From, Into : String);

      procedure Copy_Pins (Canonical, Into, Manifest : String) is
         Data : constant String := Project_Tools.Files.Read_Raw_File (Manifest);
         type Section_Kind is (Other_Section, Pins_Section, Solution_Link_Section);
         Section         : Section_Kind := Other_Section;
         Multiline_Quote : Character := Character'Val (0);

         function Key_Character (Value : Character) return Boolean is
           (Value in 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' or else Value in '_' | '-');

         procedure Copy_Pin (Relative : String) is
         begin
            if not Safe_Relative_Pin (Relative) then
               raise Workspace_Error with
                 "local pin path must remain inside the isolated staging container";
            end if;
            declare
               Dependency : constant String := Ada.Directories.Full_Name (Canonical & "/" & Relative);
            begin
               if not Project_Tools.Files.Directory_Exists (Dependency) then
                  raise Workspace_Error with "local pin target is not a directory: " & Dependency;
               elsif Project_Tools.Links.Is_Link (Dependency) then
                  raise Workspace_Error with "local pin target is a symbolic link: " & Dependency;
               end if;
               Copy_Crate (Dependency, Into & "/" & Relative);
            end;
         end Copy_Pin;

         function Trim (Text : String) return String is
           (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));

         procedure Skip_Whitespace (Text : String; Position : in out Natural) is
         begin
            while Position <= Text'Last and then Text (Position) in ' ' | Character'Val (9) |
              Ada.Characters.Latin_1.CR
            loop
               Position := Position + 1;
            end loop;
         end Skip_Whitespace;

         function Triple_At (Text : String; Position : Positive; Quote : Character) return Boolean is
           (Position + 2 <= Text'Last and then Text (Position .. Position + 2) = [Quote, Quote, Quote]);

         function Sanitized (Line : String) return String is
            Result   : String := Line;
            Position : Natural := Line'First;
            Quote    : Character := Character'Val (0);
            Escaped  : Boolean := False;
         begin
            while Position <= Line'Last loop
               if Multiline_Quote /= Character'Val (0) then
                  if Triple_At (Line, Position, Multiline_Quote) then
                     Result (Position .. Position + 2) := [others => ' '];
                     Position := Position + 3;
                     Multiline_Quote := Character'Val (0);
                  else
                     Result (Position) := ' ';
                     Position := Position + 1;
                  end if;
               elsif Quote /= Character'Val (0) then
                  if Line (Position) = Quote and then (Quote = ''' or else not Escaped) then
                     Quote := Character'Val (0);
                     Escaped := False;
                  elsif Quote = '"' then
                     Escaped := Line (Position) = '\' and then not Escaped;
                  end if;
                  Position := Position + 1;
               elsif Line (Position) = '#' then
                  Result (Position .. Result'Last) := [others => ' '];
                  exit;
               elsif Line (Position) in ''' | '"' and then Triple_At (Line, Position, Line (Position)) then
                  Multiline_Quote := Line (Position);
                  Result (Position .. Position + 2) := [others => ' '];
                  Position := Position + 3;
               elsif Line (Position) in ''' | '"' then
                  Quote := Line (Position);
                  Escaped := False;
                  Position := Position + 1;
               else
                  Position := Position + 1;
               end if;
            end loop;
            if Quote /= Character'Val (0) then
               raise Workspace_Error with "unterminated TOML string in " & Manifest;
            end if;
            return Result;
         end Sanitized;

         function Compact (Text : String) return String is
            Result : Unbounded_String;
         begin
            for Value of Text loop
               if Value not in ' ' | Character'Val (9) | Ada.Characters.Latin_1.CR then
                  Append (Result, Value);
               end if;
            end loop;
            return To_String (Result);
         end Compact;

         function Hex_Value (Value : Character) return Natural is
         begin
            if Value in '0' .. '9' then
               return Character'Pos (Value) - Character'Pos ('0');
            elsif Value in 'a' .. 'f' then
               return Character'Pos (Value) - Character'Pos ('a') + 10;
            elsif Value in 'A' .. 'F' then
               return Character'Pos (Value) - Character'Pos ('A') + 10;
            end if;
            raise Workspace_Error with "invalid Unicode escape in local pin path in " & Manifest;
         end Hex_Value;

         procedure Append_UTF8 (Result : in out Unbounded_String; Code : Natural) is
         begin
            if Code > 16#10FFFF# or else Code in 16#D800# .. 16#DFFF# then
               raise Workspace_Error with "invalid Unicode scalar in local pin path in " & Manifest;
            elsif Code <= 16#7F# then
               Append (Result, Character'Val (Code));
            elsif Code <= 16#7FF# then
               Append (Result, Character'Val (16#C0# + Code / 64));
               Append (Result, Character'Val (16#80# + Code mod 64));
            elsif Code <= 16#FFFF# then
               Append (Result, Character'Val (16#E0# + Code / 4_096));
               Append (Result, Character'Val (16#80# + (Code / 64) mod 64));
               Append (Result, Character'Val (16#80# + Code mod 64));
            else
               Append (Result, Character'Val (16#F0# + Code / 262_144));
               Append (Result, Character'Val (16#80# + (Code / 4_096) mod 64));
               Append (Result, Character'Val (16#80# + (Code / 64) mod 64));
               Append (Result, Character'Val (16#80# + Code mod 64));
            end if;
         end Append_UTF8;

         procedure Append_Escape
           (Result   : in out Unbounded_String;
            Line     : String;
            Position : in out Natural)
         is
         begin
            case Line (Position) is
               when 'b' => Append (Result, Character'Val (8));
               when 't' => Append (Result, Character'Val (9));
               when 'n' => Append (Result, Ada.Characters.Latin_1.LF);
               when 'f' => Append (Result, Character'Val (12));
               when 'r' => Append (Result, Ada.Characters.Latin_1.CR);
               when '"' => Append (Result, '"');
               when '\' => Append (Result, '\');
               when 'u' | 'U' =>
                  declare
                     Count : constant Positive := (if Line (Position) = 'u' then 4 else 8);
                     Code  : Natural := 0;
                  begin
                     if Position + Count > Line'Last then
                        raise Workspace_Error with
                          "truncated Unicode escape in local pin path in " & Manifest;
                     end if;
                     for Index in Position + 1 .. Position + Count loop
                        Code := Code * 16 + Hex_Value (Line (Index));
                     end loop;
                     Append_UTF8 (Result, Code);
                     Position := Position + Count;
                  end;
               when others =>
                  raise Workspace_Error with "unsupported escape in local pin path in " & Manifest;
            end case;
         end Append_Escape;

         function Decode_String
           (Line : String;
            First : Positive;
            Last : out Natural) return String
         is
            Quote    : constant Character := Line (First);
            Position : Natural := First + 1;
            Escaped  : Boolean := False;
            Result   : Unbounded_String;
         begin
            Last := 0;
            if Quote not in ''' | '"' or else Triple_At (Line, First, Quote) then
               raise Workspace_Error with "local pin path must be a single-line TOML string in " & Manifest;
            end if;
            while Position <= Line'Last loop
               if Quote = ''' then
                  if Line (Position) = Quote then
                     Last := Position;
                     return To_String (Result);
                  end if;
                  Append (Result, Line (Position));
                  Position := Position + 1;
               elsif not Escaped and then Line (Position) = Quote then
                  Last := Position;
                  return To_String (Result);
               elsif not Escaped and then Line (Position) = '\' then
                  Escaped := True;
                  Position := Position + 1;
               elsif Escaped then
                  Append_Escape (Result, Line, Position);
                  Escaped := False;
                  Position := Position + 1;
               else
                  Append (Result, Line (Position));
                  Position := Position + 1;
               end if;
            end loop;
            raise Workspace_Error with "unterminated local pin path in " & Manifest;
         end Decode_String;

         function Path_Value_Position (Line : String) return Natural is
            Position : Natural := Line'First;

            function Value_After_Key (After_Key : Natural) return Natural is
               Cursor : Natural := After_Key;
            begin
               Skip_Whitespace (Line, Cursor);
               if Cursor <= Line'Last and then Line (Cursor) = '=' then
                  Cursor := Cursor + 1;
                  Skip_Whitespace (Line, Cursor);
                  return Cursor;
               end if;
               return 0;
            end Value_After_Key;
         begin
            while Position <= Line'Last loop
               if Line (Position) in ''' | '"' then
                  declare
                     Last : Natural;
                     Key  : constant String := Decode_String (Line, Position, Last);
                  begin
                     if Key = "path" then
                        declare
                           Value : constant Natural := Value_After_Key (Last + 1);
                        begin
                           if Value > 0 then return Value; end if;
                        end;
                     end if;
                     Position := Last + 1;
                  end;
               elsif Position + 3 <= Line'Last and then Line (Position .. Position + 3) = "path" and then
                 (Position = Line'First or else not Key_Character (Line (Position - 1))) and then
                 (Position + 3 = Line'Last or else not Key_Character (Line (Position + 4)))
               then
                  declare
                     Value : constant Natural := Value_After_Key (Position + 4);
                  begin
                     if Value > 0 then return Value; end if;
                  end;
                  Position := Position + 4;
               else
                  Position := Position + 1;
               end if;
            end loop;
            return 0;
         end Path_Value_Position;

         procedure Process_Line (Raw_Line : String) is
            Line       : constant String := Sanitized (Raw_Line);
            Clean      : constant String := Trim (Line);
            Header     : constant String := Compact (Clean);
            Value_At   : Natural;
         begin
            if Clean'Length = 0 then return; end if;
            if Clean (Clean'First) = '[' then
               if Header = "[[pins]]" then
                  Section := Pins_Section;
               elsif Header = "[solution.state.link]" then
                  Section := Solution_Link_Section;
               else
                  Section := Other_Section;
               end if;
               return;
            end if;
            if Multiline_Quote /= Character'Val (0) or else Section = Other_Section then return; end if;
            Value_At := Path_Value_Position (Line);
            if Value_At > 0 then
               if Value_At > Line'Last then
                  raise Workspace_Error with "missing local pin path in " & Manifest;
               end if;
               declare
                  Last : Natural;
               begin
                  Copy_Pin (Decode_String (Line, Value_At, Last));
               end;
            end if;
         end Process_Line;
      begin
         if Data'Length > 0 then
            declare
               Start : Positive := Data'First;
            begin
               for Position in Data'Range loop
                  if Data (Position) = Ada.Characters.Latin_1.LF then
                     Process_Line ((if Position = Start then "" else Data (Start .. Position - 1)));
                     Start := Position + 1;
                  end if;
               end loop;
               if Start <= Data'Last then Process_Line (Data (Start .. Data'Last)); end if;
            end;
         end if;
         if Multiline_Quote /= Character'Val (0) then
            raise Workspace_Error with "unterminated multiline TOML string in " & Manifest;
         end if;
      end Copy_Pins;

      procedure Copy_Crate (From, Into : String) is
         Canonical : constant String := Ada.Directories.Full_Name (From);
         Manifest  : constant String := Project_Tools.Files.Join (Canonical, "alire.toml");
         Lockfile  : constant String := Project_Tools.Files.Join (Canonical, "alire/alire.lock");
      begin
         if Seen_Before (Canonical) then
            if not Project_Tools.Files.Exists (Into) then Copy_Tree (Canonical, Into); end if;
            return;
         end if;
         Seen.Append (To_Unbounded_String (Canonical));
         Copy_Tree (Canonical, Into);
         if Project_Tools.Files.File_Exists (Manifest) then
            Copy_Pins (Canonical, Into, Manifest);
         end if;
         if Project_Tools.Files.File_Exists (Lockfile) then
            Copy_Pins (Canonical, Into, Lockfile);
         end if;
      end Copy_Crate;
   begin
      Cleanup (Item);
      Ada_Quality.Temporary_Directories.Create (Item.Scratch, "ada-quality-stage-" & Identity);
      declare
         Target : constant String := Ada_Quality.Temporary_Directories.Child
           (Item.Scratch, Ada.Directories.Simple_Name (Canonical_Source));
      begin
         Copy_Crate (Canonical_Source, Target);
         Item.Root := To_Unbounded_String (Target);
      end;
   exception
      when others =>  --  AQ: audited exception boundary
         Ada_Quality.Temporary_Directories.Cleanup (Item.Scratch);
         Item.Root := Null_Unbounded_String;
         raise;
   end Prepare;

   procedure Cleanup (Item : in out Workspace) is
   begin
      Ada_Quality.Temporary_Directories.Cleanup (Item.Scratch);
      Item.Root := Null_Unbounded_String;
   end Cleanup;

   function Path (Item : Workspace) return String is (To_String (Item.Root));

   function Scratch_Path (Item : Workspace; Name : String) return String is
     (Ada_Quality.Temporary_Directories.Child (Item.Scratch, Name));

   function Is_Active (Item : Workspace) return Boolean is
     (Ada_Quality.Temporary_Directories.Is_Active (Item.Scratch));
end Ada_Quality.Workspaces;
