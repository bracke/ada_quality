with Ada.Characters.Handling;
with Ada.Characters.Latin_1;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Interfaces;
with Project_Tools.Gcov;
with Project_Tools.Links;
with Project_Tools.Processes;
with Project_Tools.Ada_Source;
with Project_Tools.Release_Checks;
with Project_Tools.TOML;
with Regexp;
with Ada_Quality.Execution;
with Ada_Quality.Evaluation;
with Ada_Quality.Tools;
with Ada_Quality.Workspaces;

--  AQ: complexity-reviewed -- assessment orchestration is decomposed into indicator groups.
--  AQ: size-reviewed -- native analysis and external assessment remain one cohesive implementation boundary.
package body Ada_Quality.Checks is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Types;
   use type Interfaces.Unsigned_64;
   use type Ada.Containers.Count_Type;
   use type Ada.Directories.File_Kind;
   use type Ada.Directories.File_Size;
   use type Ada_Quality.Execution.Run_Status;
   use type Regexp.Compile_Status;
   use type Regexp.Match_Status;
   use type Project_Tools.TOML.String_Parse_Status;

   Secret_Pattern : constant Regexp.Compile_Result :=
     Regexp.Compile ("(aws_secret_access_key|password|api_key|access_token)\s*:=");
   Shell_Pattern : constant Regexp.Compile_Result :=
     Regexp.Compile ("(run_shell|spawn_shell|shell_execute)");
   Local_Pin_Pattern : constant Regexp.Compile_Result :=
     Regexp.Compile ("path\s*=");

   package Text_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String);
   package Text_Sorting is new Text_Vectors.Generic_Sorting
     ("<" => Ada.Strings.Unbounded."<");

   Skip_Names : constant Project_Tools.Files.Name_List :=
     [To_Unbounded_String (".git"), To_Unbounded_String (".alire"),
      To_Unbounded_String ("obj"), To_Unbounded_String ("bin"),
      To_Unbounded_String ("cov-obj"), To_Unbounded_String ("cov-bin"),
      To_Unbounded_String ("coverage"), To_Unbounded_String ("lib"),
      To_Unbounded_String ("gnatprove")];

   Maximum_Tree_Depth       : constant := 128;
   Maximum_Project_Files    : constant := 100_000;
   Maximum_File_Bytes       : constant := 64 * 1_024 * 1_024;
   Maximum_Fingerprint_Bytes : constant := 1_024 * 1_024 * 1_024;

   function Contains (Text, Pattern : String) return Boolean is
     (Ada.Strings.Fixed.Index (Text, Pattern) > 0);

   function Lower (Text : String) return String is
     (Ada.Characters.Handling.To_Lower (Text));

   function Starts_With (Text, Prefix : String) return Boolean is
     (Text'Length >= Prefix'Length and then
      Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix);

   function Normalize_Test_Output (Text : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
      Start  : Positive := Text'First;

      procedure Append_Line (Line : String) is
         Normalized : constant String := Lower (Ada.Strings.Fixed.Trim (Line, Ada.Strings.Both));
         Volatile   : constant Boolean :=
           Starts_With (Normalized, "elapsed:") or else Starts_With (Normalized, "elapsed time:") or else
           Starts_With (Normalized, "duration:") or else Starts_With (Normalized, "timestamp:") or else
           Starts_With (Normalized, "time:");
      begin
         if not Volatile then Append (Result, Line & Ada.Characters.Latin_1.LF); end if;
      end Append_Line;
   begin
      if Text'Length = 0 then return ""; end if;
      for J in Text'Range loop
         if Text (J) = Ada.Characters.Latin_1.LF then
            Append_Line ((if J = Start then "" else Text (Start .. J - 1)));
            Start := J + 1;
         end if;
      end loop;
      if Start <= Text'Last then Append_Line (Text (Start .. Text'Last)); end if;
      return To_String (Result);
   end Normalize_Test_Output;

   function Matches (Pattern : Regexp.Compile_Result; Text : String) return Boolean is
     (Pattern.Status = Regexp.Compile_Ok and then
      Regexp.Find_First (Pattern.Expression, Text).Status = Regexp.Match_Ok);

   function Occurrences (Text, Pattern : String) return Natural is
      Cursor : Natural := Text'First;
      Found  : Natural;
      Count  : Natural := 0;
   begin
      if Text'Length = 0 or else Pattern'Length = 0 then return 0; end if;
      loop
         Found := Ada.Strings.Fixed.Index (Text, Pattern, From => Cursor);
         exit when Found = 0;
         Count := Count + 1;
         Cursor := Found + Pattern'Length;
         exit when Cursor > Text'Last;
      end loop;
      return Count;
   end Occurrences;

   function Valid_Manifest (Text : String) return Boolean is
      Name : constant Project_Tools.TOML.String_Parse_Result :=
        Project_Tools.TOML.Parse_String_After (Text, "name", Text'First);
      Version : constant Project_Tools.TOML.String_Parse_Result :=
        Project_Tools.TOML.Parse_String_After (Text, "version", Text'First);
   begin
      return Name.Status = Project_Tools.TOML.Parsed_String and then
        Version.Status = Project_Tools.TOML.Parsed_String and then
        Length (Name.Value) > 0 and then Length (Version.Value) > 0;
   end Valid_Manifest;

   function Has_Manifest_String (Text, Key : String) return Boolean is
      Value : constant Project_Tools.TOML.String_Parse_Result :=
        Project_Tools.TOML.Parse_String_After (Text, Key, Text'First);
   begin
      return Value.Status = Project_Tools.TOML.Parsed_String and then Length (Value.Value) > 0;
   end Has_Manifest_String;

   function Without_TOML_Comments (Text : String) return String is
      Result    : String := Text;
      In_String : Boolean := False;
      Quote     : Character := Character'Val (0);
      Escaped   : Boolean := False;
   begin
      for J in Text'Range loop
         if Text (J) = Ada.Characters.Latin_1.LF then
            In_String := False;
            Escaped := False;
         elsif not In_String and then Text (J) = '#' then
            declare
               K : Natural := J;
            begin
               while K <= Text'Last and then Text (K) /= Ada.Characters.Latin_1.LF loop
                  Result (K) := ' ';
                  K := K + 1;
               end loop;
            end;
         elsif In_String then
            if Text (J) = Quote and then not Escaped then In_String := False; end if;
            Escaped := Text (J) = '\' and then not Escaped;
         elsif Text (J) in ''' | '"' then
            In_String := True;
            Quote := Text (J);
         end if;
      end loop;
      return Result;
   end Without_TOML_Comments;

   function Has_Suffix (Text, Suffix : String) return Boolean;

   --  Return the string elements of the top-level array Key in an Alire manifest, or an empty vector when Key is
   --  absent or its array is malformed.
   function Manifest_Strings (Text, Key : String) return Text_Vectors.Vector is
      Clean  : constant String := Without_TOML_Comments (Text);
      Result : Text_Vectors.Vector;
      Start  : Natural := Clean'First;
      Key_At : Natural := 0;
   begin
      if Text'Length = 0 then return Result; end if;
      while Start <= Clean'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index (Clean, [ASCII.LF], From => Start);
            First : Natural := Start;
         begin
            if Stop = 0 then Stop := Clean'Last + 1; end if;
            while First < Stop and then Clean (First) in ' ' | Character'Val (9) | ASCII.CR loop
               First := First + 1;
            end loop;
            if Stop - First >= Key'Length and then
              Clean (First .. First + Key'Length - 1) = Key and then
              (First + Key'Length = Stop or else
               Clean (First + Key'Length) in ' ' | Character'Val (9) | '=')
            then
               Key_At := First;
               exit;
            end if;
            exit when Stop > Clean'Last;
            Start := Stop + 1;
         end;
      end loop;
      if Key_At = 0 then return Result; end if;
      declare
         Open_At : constant Natural := Ada.Strings.Fixed.Index
           (Clean, "[", From => Key_At + Key'Length);
         Position : Natural := Open_At + 1;
      begin
         if Open_At = 0 then return Result; end if;
         while Position <= Clean'Last loop
            exit when Clean (Position) = ']';
            if Clean (Position) in ''' | '"' then
               declare
                  Quote : constant Character := Clean (Position);
                  First : constant Natural := Position + 1;
                  Escaped : Boolean := False;
               begin
                  Position := First;
                  while Position <= Clean'Last loop
                     exit when Clean (Position) = Quote and then (Quote = ''' or else not Escaped);
                     if Quote = '"' then
                        Escaped := Clean (Position) = '\' and then not Escaped;
                     end if;
                     Position := Position + 1;
                  end loop;
                  if Position > Clean'Last then return Text_Vectors.Empty_Vector; end if;
                  Result.Append (To_Unbounded_String (Clean (First .. Position - 1)));
               end;
            end if;
            Position := Position + 1;
         end loop;
      end;
      return Result;
   end Manifest_Strings;

   function Manifest_Project_Files (Root, Text : String) return Text_Vectors.Vector is
      Result : Text_Vectors.Vector;
   begin
      for Item of Manifest_Strings (Text, "project-files") loop
         declare
            Relative_Path : constant String := To_String (Item);
            Full_Path     : constant String := Project_Tools.Files.Join (Root, Relative_Path);
         begin
            if Relative_Path'Length > 0 and then Has_Suffix (Lower (Relative_Path), ".gpr") and then
              Project_Tools.Files.File_Exists (Full_Path)
            then
               Result.Append (To_Unbounded_String (Full_Path));
            end if;
         end;
      end loop;
      return Result;
   end Manifest_Project_Files;

   function Test_Manifest_Text (Root : String) return String is
      Manifest : constant String := Project_Tools.Files.Join (Root, "tests/alire.toml");
   begin
      return (if Project_Tools.Files.File_Exists (Manifest) then Project_Tools.Files.Read_Raw_File (Manifest) else "");
   end Test_Manifest_Text;

   function Test_Project_File (Root : String) return String is
      Text  : constant String := Test_Manifest_Text (Root);
      Tests : constant String := Project_Tools.Files.Join (Root, "tests");
   begin
      if Text'Length = 0 then
         return "";
      end if;
      declare
         Listed : constant Text_Vectors.Vector := Manifest_Project_Files (Tests, Text);
      begin
         return
           (if not Listed.Is_Empty then To_String (Listed.First_Element)
            else Project_Tools.Files.Join (Tests, Project_Tools.TOML.String_Value_After (Text, "name", Text'First)
                                                  & ".gpr"));
      end;
   end Test_Project_File;

   function Test_Suite_Executable (Root : String) return String is
      Text : constant String := Test_Manifest_Text (Root);
   begin
      if Text'Length = 0 then
         return "";
      end if;
      declare
         Listed : constant Text_Vectors.Vector := Manifest_Strings (Text, "executables");
      begin
         return Project_Tools.Files.Join
           (Root, "tests/bin/" & (if not Listed.Is_Empty then To_String (Listed.First_Element)
                                  else Project_Tools.TOML.String_Value_After (Text, "name", Text'First)));
      end;
   end Test_Suite_Executable;

   function Dedicated_Proof_Projects (Root : String) return Project_Tools.Files.Path_List is
      Names  : Text_Vectors.Vector;
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
   begin
      if Ada.Directories.Exists (Root) then
         Ada.Directories.Start_Search
           (Search, Root, "spark*.gpr", [Ada.Directories.Ordinary_File => True, others => False]);
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            Names.Append (To_Unbounded_String (Ada.Directories.Full_Name (Item)));
         end loop;
         Ada.Directories.End_Search (Search);
         Text_Sorting.Sort (Names);
      end if;
      return Result : Project_Tools.Files.Path_List (1 .. Natural (Names.Length)) do
         for Index in Result'Range loop
            Result (Index) := Names (Index);
         end loop;
      end return;
   end Dedicated_Proof_Projects;

   function Is_Skipped (Name : String) return Boolean is
   begin
      for Item of Skip_Names loop
         if To_String (Item) = Name then return True; end if;
      end loop;
      return False;
   end Is_Skipped;

   function Has_Suffix (Text, Suffix : String) return Boolean is
     (Text'Length >= Suffix'Length and then
      Text (Text'Last - Suffix'Length + 1 .. Text'Last) = Suffix);

   function Code_Without_Comments_And_Strings (Path : String) return String is
      Data       : constant String := Project_Tools.Files.Read_Raw_File (Path);
      Normalized : String := Data;
      In_String  : Boolean := False;
      In_Comment : Boolean := False;
      J          : Natural := Data'First;
   begin
      while J <= Data'Last loop
         if In_Comment then
            if Data (J) = Ada.Characters.Latin_1.LF then In_Comment := False; end if;
            Normalized (J) := ' ';
            J := J + 1;
         elsif not In_String and then J < Data'Last and then Data (J .. J + 1) = "--" then
            Normalized (J .. J + 1) := "  ";
            In_Comment := True;
            J := J + 2;
         elsif Data (J) = '"' then
            Normalized (J) := ' ';
            if In_String and then J < Data'Last and then Data (J + 1) = '"' then
               Normalized (J + 1) := ' ';
               J := J + 2;
            else
               In_String := not In_String;
               J := J + 1;
            end if;
         else
            if In_String then Normalized (J) := ' '; end if;
            J := J + 1;
         end if;
      end loop;
      return Lower (Normalized);
   end Code_Without_Comments_And_Strings;

   function Ada_Code_Has_Token (Path, Token : String) return Boolean is
      Code  : constant String := Code_Without_Comments_And_Strings (Path);
      Match : Natural := Code'First;

      function Identifier_Character (Value : Character) return Boolean is
        (Value in 'a' .. 'z' | '0' .. '9' or else Value = '_');
   begin
      loop
         Match := Ada.Strings.Fixed.Index (Code, Lower (Token), From => Match);
         if Match = 0 then return False; end if;
         declare
            Last : constant Natural := Match + Token'Length - 1;
         begin
            if (Match = Code'First or else not Identifier_Character (Code (Match - 1))) and then
              (Last = Code'Last or else not Identifier_Character (Code (Last + 1)))
            then
               return True;
            end if;
            Match := Last + 1;
         end;
      end loop;
   end Ada_Code_Has_Token;

   function Relative (Root, Path : String) return String is
   begin
      if Path'Length > Root'Length + 1 and then
        Path (Path'First .. Path'First + Root'Length - 1) = Root
      then
         return Path (Path'First + Root'Length + 1 .. Path'Last);
      end if;
      return Path;
   end Relative;

   function Tree_Entries (Root : String; Links : Boolean) return Text_Vectors.Vector is
      Result : Text_Vectors.Vector;

      procedure Walk (Directory : String; Depth : Positive) is
         Search      : Ada.Directories.Search_Type;
         Search_Open : Boolean := False;
         Item        : Ada.Directories.Directory_Entry_Type;
      begin
         if Depth > Maximum_Tree_Depth then
            raise Constraint_Error with "project tree exceeds maximum directory depth";
         end if;
         if Project_Tools.Links.Is_Link (Directory) then
            if Links then Result.Append (To_Unbounded_String (Directory)); end if;
            return;
         elsif not Ada.Directories.Exists (Directory) then
            return;
         end if;
         Ada.Directories.Start_Search (Search, Directory, "");
         Search_Open := True;
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            declare
               Name : constant String := Ada.Directories.Simple_Name (Item);
               Path : constant String := Directory & "/" & Name;
            begin
               if Name = "." or else Name = ".." or else Is_Skipped (Name) then
                  null;
               elsif Project_Tools.Links.Is_Link (Path) then
                  if Links then Result.Append (To_Unbounded_String (Path)); end if;
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Directory then
                  Walk (Path, Depth + 1);
               elsif not Links and then Ada.Directories.Kind (Item) = Ada.Directories.Ordinary_File then
                  Result.Append (To_Unbounded_String (Path));
               end if;
               if Result.Length > Maximum_Project_Files then
                  raise Constraint_Error with "project tree exceeds maximum file count";
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         Search_Open := False;
      exception
         when others =>  --  AQ: audited exception boundary
            if Search_Open then Ada.Directories.End_Search (Search); end if;
            raise;
      end Walk;
   begin
      Walk (Root, 1);
      Text_Sorting.Sort (Result);
      return Result;
   end Tree_Entries;

   function All_Files (Root : String) return Text_Vectors.Vector is
     (Tree_Entries (Root, Links => False));

   function All_Links (Root : String) return Text_Vectors.Vector is
     (Tree_Entries (Root, Links => True));

   function Source_Files (Root : String) return Text_Vectors.Vector is
      Result : Text_Vectors.Vector;
   begin
      for Path of All_Files (Root) loop
         declare
            Name : constant String := To_String (Path);
            Rel  : constant String := "/" & Relative (Root, Name);
         begin
            if (Has_Suffix (Name, ".ads") or else Has_Suffix (Name, ".adb")) and then
              not (Contains (Rel, "/config/") and then
                (Contains (Ada.Directories.Simple_Name (Name), "_config.ads") or else
                 Contains (Ada.Directories.Simple_Name (Name), "_config.adb")))
            then
               Result.Append (Path);
            end if;
         end;
      end loop;
      return Result;
   end Source_Files;

   function Is_Generated_Fingerprint_File (Root, Path : String) return Boolean is
      Name : constant String := Ada.Directories.Simple_Name (Path);
      Rel  : constant String := "/" & Relative (Root, Path);
   begin
      if Name in "alr_test_local.log" | "alr_test_local.xml" | "settings.toml" | "build_hash_inputs" then
         return True;
      elsif Contains (Rel, "/config/") and then
        (Contains (Name, "_config.ads") or else Contains (Name, "_config.gpr") or else
         Contains (Name, "_config.h"))
      then
         return True;
      elsif Contains (Rel, "/alire/") and then Name /= "alire.lock" then
         return True;
      else
         return False;
      end if;
   end Is_Generated_Fingerprint_File;

   function Declares_SPARK (Root : String) return Boolean is
   begin
      for Path of All_Files (Root) loop
         declare
            Name : constant String := Lower (To_String (Path));
         begin
            if (Has_Suffix (Name, ".ads") or else Has_Suffix (Name, ".adb") or else
                Has_Suffix (Name, ".adc") or else Has_Suffix (Name, ".gpr")) and then
              Ada_Code_Has_Token (To_String (Path), "spark_mode")
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end Declares_SPARK;

   function Hash_Image (Value : Interfaces.Unsigned_64) return String is
      Hex    : constant String := "0123456789abcdef";
      Work   : Interfaces.Unsigned_64 := Value;
      Result : String (1 .. 16);
   begin
      for J in reverse Result'Range loop
         Result (J) := Hex (Natural (Work and 15) + 1);
         Work := Interfaces.Shift_Right (Work, 4);
      end loop;
      return Result;
   end Hash_Image;

   function Artifact_Files (Root : String) return Text_Vectors.Vector is
      Result : Text_Vectors.Vector;

      function Is_Artifact_Directory (Name : String) return Boolean is
        (Name in "obj" | "bin" | "cov-obj" | "cov-bin" | "coverage" | "lib" | "gnatprove");

      procedure Walk (Directory : String; Inside_Artifact : Boolean; Depth : Positive) is
         Search      : Ada.Directories.Search_Type;
         Search_Open : Boolean := False;
         Item        : Ada.Directories.Directory_Entry_Type;
      begin
         if Depth > Maximum_Tree_Depth then
            raise Constraint_Error with "project tree exceeds maximum directory depth";
         end if;
         Ada.Directories.Start_Search (Search, Directory, "");
         Search_Open := True;
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            declare
               Name : constant String := Ada.Directories.Simple_Name (Item);
               Path : constant String := Directory & "/" & Name;
               In_Artifact : constant Boolean := Inside_Artifact or else Is_Artifact_Directory (Name);
            begin
               if Name in "." | ".." or else (not Inside_Artifact and then Name in ".git" | ".alire") then
                  null;
               elsif Project_Tools.Links.Is_Link (Path) then
                  if In_Artifact then Result.Append (To_Unbounded_String (Path)); end if;
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Directory then
                  Walk (Path, In_Artifact, Depth + 1);
               elsif In_Artifact and then Ada.Directories.Kind (Item) = Ada.Directories.Ordinary_File then
                  Result.Append (To_Unbounded_String (Path));
               end if;
               if Result.Length > Maximum_Project_Files then
                  raise Constraint_Error with "project artifact tree exceeds maximum file count";
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         Search_Open := False;
      exception
         when others =>  --  AQ: audited exception boundary
            if Search_Open then Ada.Directories.End_Search (Search); end if;
            raise;
      end Walk;
   begin
      Walk (Root, Inside_Artifact => False, Depth => 1);
      Text_Sorting.Sort (Result);
      return Result;
   end Artifact_Files;

   function Tree_Fingerprint
     (Root             : String;
      Files            : Text_Vectors.Vector;
      Ignore_Generated : Boolean) return String
   is
      Hash  : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Total_Bytes : Natural := 0;

      procedure Add_To_Hash (Text : String) is
      begin
         for C of Text loop
            Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
         end loop;
      end Add_To_Hash;
   begin
      for Path of Files loop
         if not Ignore_Generated or else not Is_Generated_Fingerprint_File (Root, To_String (Path)) then
            declare
               Name : constant String := Relative (Root, To_String (Path));
            begin
               if Project_Tools.Links.Is_Link (To_String (Path)) then
                  Add_To_Hash (Name & Character'Val (0) & "<symbolic-link>");
               else
                  declare
                     Size : constant Ada.Directories.File_Size := Ada.Directories.Size (To_String (Path));
                  begin
                     --  Source files are read whole; artifact files are hashed as a stream, so only the aggregate
                     --  limit bounds them.
                     if Ignore_Generated and then Size > Ada.Directories.File_Size (Maximum_File_Bytes) then
                        raise Constraint_Error with "project file exceeds fingerprint size limit: " & Name;
                     elsif Natural (Size) > Maximum_Fingerprint_Bytes - Total_Bytes then
                        raise Constraint_Error with "project exceeds aggregate fingerprint size limit";
                     end if;
                     Total_Bytes := Total_Bytes + Natural (Size);
                     if Ignore_Generated then
                        declare
                           Data : constant String := Project_Tools.Files.Read_Raw_File (To_String (Path));
                        begin
                           Add_To_Hash (Name & Character'Val (0) & Data);
                        end;
                     else
                        Add_To_Hash
                          (Name & Character'Val (0) & Ada.Directories.File_Size'Image (Size) & ":" &
                           Project_Tools.Release_Checks.FNV1A64 (To_String (Path)));
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      return Hash_Image (Hash);
   end Tree_Fingerprint;

   function Source_Fingerprint (Root : String) return String is
      Files : Text_Vectors.Vector := All_Files (Root);
   begin
      Files.Append_Vector (All_Links (Root));
      Text_Sorting.Sort (Files);
      return Tree_Fingerprint (Root, Files, Ignore_Generated => True);
   end Source_Fingerprint;

   function Project_State_Fingerprint (Root : String) return String is
     (Source_Fingerprint (Root) & ":" &
      Tree_Fingerprint (Root, Artifact_Files (Root), Ignore_Generated => False));

   procedure Copy_State_Tree (Source, Target : String) is
      Count : Natural := 0;

      procedure Copy_Directory (From, Into : String; Depth : Positive) is
         Search      : Ada.Directories.Search_Type;
         Search_Open : Boolean := False;
         Item        : Ada.Directories.Directory_Entry_Type;
      begin
         if Depth > Maximum_Tree_Depth then
            raise Constraint_Error with "test baseline exceeds maximum directory depth";
         end if;
         Ada.Directories.Create_Path (Into);
         Ada.Directories.Start_Search (Search, From, "");
         Search_Open := True;
         while Ada.Directories.More_Entries (Search) loop
            Ada.Directories.Get_Next_Entry (Search, Item);
            declare
               Name      : constant String := Ada.Directories.Simple_Name (Item);
               From_Path : constant String := Project_Tools.Files.Join (From, Name);
               Into_Path : constant String := Project_Tools.Files.Join (Into, Name);
            begin
               if Name in "." | ".." then
                  null;
               elsif Project_Tools.Links.Is_Link (From_Path) then
                  raise Constraint_Error with "test baseline contains a symbolic link: " & From_Path;
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Directory then
                  Copy_Directory (From_Path, Into_Path, Depth + 1);
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Ordinary_File then
                  Count := Count + 1;
                  if Count > Maximum_Project_Files then
                     raise Constraint_Error with "test baseline exceeds maximum file count";
                  end if;
                  Ada.Directories.Copy_File
                    (Source_Name => From_Path, Target_Name => Into_Path,
                     Form => "preserve=all_attributes");
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         Search_Open := False;
      exception
         when others =>
            if Search_Open then Ada.Directories.End_Search (Search); end if;
            raise;
      end Copy_Directory;
   begin
      Copy_Directory (Source, Target, 1);
   end Copy_State_Tree;

   procedure Add_Finding
     (Item    : in out Indicator_Result;
      Rule    : String;
      Message : String;
      Path    : String := "";
      Line    : Natural := 0;
      Level   : Severity := Medium)
   is
      Fingerprint : constant String := Image (Item.Indicator) & ":" & Rule & ":" & Path & ":" & Message;
   begin
      Item.Findings.Append
        (Finding'(Indicator => Item.Indicator,
          Rule => To_Unbounded_String (Rule),
          Level => Level,
          Message => To_Unbounded_String (Message),
          Relative_Path => To_Unbounded_String (Path),
          Line => Line,
          Fingerprint => To_Unbounded_String (Fingerprint)));
   end Add_Finding;

   function Passed (Id : Indicator_Id; Summary, Evidence : String) return Indicator_Result is
     (Ada_Quality.Evaluation.Evaluate
        (Id, Succeeded, True, True, Summary, Summary, Evidence));

   function Violated (Id : Indicator_Id; Summary, Evidence : String) return Indicator_Result is
      Result : Indicator_Result := Ada_Quality.Evaluation.Evaluate
        (Id, Succeeded, True, False, Summary, Summary, Evidence);
   begin
      Add_Finding (Result, Image (Id), Summary);
      return Result;
   end Violated;

   function Blocked_Result (Id : Indicator_Id; Summary, Evidence : String) return Indicator_Result is
     (Ada_Quality.Evaluation.Evaluate
        (Id, Blocked, True, False, Summary, Summary, Evidence));

   function Not_Applicable_Result (Id : Indicator_Id; Evidence : String) return Indicator_Result is
     (Ada_Quality.Evaluation.Evaluate
        (Id, Not_Applicable, False, False, "not applicable", "not applicable", Evidence));

   procedure Scan_Source
     (Root   : String;
      Policy : Ada_Quality.Policy.Quality_Policy;
      Result : out Source_Analysis)
   is
      Files : constant Text_Vectors.Vector := Source_Files (Root);
   begin
      Result := (Findings => <>, others => 0);
      for Path_Value of All_Files (Root) loop
         declare
            Path : constant String := To_String (Path_Value);
            Rel  : constant String := "/" & Relative (Root, Path);
         begin
            if (Has_Suffix (Path, ".ads") or else Has_Suffix (Path, ".adb")) and then
              Contains (Rel, "/config/") and then
              (Contains (Ada.Directories.Simple_Name (Path), "_config.ads") or else
               Contains (Ada.Directories.Simple_Name (Path), "_config.adb"))
            then
               Result.Generated_Files := Result.Generated_Files + 1;
            end if;
         end;
      end loop;
      for Path_Value of Files loop
         declare
            Path       : constant String := To_String (Path_Value);
            Name       : constant String := Ada.Directories.Simple_Name (Path);
            Rel_Path   : constant String := "/" & Relative (Root, Path);
            Is_Test    : constant Boolean :=
              Contains (Rel_Path, "/tests/") or else Contains (Rel_Path, "/test/");
            Data       : constant String := Project_Tools.Files.Read_Raw_File (Path);
            Complexity_Reviewed : constant Boolean :=
              Contains (Lower (Data), "aq: complexity-reviewed");
            Size_Reviewed : constant Boolean := Contains (Lower (Data), "aq: size-reviewed");
            Start      : Positive := 1;
            File_Lines : Natural := 0;
            Complexity : Natural := 1;
            File_Max_Complexity : Natural := 1;
            Has_Docs   : Boolean := False;
            Pending_Doc : Boolean := False;
            Unit_Name_Checked : Boolean := False;
            Is_Spec     : constant Boolean :=
              Name'Length >= 4 and then Name (Name'Last - 3 .. Name'Last) = ".ads";

            procedure Note
              (Indicator : Indicator_Id;
               Rule, Message : String;
               Line : Natural := 0;
               Level : Severity := Medium) is
               Rel : constant String := Relative (Root, Path);
            begin
               Result.Findings.Append
                 (Finding'(Indicator => Indicator, Rule => To_Unbounded_String (Rule), Level => Level,
                  Message => To_Unbounded_String (Message), Relative_Path => To_Unbounded_String (Rel),
                  Line => Line, Fingerprint => To_Unbounded_String
                    (Image (Indicator) & ":" & Rule & ":" & Rel & ":" & Message)));
            end Note;

            procedure Scan_Line (Line : String) is
               function Code_Only return String is
                  Result    : String := Line;
                  In_String : Boolean := False;
                  J         : Natural := Line'First;
               begin
                  while J <= Line'Last loop
                     if not In_String and then J < Line'Last and then Line (J .. J + 1) = "--" then
                        Result (J .. Result'Last) := [others => ' '];
                        exit;
                     elsif Line (J) = '"' then
                        Result (J) := ' ';
                        if In_String and then J < Line'Last and then Line (J + 1) = '"' then
                           Result (J + 1) := ' ';
                           J := J + 2;
                        else
                           In_String := not In_String;
                           J := J + 1;
                        end if;
                     else
                        if In_String then Result (J) := ' '; end if;
                        J := J + 1;
                     end if;
                  end loop;
                  return Result;
               end Code_Only;

               Clean : constant String := Lower (Code_Only);

               function Tokens return Text_Vectors.Vector is
                  Result : Text_Vectors.Vector;
                  First  : Natural := 0;

                  function Is_Identifier_Character (C : Character) return Boolean is
                    (C in 'a' .. 'z' or else C in '0' .. '9' or else C = '_');
               begin
                  for J in Clean'Range loop
                     if Is_Identifier_Character (Clean (J)) then
                        if First = 0 then First := J; end if;
                     elsif First > 0 then
                        Result.Append (To_Unbounded_String (Clean (First .. J - 1)));
                        First := 0;
                     end if;
                  end loop;
                  if First > 0 then Result.Append (To_Unbounded_String (Clean (First .. Clean'Last))); end if;
                  return Result;
               end Tokens;

               Words : constant Text_Vectors.Vector := Tokens;
               Decisions : Natural := 0;

               function Canonical (Value : String) return String is
                  Result : String (1 .. Value'Length);
                  Last   : Natural := 0;
               begin
                  for C of Lower (Value) loop
                     if C in 'a' .. 'z' or else C in '0' .. '9' then
                        Last := Last + 1;
                        Result (Last) := C;
                     end if;
                  end loop;
                  return Result (1 .. Last);
               end Canonical;
            begin
               File_Lines := File_Lines + 1;
               if not Words.Is_Empty then
                  if not Unit_Name_Checked then
                     declare
                        First : Positive := Words.First_Index;
                     begin
                        if To_String (Words (First)) = "private" and then First < Words.Last_Index then
                           First := First + 1;
                        end if;
                        if To_String (Words (First)) = "package" and then First < Words.Last_Index and then
                          To_String (Words (First + 1)) = "body"
                        then
                           First := First + 2;
                        elsif To_String (Words (First)) in "package" | "procedure" | "function" then
                           First := First + 1;
                        else
                           First := Words.Last_Index;
                        end if;
                        if First <= Words.Last_Index and then
                          To_String (Words ((if To_String (Words (Words.First_Index)) = "private"
                            then Words.First_Index + 1 else Words.First_Index))) in
                              "package" | "procedure" | "function"
                        then
                           declare
                              Unit_Name : Ada.Strings.Unbounded.Unbounded_String;
                           begin
                              for K in First .. Words.Last_Index loop
                                 exit when To_String (Words (K)) in "is" | "with" | "renames";
                                 Append (Unit_Name, To_String (Words (K)));
                              end loop;
                              Unit_Name_Checked := True;
                              declare
                                 Dot : constant Natural := Ada.Strings.Fixed.Index
                                   (Name, ".", Going => Ada.Strings.Backward);
                                 Stem : constant String :=
                                   (if Dot > Name'First then Name (Name'First .. Dot - 1) else Name);
                              begin
                                 if Canonical (To_String (Unit_Name)) /= Canonical (Stem) then
                                    Result.Naming_Errors := Result.Naming_Errors + 1;
                                    Note (SRC_02, "unit-file-name",
                                      "library unit name does not match its Ada source file", File_Lines);
                                 end if;
                              end;
                           end;
                        end if;
                     end;
                  end if;
                  for J in Words.First_Index .. Words.Last_Index loop
                     declare
                        Word : constant String := To_String (Words (J));
                        Previous : constant String :=
                          (if J = Words.First_Index then "" else To_String (Words (J - 1)));
                        Following : constant String :=
                          (if J = Words.Last_Index then "" else To_String (Words (J + 1)));
                     begin
                        if Word in "procedure" | "function" and then Previous /= "end" then
                           File_Max_Complexity := Natural'Max (File_Max_Complexity, Complexity);
                           Complexity := 1;
                        elsif Word = "if" and then Previous not in "end" | "elsif" then
                           Decisions := Decisions + 1;
                        elsif Word in "elsif" | "when" then
                           Decisions := Decisions + 1;
                        elsif Word in "case" | "loop" and then Previous /= "end" then
                           Decisions := Decisions + 1;
                        elsif (Word = "and" and then Following = "then") or else
                          (Word = "or" and then Following = "else")
                        then
                           Decisions := Decisions + 1;
                        end if;
                     end;
                  end loop;
               end if;
               if Line'Length > 120 then
                  Result.Long_Lines := Result.Long_Lines + 1;
                  Note (SRC_01, "line-length", "source line exceeds 120 columns", File_Lines);
               end if;
               if Contains (Line, Character'Val (9) & "") or else
                 (Line'Length > 0 and then Line (Line'Last) = ' ')
               then
                  Result.Hygiene_Errors := Result.Hygiene_Errors + 1;
                  Note (SRC_04, "source-hygiene", "tab or trailing whitespace", File_Lines);
               end if;
               if Decisions > 0 then
                  Complexity := Complexity + Decisions;
                  File_Max_Complexity := Natural'Max (File_Max_Complexity, Complexity);
               end if;
               if Contains (Clean, "register_routine") or else Contains (Clean, ".add_test") then
                  Result.Test_Registrations := Result.Test_Registrations + 1;
               end if;
               if Matches (Secret_Pattern, Clean) then
                  Result.Secret_Matches := Result.Secret_Matches + 1;
                  Note (SEC_01, "embedded-secret", "possible embedded credential assignment", File_Lines, High);
               end if;
               if Matches (Shell_Pattern, Clean) then
                  Result.Unsafe_Processes := Result.Unsafe_Processes + 1;
                  Note (SEC_02, "shell-execution", "shell-oriented process execution pattern", File_Lines, High);
               end if;
               if Is_Spec then
                  declare
                     Trimmed : constant String := Ada.Strings.Fixed.Trim (Line, Ada.Strings.Both);
                  begin
                     if Trimmed'Length > 2 and then Trimmed (Trimmed'First .. Trimmed'First + 1) = "--" then
                        Pending_Doc := Ada.Strings.Fixed.Trim
                          (Trimmed (Trimmed'First + 2 .. Trimmed'Last), Ada.Strings.Both)'Length > 0;
                     elsif Trimmed'Length > 0 then
                        if Pending_Doc and then
                          (Contains (Clean, "package ") or else Contains (Clean, "generic"))
                        then
                           Has_Docs := True;
                        end if;
                        Pending_Doc := False;
                     end if;
                  end;
               end if;
            end Scan_Line;
         begin
            Result.File_Count := Result.File_Count + 1;
            if Is_Test then
               Result.Test_Files := Result.Test_Files + 1;
            else
               Result.Production_Files := Result.Production_Files + 1;
            end if;
            if Is_Spec and then not Is_Test then
               Result.Spec_Count := Result.Spec_Count + 1;
            end if;
            if Name /= Lower (Name) then
               Result.Naming_Errors := Result.Naming_Errors + 1;
               Note (SRC_02, "file-name", "Ada source file name is not lowercase");
            end if;
            if Data'Length > 0 then
               for J in Data'Range loop
                  if Data (J) = Ada.Characters.Latin_1.LF then
                     if J > Start then Scan_Line (Data (Start .. J - 1)); else File_Lines := File_Lines + 1; end if;
                     Start := J + 1;
                  end if;
               end loop;
               if Start <= Data'Last then Scan_Line (Data (Start .. Data'Last)); end if;
            end if;
            Result.Lines := Result.Lines + File_Lines;
            if File_Lines > Policy.Maximum_Source_Lines and then not Size_Reviewed then
               Result.Oversized_Files := Result.Oversized_Files + 1;
               Note (SRC_06, "source-size", "source file exceeds configured line limit");
            end if;
            File_Max_Complexity := Natural'Max (File_Max_Complexity, Complexity);
            if not Complexity_Reviewed and then File_Max_Complexity > Result.Maximum_Complexity then
               Result.Maximum_Complexity := File_Max_Complexity;
            end if;
            if File_Max_Complexity > Policy.Maximum_Complexity and then not Complexity_Reviewed then
               Note (SRC_03, "complexity", "source complexity exceeds configured limit");
            end if;
            if Is_Spec and then not Is_Test and then not Has_Docs then
               Result.Undocumented_Specs := Result.Undocumented_Specs + 1;
               Note (DOC_01, "public-documentation", "public specification has no documentation comment");
            end if;
            declare
               procedure Visit_Handler (Line_Number : Positive; Source_Line : String) is
               begin
                  if not Contains (Lower (Source_Line), "aq: audited exception boundary") then
                     Result.Broad_Handlers := Result.Broad_Handlers + 1;
                     Note (SRC_05, "broad-handler", "broad exception handler", Line_Number);
                  end if;
               end Visit_Handler;
            begin
               Project_Tools.Ada_Source.Scan_Broad_Exception_Handlers (Path, Visit_Handler'Access);
            end;
         end;
      end loop;
   end Scan_Source;

   function Analyze_Source
     (Root   : String;
      Policy : Ada_Quality.Policy.Quality_Policy) return Source_Analysis
   is
      Result : Source_Analysis;
   begin
      Scan_Source (Root, Policy, Result);
      return Result;
   end Analyze_Source;

   function Tool_Result
     (Id      : Indicator_Id;
      Run     : Ada_Quality.Execution.Run_Result;
      Success : String;
      Failure : String) return Indicator_Result
   is
      Evidence : constant String := To_String (Run.Command) & " exit=" & Integer'Image (Run.Exit_Code) &
        (if Run.Truncated then " output-truncated" else "");
      Output : constant String := To_String (Run.Output);
      Diagnostic : constant String :=
        (if Output'Length <= 256 then Output
         else Output (Output'First .. Output'First + 255) & Ada.Characters.Latin_1.LF & "[diagnostic truncated]");
   begin
      case Run.Status is
         when Ada_Quality.Execution.Spawn_Error =>
            return Blocked_Result (Id, "tool could not be executed", To_String (Run.Output));
         when Ada_Quality.Execution.Timed_Out =>
            return Blocked_Result (Id, "tool timed out", Evidence);
         when Ada_Quality.Execution.Completed =>
            if Run.Exit_Code = 0 then return Passed (Id, Success, Evidence);
            else return Violated (Id, Failure,
              Evidence & (if Diagnostic'Length = 0 then "" else Ada.Characters.Latin_1.LF & Diagnostic)); end if;
      end case;
   end Tool_Result;

   function Run_Tool
     (Root : String;
      Name : String;
      Args : Project_Tools.Processes.Argument_Vectors.Vector;
      P    : Ada_Quality.Policy.Quality_Policy) return Ada_Quality.Execution.Run_Result is
     (Ada_Quality.Execution.Run (Root, Name, Args, P.Process_Timeout_Seconds, P.Maximum_Output_Bytes));

   function Args (Values : Project_Tools.Processes.Argument_Items)
     return Project_Tools.Processes.Argument_Vectors.Vector is
     (Project_Tools.Processes.Arguments (Values));

   function GPR_String (Text : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for Value of Text loop
         if Value = '"' then Append (Result, """"""); else Append (Result, Value); end if;
      end loop;
      return To_String (Result);
   end GPR_String;

   function GPR_Project_Name (Path : String) return String is
      Code     : constant String := Code_Without_Comments_And_Strings (Path);
      Position : Natural := Code'First;
      Marker   : constant String := "project";

      function Identifier_Character (Value : Character) return Boolean is
        (Value in 'a' .. 'z' | '0' .. '9' or else Value = '_');
   begin
      while Position <= Code'Last loop
         Position := Ada.Strings.Fixed.Index (Code, Marker, From => Position);
         if Position = 0 then return ""; end if;
         declare
            After : Natural := Position + Marker'Length;
         begin
            if (Position = Code'First or else not Identifier_Character (Code (Position - 1))) and then
              (After > Code'Last or else not Identifier_Character (Code (After)))
            then
               while After <= Code'Last and then Code (After) in ' ' | Character'Val (9) |
                 ASCII.CR | ASCII.LF
               loop
                  After := After + 1;
               end loop;
               declare
                  Last : Natural := After;
               begin
                  while Last <= Code'Last and then Identifier_Character (Code (Last)) loop
                     Last := Last + 1;
                  end loop;
                  if Last > After then return Code (After .. Last - 1); end if;
               end;
            end if;
            Position := Position + Marker'Length;
         end;
      end loop;
      return "";
   end GPR_Project_Name;

   function GPR_Has_Compiler_Package (Path : String) return Boolean is
      Code     : constant String := Code_Without_Comments_And_Strings (Path);
      Position : Natural := Code'First;
      Marker   : constant String := "package";

      function Identifier_Character (Value : Character) return Boolean is
        (Value in 'a' .. 'z' | '0' .. '9' or else Value = '_');
   begin
      while Position <= Code'Last loop
         Position := Ada.Strings.Fixed.Index (Code, Marker, From => Position);
         if Position = 0 then return False; end if;
         declare
            After : Natural := Position + Marker'Length;
         begin
            if (Position = Code'First or else not Identifier_Character (Code (Position - 1))) and then
              (After > Code'Last or else not Identifier_Character (Code (After)))
            then
               while After <= Code'Last and then Code (After) in ' ' | Character'Val (9) |
                 ASCII.CR | ASCII.LF
               loop
                  After := After + 1;
               end loop;
               if After + 7 <= Code'Last and then Code (After .. After + 7) = "compiler" and then
                 (After + 8 > Code'Last or else not Identifier_Character (Code (After + 8)))
               then
                  return True;
               end if;
            end if;
            Position := Position + Marker'Length;
         end;
      end loop;
      return False;
   end GPR_Has_Compiler_Package;

   function Assess
     (Project_Id : Natural;
      Root       : String;
      Policy     : Ada_Quality.Policy.Quality_Policy) return Assessment
   is
      Result       : Assessment;
      Metrics      : Source_Analysis;
      Manifest     : constant String := Project_Tools.Files.Join (Root, "alire.toml");
      Manifest_Data : constant String :=
        (if Project_Tools.Files.File_Exists (Manifest)
         then Project_Tools.Files.Read_Raw_File (Manifest) else "");
      GPR           : constant String :=
        Project_Tools.Files.Find_File (Root, Ada.Directories.Simple_Name (Root) & ".gpr");
      Any_GPR       : constant Project_Tools.Files.Path_List :=
        Project_Tools.Files.List_Tree (Root, "*.gpr", Skip_Names);
      function Selected_Project_Files return Text_Vectors.Vector is
         Result : Text_Vectors.Vector := Manifest_Project_Files (Root, Manifest_Data);
         Name   : constant Project_Tools.TOML.String_Parse_Result :=
           Project_Tools.TOML.Parse_String_After (Manifest_Data, "name", Manifest_Data'First);
      begin
         if Result.Is_Empty and then Name.Status = Project_Tools.TOML.Parsed_String then
            declare
               Named_GPR : constant String := Project_Tools.Files.Find_File
                 (Root, To_String (Name.Value) & ".gpr");
            begin
               if Named_GPR'Length > 0 then Result.Append (To_Unbounded_String (Named_GPR)); end if;
            end;
         end if;
         if Result.Is_Empty and then GPR'Length > 0 then
            Result.Append (To_Unbounded_String (GPR));
         elsif Result.Is_Empty and then Any_GPR'Length > 0 then
            Result.Append (Any_GPR (Any_GPR'First));
         end if;
         return Result;
      end Selected_Project_Files;
      Project_GPRs  : constant Text_Vectors.Vector := Selected_Project_Files;
      Checker_A     : constant String := Project_Tools.Files.Join (Root, "tools/bin/check_all");
      Checker_B     : constant String := Project_Tools.Files.Join (Root, "bin/check_all");
      Checker_C     : constant String := Project_Tools.Files.Join (Root, "tests/bin/check_all");
      --  The first release checker present, in this precedence order, or empty when none exists. The tests-crate
      --  location serves projects whose tooling lives entirely in their tests crate.
      Release_Checker : constant String :=
        (if Project_Tools.Files.File_Exists (Checker_A) then Checker_A
         elsif Project_Tools.Files.File_Exists (Checker_B) then Checker_B
         elsif Project_Tools.Files.File_Exists (Checker_C) then Checker_C
         else "");
      Test_Manifest : constant String := Project_Tools.Files.Join (Root, "tests/alire.toml");
      Coverage_File : constant String := Project_Tools.Files.Join (Root, "coverage/gcov-summary.txt");
      Before        : constant String := Source_Fingerprint (Root);
      Build_Run, Validation_Run, Warning_Run, Test_Build_Run, Test_Run_1, Test_Run_2,
        Toolchain_Run : Ada_Quality.Execution.Run_Result;
      Release_Run, Proof_Run, Doc_Run : Ada_Quality.Execution.Run_Result;
      Git_Before, Git_After : Ada_Quality.Execution.Run_Result;
      Has_SPARK : Boolean := False;
      Stage : Ada_Quality.Workspaces.Workspace;
      Execution_Root : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String (Root);
      Test_Artifact_1, Test_Artifact_2 : Ada.Strings.Unbounded.Unbounded_String;

      procedure Add (Item : Indicator_Result) is
      begin
         pragma Assert (Is_Valid (Item));
         Result.Results.Append (Item);
      end Add;

      function Present (Condition : Boolean; Id : Indicator_Id; Good, Bad, Evidence : String)
        return Indicator_Result is
        (if Condition then Passed (Id, Good, Evidence) else Violated (Id, Bad, Evidence));

      function Integer_Result
        (Condition : Boolean;
         Id        : Indicator_Id;
         Good, Bad : String;
         Evidence  : String;
         Value     : Natural) return Indicator_Result
      is
         Item : Indicator_Result := Present (Condition, Id, Good, Bad, Evidence);
      begin
         Item.Measurement :=
           (Kind => Integer_Value, Integer_Data => Long_Long_Integer (Value));
         if not Condition then
            for Finding of Metrics.Findings loop
               if Finding.Indicator = Id then
                  if Item.Findings.Length = 1 and then
                    Length (Item.Findings.First_Element.Relative_Path) = 0
                  then
                     Item.Findings.Clear;
                  end if;
                  Item.Findings.Append (Finding);
               end if;
            end loop;
         end if;
         return Item;
      end Integer_Result;

      function Execute
        (Label     : String;
         Directory : String;
         Name      : String;
         Arguments : Project_Tools.Processes.Argument_Vectors.Vector)
         return Ada_Quality.Execution.Run_Result
      is
         Run : constant Ada_Quality.Execution.Run_Result := Run_Tool (Directory, Name, Arguments, Policy);
         Hash : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      begin
         for C of To_String (Run.Output) loop
            Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
         end loop;
         Result.Executions.Append
           (Tool_Execution'
              (Tool => To_Unbounded_String (Label), Command => Run.Command,
               Status =>
                 (case Run.Status is
                    when Ada_Quality.Execution.Completed => Tool_Completed,
                    when Ada_Quality.Execution.Timed_Out => Tool_Timed_Out,
                    when Ada_Quality.Execution.Spawn_Error => Tool_Spawn_Error),
               Exit_Code => Run.Exit_Code, Output_Digest => To_Unbounded_String (Hash_Image (Hash)),
               Output_Bytes => Length (Run.Output), Truncated => Run.Truncated));
         return Run;
      end Execute;

      procedure Measure_Build is
      begin
      Result.Project_Id := Project_Id;
      Result.Project_Path := To_Unbounded_String (Root);
      Result.Source_Fingerprint := To_Unbounded_String (Before);
      Result.Policy_Fingerprint := To_Unbounded_String (Ada_Quality.Policy.Fingerprint (Policy));
      Metrics := Analyze_Source (Root, Policy);
      Ada_Quality.Workspaces.Prepare
        (Stage, Root, Ada.Strings.Fixed.Trim (Natural'Image (Project_Id), Ada.Strings.Both));
      Execution_Root := To_Unbounded_String (Ada_Quality.Workspaces.Path (Stage));
      if Policy.Require_Clean_Worktree then
         Git_Before := Execute
           ("git-status-before", Root, Ada_Quality.Tools.Program (Ada_Quality.Tools.Git),
            Args ([Project_Tools.Processes.Argument ("-C"),
            Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("status"),
            Project_Tools.Processes.Argument ("--porcelain"),
            Project_Tools.Processes.Argument ("--untracked-files=all")]));
      end if;

      Add (Present (Project_Tools.Files.File_Exists (Manifest) and then Valid_Manifest (Manifest_Data), STR_01,
        "valid Alire manifest present", "missing or malformed alire.toml", Manifest));
      Add (Present (Any_GPR'Length > 0, STR_02, "GPR project present", "missing GPR project", Root));
      Add (Present (Project_Tools.Files.Directory_Exists (Project_Tools.Files.Join (Root, "src")), STR_03,
        "standard src layout present", "missing src directory", Root));
      Add (Present (Project_Tools.Files.File_Exists (Test_Manifest), STR_04,
        "test subcrate present", "missing tests/alire.toml", Test_Manifest));
      Add (Present (Release_Checker'Length > 0, STR_05, "release checker present", "missing release checker", Root));

      if Project_Tools.Files.File_Exists (Manifest) and then Valid_Manifest (Manifest_Data) and then
        Any_GPR'Length > 0
      then
         Build_Run := Execute
           ("alire-build", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
            Args ([Project_Tools.Processes.Argument ("build")]));
         Validation_Run := Execute
           ("alire-validation-build", To_String (Execution_Root),
            Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
            Args ([Project_Tools.Processes.Argument ("build"),
            Project_Tools.Processes.Argument ("--validation"), Project_Tools.Processes.Argument ("--"),
            Project_Tools.Processes.Argument ("-f")]));
         for Index in Project_GPRs.First_Index .. Project_GPRs.Last_Index loop
            declare
               Original_Project : constant String := Project_Tools.Files.Join
                 (To_String (Execution_Root), Relative (Root, To_String (Project_GPRs (Index))));
               Original_Name : constant String := GPR_Project_Name (Original_Project);
               Inherited_Switches : constant String :=
                 (if GPR_Has_Compiler_Package (Original_Project)
                  then Original_Name & ".Compiler'Default_Switches (""Ada"") & "
                  else "");
               Suffix : constant String := Ada.Strings.Fixed.Trim (Positive'Image (Index), Ada.Strings.Both);
               Wrapper_Name : constant String := "Ada_Quality_Warning_Gate_" & Suffix;
               Warning_Project : constant String := Ada_Quality.Workspaces.Scratch_Path
                 (Stage, "ada_quality_warning_gate_" & Suffix & ".gpr");
               Current_Run : Ada_Quality.Execution.Run_Result;
            begin
               if Original_Name'Length = 0 then
                  raise Constraint_Error with "cannot determine GPR project name: " & Original_Project;
               end if;
               Project_Tools.Files.Write_Text_File
                 (Warning_Project,
                  "project " & Wrapper_Name & " extends """ & GPR_String (Original_Project) & """ is" &
                  Ada.Characters.Latin_1.LF &
                  "   package Compiler is" & Ada.Characters.Latin_1.LF &
                  "      for Default_Switches (""Ada"") use " & Inherited_Switches &
                  "(""-gnatwa"", ""-gnatwe"");" &
                  Ada.Characters.Latin_1.LF &
                  "   end Compiler;" & Ada.Characters.Latin_1.LF &
                  "end " & Wrapper_Name & ";" & Ada.Characters.Latin_1.LF);
               Current_Run := Execute
                 ("compiler-warning-build-" & Suffix, To_String (Execution_Root),
                  Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
                  Args ([Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
                  Project_Tools.Processes.Argument ("gprbuild"), Project_Tools.Processes.Argument ("-P"),
                  Project_Tools.Processes.Argument (Warning_Project), Project_Tools.Processes.Argument ("-p"),
                  Project_Tools.Processes.Argument ("-f")]));
               if Index = Project_GPRs.First_Index or else
                 (Warning_Run.Status = Ada_Quality.Execution.Completed and then Warning_Run.Exit_Code = 0 and then
                  (Current_Run.Status /= Ada_Quality.Execution.Completed or else Current_Run.Exit_Code /= 0))
               then
                  Warning_Run := Current_Run;
               end if;
            end;
         end loop;
         Toolchain_Run := Execute
           ("gnat-toolchain", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
            Args ([Project_Tools.Processes.Argument ("exec"),
            Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("gnatls"),
            Project_Tools.Processes.Argument ("--version")]));
         Result.Toolchain_Fingerprint := Result.Executions.Last_Element.Output_Digest;
         Add (Tool_Result (BLD_01, Build_Run, "project builds", "project build failed"));
         Add (Tool_Result (BLD_02, Validation_Run, "validation build passes", "validation build failed"));
         Add (Tool_Result (BLD_03, Warning_Run, "compiler warnings gate passes", "compiler warnings gate failed"));
         if Toolchain_Run.Status = Ada_Quality.Execution.Completed and then Toolchain_Run.Exit_Code = 0 and then
           Contains (To_String (Toolchain_Run.Output), "GNAT")
         then
            Add (Passed (BLD_04, "Alire GNAT toolchain identified", To_String (Toolchain_Run.Command)));
         elsif Toolchain_Run.Status = Ada_Quality.Execution.Completed and then Toolchain_Run.Exit_Code = 0 then
            Add (Blocked_Result (BLD_04, "toolchain output did not identify GNAT", To_String (Toolchain_Run.Command)));
         else
            Add (Tool_Result (BLD_04, Toolchain_Run, "Alire toolchain available", "toolchain query failed"));
         end if;
      else
         Add (Blocked_Result (BLD_01, "build prerequisites unavailable", "requires STR-01 and STR-02"));
         Add (Blocked_Result (BLD_02, "build prerequisites unavailable", "requires BLD-01"));
         Add (Blocked_Result (BLD_03, "build prerequisites unavailable", "requires BLD-01"));
         Add (Blocked_Result (BLD_04, "toolchain prerequisites unavailable", "requires STR-01 and STR-02"));
      end if;

      end Measure_Build;

      procedure Measure_Tests is
         Test_Directory : constant String := Project_Tools.Files.Join
           (To_String (Execution_Root), "tests");
         Test_Project : constant String := Test_Project_File (To_String (Execution_Root));
         Test_Binary : constant String := Test_Suite_Executable (To_String (Execution_Root));
         Baseline_Directory : constant String :=
           Ada_Quality.Workspaces.Scratch_Path (Stage, "determinism-baseline");
         Artifact_Error : Ada.Strings.Unbounded.Unbounded_String;

         --  Fingerprint the project state after a test run. A project whose artifacts exceed the fingerprint limits
         --  cannot show deterministic artifacts; that blocks TST-04 instead of aborting the assessment.
         function State_After_Run return Ada.Strings.Unbounded.Unbounded_String is
         begin
            return To_Unbounded_String (Project_State_Fingerprint (To_String (Execution_Root)));
         exception
            when Error : Constraint_Error =>
               declare
                  Message : constant String := Ada.Exceptions.Exception_Message (Error);
               begin
                  if Message'Length < 8 or else Message (Message'First .. Message'First + 7) /= "project " then
                     raise;
                  end if;
                  Artifact_Error := To_Unbounded_String (Message);
                  return Null_Unbounded_String;
               end;
         end State_After_Run;
      begin
      if Project_Tools.Files.File_Exists (Test_Manifest) and then
        Build_Run.Status = Ada_Quality.Execution.Completed and then Build_Run.Exit_Code = 0
      then
         Test_Build_Run := Execute
           ("aunit-build", Test_Directory, Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
            Args ([Project_Tools.Processes.Argument ("exec"),
            Project_Tools.Processes.Argument ("--"),
            Project_Tools.Processes.Argument ("gprbuild"),
            Project_Tools.Processes.Argument ("-P"),
            Project_Tools.Processes.Argument (Test_Project),
            Project_Tools.Processes.Argument ("-p"),
            Project_Tools.Processes.Argument ("-j0")]));
         if Test_Build_Run.Status = Ada_Quality.Execution.Completed and then Test_Build_Run.Exit_Code = 0 then
            Copy_State_Tree (To_String (Execution_Root), Baseline_Directory);
            Test_Run_1 := Execute
              ("aunit-first", Test_Directory, Test_Binary, Project_Tools.Processes.No_Arguments);
            Test_Artifact_1 := State_After_Run;
            Project_Tools.Files.Delete_Tree (To_String (Execution_Root));
            Copy_State_Tree (Baseline_Directory, To_String (Execution_Root));
            Test_Run_2 := Execute
              ("aunit-second", Test_Directory, Test_Binary, Project_Tools.Processes.No_Arguments);
            Test_Artifact_2 := State_After_Run;
            Add (Tool_Result (TST_01, Test_Run_1, "AUnit suite passes", "AUnit suite failed"));
         else
            Test_Run_1 := Test_Build_Run;
            Test_Run_2 := Test_Build_Run;
            Add (Tool_Result (TST_01, Test_Build_Run, "AUnit suite builds", "AUnit suite build failed"));
         end if;
         Add (Integer_Result (Metrics.Test_Registrations > 0, TST_02,
           "registered tests found", "no AUnit registrations found", "Register_Routine scan",
           Metrics.Test_Registrations));
         if Length (Artifact_Error) > 0 then
            Add (Blocked_Result (TST_04, "project artifacts could not be fingerprinted", To_String (Artifact_Error)));
         else
            Add (Present (Test_Run_1.Status = Ada_Quality.Execution.Completed and then Test_Run_1.Exit_Code = 0 and then
              Test_Run_2.Status = Ada_Quality.Execution.Completed and then Test_Run_2.Exit_Code = 0 and then
              Normalize_Test_Output (To_String (Test_Run_1.Output)) =
                Normalize_Test_Output (To_String (Test_Run_2.Output)) and then
              Test_Artifact_1 = Test_Artifact_2, TST_04,
              "test execution, normalized output, and artifacts are deterministic across two runs",
              "test runs differed in execution, normalized output, or project artifacts",
              "two AUnit runs restored from one post-build baseline with normalized output and state fingerprints"));
         end if;
      else
         Add (Blocked_Result (TST_01, "test subcrate unavailable", Test_Manifest));
         Add (Blocked_Result (TST_02, "test subcrate unavailable", Test_Manifest));
         Add (Blocked_Result (TST_04, "test subcrate unavailable", Test_Manifest));
      end if;

      end Measure_Tests;

      procedure Measure_Coverage is
      begin
      if Test_Run_1.Status /= Ada_Quality.Execution.Completed or else Test_Run_1.Exit_Code /= 0 then
         Add (Blocked_Result (TST_03, "coverage prerequisite test execution did not pass", "requires TST-01"));
      elsif Project_Tools.Files.File_Exists (Coverage_File) then
         declare
            Covered_Text : constant String := Project_Tools.Files.Value_Of (Coverage_File, "covered");
            Total_Text   : constant String := Project_Tools.Files.Value_Of (Coverage_File, "total");
            Coverage_Fingerprint : constant String :=
              Project_Tools.Files.Value_Of (Coverage_File, "source_fingerprint");
            Coverage_Toolchain : constant String :=
              Project_Tools.Files.Value_Of (Coverage_File, "toolchain_fingerprint");
            Coverage_Complete : constant String :=
              Lower (Project_Tools.Files.Value_Of (Coverage_File, "complete"));
            Coverage_Inventory : constant String :=
              Project_Tools.Files.Value_Of (Coverage_File, "inventory");
            Summary : constant Project_Tools.Gcov.Coverage_Summary :=
              Project_Tools.Gcov.Parse_Lines_Executed_Output
                (Project_Tools.Files.Read_Raw_File (Coverage_File));
            Covered : constant Natural :=
              (if Covered_Text'Length > 0 then Natural'Value (Covered_Text)
               else Project_Tools.Gcov.Covered_Lines (Summary));
            Total   : constant Natural :=
              (if Total_Text'Length > 0 then Natural'Value (Total_Text)
               else Project_Tools.Gcov.Total_Lines (Summary));
         begin
            if Coverage_Complete /= "true" or else Coverage_Inventory /= "gcov-production-lines-v2" then
               Add (Blocked_Result (TST_03, "coverage evidence does not claim a complete production inventory",
                 "complete=true and inventory=gcov-production-lines-v2 are required"));
            elsif Coverage_Fingerprint'Length = 0 or else Coverage_Fingerprint /= Before then
               Add (Blocked_Result (TST_03, "coverage evidence does not match the assessed source",
                 "expected=" & Before & " recorded=" & Coverage_Fingerprint));
            elsif Coverage_Toolchain'Length = 0 or else
              Coverage_Toolchain /= To_String (Result.Toolchain_Fingerprint)
            then
               Add (Blocked_Result (TST_03, "coverage evidence does not match the assessed toolchain",
                 "expected=" & To_String (Result.Toolchain_Fingerprint) & " recorded=" & Coverage_Toolchain));
            else
               declare
                  Item : Indicator_Result :=
                    Present (Coverage_Passes (Covered, Total, Policy.Coverage_Minimum_Basis_Points), TST_03,
                      "production line coverage meets policy", "production line coverage is below policy or empty",
                      Natural'Image (Covered) & "/" & Natural'Image (Total) & " lines");
               begin
                  Item.Measurement :=
                    (Kind => Decimal_Value,
                     Basis_Points =>
                       (if Total = 0 then 0
                        else Long_Long_Integer (Covered) * 10_000 / Long_Long_Integer (Total)));
                  Add (Item);
               end;
            end if;
         exception
            when Constraint_Error =>
               Add (Blocked_Result (TST_03, "coverage evidence is malformed", Coverage_File));
         end;
      else
         Add (Blocked_Result (TST_03, "complete production coverage evidence unavailable",
           "expected complete gcov inventory at " & Coverage_File));
      end if;

      end Measure_Coverage;

      procedure Measure_Source is
      begin
      Add (Integer_Result (Metrics.Long_Lines = 0, SRC_01,
        "source formatting passes", "source lines exceed 120 columns",
        Natural'Image (Metrics.Long_Lines) & " long lines", Metrics.Long_Lines));
      Add (Integer_Result (Metrics.Naming_Errors = 0, SRC_02,
        "source file naming passes", "source file naming violations",
        Natural'Image (Metrics.Naming_Errors) & " files", Metrics.Naming_Errors));
      Add (Integer_Result (Metrics.Maximum_Complexity <= Policy.Maximum_Complexity, SRC_03,
        "complexity within policy", "complexity exceeds policy", Natural'Image (Metrics.Maximum_Complexity),
        Metrics.Maximum_Complexity));
      Add (Integer_Result (Metrics.Hygiene_Errors = 0, SRC_04,
        "source hygiene passes", "source hygiene violations",
        Natural'Image (Metrics.Hygiene_Errors) & " findings", Metrics.Hygiene_Errors));
      Add (Integer_Result (Metrics.Broad_Handlers = 0, SRC_05,
        "exception handling passes", "broad exception handlers found",
        Natural'Image (Metrics.Broad_Handlers) & " handlers", Metrics.Broad_Handlers));
      Add (Integer_Result (Metrics.Oversized_Files = 0, SRC_06,
        "source sizes within policy", "oversized source files found",
        Natural'Image (Metrics.Oversized_Files) & " files", Metrics.Oversized_Files));

      end Measure_Source;

      procedure Measure_Documentation is
      begin
      if Any_GPR'Length > 0 then
         declare
            Project_File : constant String :=
              Project_Tools.Files.Join
                (To_String (Execution_Root), Relative
                   (Root, (if GPR'Length > 0 then GPR else To_String (Any_GPR (Any_GPR'First)))));
            Output_Dir : constant String := Ada_Quality.Workspaces.Scratch_Path (Stage, "gnatdoc");
         begin
            if Project_Tools.Files.Exists (Output_Dir) then
               Project_Tools.Files.Delete_Tree (Output_Dir);
            end if;
            Doc_Run := Execute
              ("gnatdoc", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
               Args ([Project_Tools.Processes.Argument ("exec"),
               Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("gnatdoc"),
               Project_Tools.Processes.Argument ("-P"), Project_Tools.Processes.Argument (Project_File),
               Project_Tools.Processes.Argument ("-O"), Project_Tools.Processes.Argument (Output_Dir),
               Project_Tools.Processes.Argument ("--warnings")]));
            declare
               Warning_Count : constant Natural :=
                 Occurrences (Lower (To_String (Doc_Run.Output)), "warning:");
            begin
               if Doc_Run.Status /= Ada_Quality.Execution.Completed or else Doc_Run.Exit_Code /= 0 then
                  Add (Blocked_Result
                    (DOC_01, "public declaration documentation could not be evaluated",
                     To_String (Doc_Run.Command)));
               elsif Metrics.Spec_Count = 0 then
                  Add (Violated (DOC_01, "no public specifications were available for documentation audit", Root));
               else
                  Add (Integer_Result
                    (Warning_Count = 0, DOC_01,
                     "every public declaration passes the GNATdoc documentation audit",
                     "GNATdoc reported undocumented or malformed public declarations",
                     Natural'Image (Warning_Count) & " documentation warnings", Warning_Count));
               end if;
            end;
            if Doc_Run.Status = Ada_Quality.Execution.Completed and then Doc_Run.Exit_Code = 0 and then
              Contains (Lower (To_String (Doc_Run.Output)), "warning:") then
               Add (Violated (DOC_02, "GNATdoc reported documentation warnings", To_String (Doc_Run.Command)));
            else
               Add
                 (Tool_Result
                    (DOC_02, Doc_Run, "GNATdoc generation passes without warnings", "GNATdoc generation failed"));
            end if;
            if Project_Tools.Files.Exists (Output_Dir) then
               Project_Tools.Files.Delete_Tree (Output_Dir);
            end if;
         end;
      else
         Add (Blocked_Result (DOC_01, "public declaration documentation requires a GPR project", Root));
         Add (Blocked_Result (DOC_02, "GNATdoc cannot run without a GPR project", Root));
      end if;
      Add (Present (Project_Tools.Files.File_Exists (Project_Tools.Files.Join (Root, "README.md")), DOC_03,
        "required documentation present", "README.md missing", Root));

      end Measure_Documentation;

      procedure Measure_Dependencies_And_Security is
      begin
      Add (Tool_Result (DEP_01, Build_Run, "dependencies resolve", "dependency resolution/build failed"));
      Add (Present (not Matches (Local_Pin_Pattern, Without_TOML_Comments (Manifest_Data)), DEP_02,
        "manifest contains no local path pins", "manifest contains local path pins", Manifest));
      Add (Tool_Result (DEP_03, Build_Run, "dependency solution is buildable", "dependency solution inconsistent"));

      Add (Integer_Result (Metrics.Secret_Matches = 0, SEC_01, "no embedded secret patterns found",
        "possible embedded secrets found", Natural'Image (Metrics.Secret_Matches) & " matches",
        Metrics.Secret_Matches));
      Add (Integer_Result (Metrics.Unsafe_Processes = 0, SEC_02, "no shell process patterns found",
        "unsafe shell process patterns found", Natural'Image (Metrics.Unsafe_Processes) & " matches",
        Metrics.Unsafe_Processes));
      declare
         Artifacts : Natural := 0;
         Links     : constant Natural := Natural (All_Links (Root).Length);
      begin
         for Path of All_Files (Root) loop
            declare
               Name : constant String := Lower (To_String (Path));
            begin
               if (Name'Length >= 2 and then Name (Name'Last - 1 .. Name'Last) = ".o") or else
                 (Name'Length >= 4 and then Name (Name'Last - 3 .. Name'Last) = ".pyc")
               then Artifacts := Artifacts + 1; end if;
            end;
         end loop;
         Add (Integer_Result (Artifacts = 0 and then Links = 0, SEC_03,
           "no forbidden artifacts or symbolic links",
           "forbidden artifacts or symbolic links found",
           Natural'Image (Artifacts) & " artifacts," & Natural'Image (Links) & " links", Artifacts + Links));
      end;

      end Measure_Dependencies_And_Security;

      procedure Measure_Release is
      begin
      if Release_Checker'Length > 0 then
         declare
            Staged_Checker : constant String := Project_Tools.Files.Join
              (To_String (Execution_Root), Relative (Root, Release_Checker));
         begin
            if Project_Tools.Files.File_Exists (Staged_Checker) then
               Release_Run := Execute
                 ("release-checker", To_String (Execution_Root), Staged_Checker,
                  Project_Tools.Processes.No_Arguments);
               Add (Tool_Result (REL_01, Release_Run, "release checker passes", "release checker failed"));
            else
               Add (Blocked_Result (REL_01, "release checker absent from staged build", Staged_Checker));
            end if;
         end;
      else
         Add (Blocked_Result (REL_01, "release checker missing", Root));
      end if;
      Add (Present (Has_Manifest_String (Manifest_Data, "licenses") and then
        (Project_Tools.Files.File_Exists (Project_Tools.Files.Join (Root, "LICENSE")) or else
         Project_Tools.Files.File_Exists (Project_Tools.Files.Join (Root, "LICENSE.md"))), REL_02,
        "license metadata and file present", "license metadata/file inconsistent", Manifest));
      Add (Present (Valid_Manifest (Manifest_Data) and then Has_Manifest_String (Manifest_Data, "licenses"),
        REL_03, "release manifest fields present",
        "release manifest fields missing", Manifest));

      end Measure_Release;

      procedure Measure_Proof is
         Dedicated : constant Project_Tools.Files.Path_List := Dedicated_Proof_Projects (Root);

         function Prove (Project_File : String) return Ada_Quality.Execution.Run_Result is
           (Execute
              ("gnatprove", To_String (Execution_Root), Ada_Quality.Tools.Program (Ada_Quality.Tools.Alire),
               Args ([Project_Tools.Processes.Argument ("exec"),
               Project_Tools.Processes.Argument ("--"), Project_Tools.Processes.Argument ("gnatprove"),
               Project_Tools.Processes.Argument ("-P"), Project_Tools.Processes.Argument (Project_File),
               Project_Tools.Processes.Argument ("--mode=prove"),
               Project_Tools.Processes.Argument ("--level=2")])));
      begin
      Has_SPARK := Declares_SPARK (Root);
      if Has_SPARK and then Dedicated'Length > 0 then
         --  Dedicated proof projects name exactly the SPARK units; each must prove.
         for Project of Dedicated loop
            Proof_Run := Prove
              (Project_Tools.Files.Join (To_String (Execution_Root), Relative (Root, To_String (Project))));
            exit when Proof_Run.Status /= Ada_Quality.Execution.Completed or else Proof_Run.Exit_Code /= 0;
         end loop;
         Add (Tool_Result (PRF_01, Proof_Run, "declared SPARK units proved", "SPARK proof failed or is incomplete"));
      elsif Has_SPARK and then Any_GPR'Length > 0 then
         declare
            Project_File : constant String :=
              Project_Tools.Files.Join
                (To_String (Execution_Root), Relative
                   (Root, (if GPR'Length > 0 then GPR else To_String (Any_GPR (Any_GPR'First)))));
         begin
            Proof_Run := Prove (Project_File);
            Add (Tool_Result (PRF_01, Proof_Run, "declared SPARK units proved", "SPARK proof failed or is incomplete"));
         end;
      else
         Add (Not_Applicable_Result (PRF_01, "no source unit declares SPARK_Mode"));
      end if;

      end Measure_Proof;

      procedure Finalize_Assessment is
      begin
      declare
         After : constant String := Source_Fingerprint (Root);
      begin
         if Before /= After then
            Add (Violated (REL_04, "assessment modified source inputs",
              "before=" & Before & " after=" & After));
         elsif not Policy.Require_Clean_Worktree then
            Add (Passed (REL_04, "source fingerprint unchanged", "clean-worktree policy disabled"));
         else
            Git_After := Execute
              ("git-status-after", Root, Ada_Quality.Tools.Program (Ada_Quality.Tools.Git),
               Args ([Project_Tools.Processes.Argument ("-C"),
               Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("status"),
               Project_Tools.Processes.Argument ("--porcelain"),
               Project_Tools.Processes.Argument ("--untracked-files=all")]));
            if Git_Before.Status /= Ada_Quality.Execution.Completed or else
              Git_After.Status /= Ada_Quality.Execution.Completed or else
              Git_Before.Exit_Code /= 0 or else Git_After.Exit_Code /= 0
            then
               Add (Blocked_Result (REL_04, "clean worktree evidence unavailable",
                 "git status must succeed before and after assessment"));
            elsif Length (Git_Before.Output) > 0 or else Length (Git_After.Output) > 0 then
               Add (Violated (REL_04, "Git worktree is not clean",
                 "git status reported tracked or untracked changes"));
            else
               Add (Passed (REL_04, "clean staged source remained unchanged",
                 "git status clean before and after; fingerprint=" & Before));
            end if;
         end if;
         if Before = After then Result.Status := Assessment_Completed; else Result.Status := Assessment_Invalid; end if;
      end;

      end Finalize_Assessment;

   begin
      Measure_Build;
      Measure_Tests;
      Measure_Coverage;
      Measure_Source;
      Measure_Documentation;
      Measure_Dependencies_And_Security;
      Measure_Release;
      Measure_Proof;
      Finalize_Assessment;

      pragma Assert (Result.Results.Length = 33);
      Ada_Quality.Workspaces.Cleanup (Stage);
      return Result;
   exception
      when others =>  --  AQ: audited exception boundary
         Ada_Quality.Workspaces.Cleanup (Stage);
         raise;
   end Assess;
end Ada_Quality.Checks;
