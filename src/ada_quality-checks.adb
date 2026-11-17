with Ada.Characters.Handling;
with Ada.Characters.Latin_1;
with Ada.Containers.Vectors;
with Ada.Containers.Ordered_Sets;
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
with Ada_Quality.Evaluation;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Manifests;
with Ada_Quality.Resource_Limits;
with Ada_Quality.Source_Safety;
with Ada_Quality.Tools;
with Ada_Quality.Workspaces;

--  AQ-WAIVER: SRC-03 target=manifest_strings justification=manifest helpers share one bounded parse
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
   Local_Pin_Pattern : constant Regexp.Compile_Result :=
     Regexp.Compile ("path\s*=");

   package Text_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Ada.Strings.Unbounded.Unbounded_String);
   package Text_Sorting is new Text_Vectors.Generic_Sorting
     ("<" => Ada.Strings.Unbounded."<");
   package Text_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "<" => Ada.Strings.Unbounded."<",
      "=" => Ada.Strings.Unbounded."=");

   type Dependency_Entry is record
      Name       : Ada.Strings.Unbounded.Unbounded_String;
      Constraint : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   package Dependency_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Dependency_Entry);

   Skip_Names : constant Project_Tools.Files.Name_List :=
     [To_Unbounded_String (".git"), To_Unbounded_String (".alire"),
      To_Unbounded_String ("obj"), To_Unbounded_String ("bin"),
      To_Unbounded_String ("cov-obj"), To_Unbounded_String ("cov-bin"),
      To_Unbounded_String ("coverage"), To_Unbounded_String ("lib"),
      To_Unbounded_String ("gnatprove")];

   Maximum_Tree_Depth : constant Positive :=
     Ada_Quality.Resource_Limits.Maximum_Tree_Depth;
   Maximum_Project_Files : constant Positive :=
     Ada_Quality.Resource_Limits.Maximum_Project_Files;
   Maximum_File_Bytes : constant Positive :=
     Ada_Quality.Resource_Limits.Maximum_File_Bytes;
   Maximum_Fingerprint_Bytes : constant Positive :=
     Ada_Quality.Resource_Limits.Maximum_Aggregate_Bytes;

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

   function Documentation_Warning_Count (Output : String) return Natural is
      Text    : constant String := Lower (Output);
      Pattern : constant String := " is not documented";
      Start   : Natural := Text'First;
      Warnings : Text_Sets.Set;

      procedure Include_Line (Last : Natural) is
      begin
         if Last >= Start and then Ada.Strings.Fixed.Index (Text (Start .. Last), Pattern) > 0 then
            Warnings.Include (To_Unbounded_String (Text (Start .. Last)));
         end if;
      end Include_Line;
   begin
      if Text'Length = 0 then return 0; end if;
      for Index in Text'Range loop
         if Text (Index) = Ada.Characters.Latin_1.LF then
            Include_Line (Index - 1);
            Start := Index + 1;
         end if;
      end loop;
      if Start <= Text'Last then Include_Line (Text'Last); end if;
      return Natural (Warnings.Length);
   end Documentation_Warning_Count;

   function Valid_Manifest (Text : String) return Boolean is
      Name, Version : Ada.Strings.Unbounded.Unbounded_String;
   begin
      return Ada_Quality.Manifests.Top_Level_String (Text, "name", Name) and then
        Ada_Quality.Manifests.Top_Level_String (Text, "version", Version);
   end Valid_Manifest;

   function Has_Manifest_String (Text, Key : String) return Boolean is
      Value : Ada.Strings.Unbounded.Unbounded_String;
   begin
      return Ada_Quality.Manifests.Top_Level_String (Text, Key, Value);
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

   function TOML_Structure (Text : String) return String is
      Result    : String := Without_TOML_Comments (Text);
      In_String : Boolean := False;
      Quote     : Character := Character'Val (0);
      Escaped   : Boolean := False;
   begin
      for J in Result'Range loop
         if Result (J) = Ada.Characters.Latin_1.LF then
            In_String := False;
            Escaped := False;
         elsif In_String then
            declare
               Current : constant Character := Result (J);
            begin
               Result (J) := ' ';
               if Current = Quote and then not Escaped then In_String := False; end if;
               Escaped := Current = '\' and then not Escaped;
            end;
         elsif Result (J) in ''' | '"' then
            In_String := True;
            Quote := Result (J);
            Result (J) := ' ';
         end if;
      end loop;
      return Result;
   end TOML_Structure;

   function Has_Suffix (Text, Suffix : String) return Boolean;

   --  Return the string elements of the top-level array Key in an Alire manifest, or an empty vector when Key is
   --  absent or its array is malformed.
   function Manifest_Strings (Text, Key : String) return Text_Vectors.Vector is
      Result : Text_Vectors.Vector;
      Values : Ada_Quality.Manifests.String_Vectors.Vector;
   begin
      if Ada_Quality.Manifests.Top_Level_String_Array (Text, Key, Values) then
         for Value of Values loop Result.Append (Value); end loop;
      end if;
      return Result;
   end Manifest_Strings;

   function Dependency_Consistency
     (Manifest_Text, Lock_Text : String) return Dependency_Evidence_Status is separate;

   procedure Parse_SPDX
     (Text : String;
      Valid, Supported : out Boolean;
      Licenses, Exceptions : out Text_Vectors.Vector) is separate;

   function License_Evidence
     (Root, Manifest_Text : String) return Metadata_Evidence_Status is separate;

   function Valid_Release_Manifest (Manifest_Text : String) return Boolean is
     (Valid_Manifest (Manifest_Text) and then
      Has_Manifest_String (Manifest_Text, "licenses") and then
      Has_Manifest_String (Manifest_Text, "description") and then
      not Manifest_Strings (Manifest_Text, "authors").Is_Empty and then
      not Manifest_Strings (Manifest_Text, "maintainers").Is_Empty);

   function Classify_Proof_Applicability
     (SPARK_Declared, Project_Available : Boolean) return Proof_Applicability_Status is
     (if not SPARK_Declared then Proof_Not_Applicable
      elsif Project_Available then Proof_Ready else Proof_Blocked);

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

   function Tree_Entries (Root : String; Links : Boolean) return Text_Vectors.Vector is separate;

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

   function Finding_Fingerprint
     (Indicator : Indicator_Id;
      Rule, Path, Message : String;
      Context : String := "") return String is
     (Ada_Quality.Finding_Identity.Create (Indicator, Rule, Path, Message, Context));

   function Artifact_Files (Root : String) return Text_Vectors.Vector is separate;

   function Tree_Fingerprint
     (Root             : String;
      Files            : Text_Vectors.Vector;
      Ignore_Generated : Boolean) return String is separate;

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

   procedure Copy_State_Tree (Source, Target : String) is separate;

   procedure Add_Finding
     (Item    : in out Indicator_Result;
      Rule    : String;
      Message : String;
      Path    : String := "";
      Line    : Natural := 0;
      Level   : Severity := Medium)
   is
      Fingerprint : constant String :=
        Finding_Fingerprint (Item.Indicator, Rule, Path, Message);
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

   type Review_Waiver is record
      Valid         : Boolean := False;
      Target        : Ada.Strings.Unbounded.Unbounded_String;
      Justification : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Find_Review_Waiver (Data, Rule, Expected_Target : String) return Review_Waiver is
      Prefix : constant String := "aq-waiver: " & Lower (Rule) & " target=";
      Justification_Tag : constant String := " justification=";
      Wanted : constant String := Lower (Expected_Target);
      Cursor : Natural := Data'First;
   begin
      if Data'Length = 0 then return (others => <>); end if;
      while Cursor <= Data'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index (Data, [ASCII.LF], From => Cursor);
         begin
            if Stop = 0 then Stop := Data'Last + 1; end if;
            declare
               Line : constant String := Lower (Ada.Strings.Fixed.Trim
                 (Data (Cursor .. Stop - 1), Ada.Strings.Both));
            begin
               if Line'Length > 2 and then Line (Line'First .. Line'First + 1) = "--"
               then
                  declare
                     Payload : constant String := Ada.Strings.Fixed.Trim
                       (Line (Line'First + 2 .. Line'Last), Ada.Strings.Both);
                     Justification_At : constant Natural := Ada.Strings.Fixed.Index (Payload, Justification_Tag);
                  begin
                     if Payload'Length > Prefix'Length and then
                       Payload (Payload'First .. Payload'First + Prefix'Length - 1) = Prefix and then
                       Justification_At > Payload'First + Prefix'Length
                     then
                        declare
                           Target : constant String := Ada.Strings.Fixed.Trim
                             (Payload (Payload'First + Prefix'Length .. Justification_At - 1), Ada.Strings.Both);
                           Justification : constant String := Ada.Strings.Fixed.Trim
                             (Payload (Justification_At + Justification_Tag'Length .. Payload'Last), Ada.Strings.Both);
                        begin
                           if Target = Wanted and then Justification'Length > 0 then
                              return
                                (Valid => True, Target => To_Unbounded_String (Target),
                                 Justification => To_Unbounded_String (Justification));
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;
            exit when Stop > Data'Last;
            Cursor := Stop + 1;
         end;
      end loop;
      return (others => <>);
   end Find_Review_Waiver;

   procedure Scan_Source
     (Root            : String;
      Files           : Text_Vectors.Vector;
      Count_Generated : Boolean;
      Policy          : Ada_Quality.Policy.Quality_Policy;
      Result          : out Source_Analysis) is separate;

   function Analyze_Source
     (Root   : String;
      Policy : Ada_Quality.Policy.Quality_Policy) return Source_Analysis
   is
      Result : Source_Analysis;
   begin
      Scan_Source (Root, Source_Files (Root), True, Policy, Result);
      return Result;
   end Analyze_Source;

   function Safe_Changed_Relative (Path : String) return Boolean is
      Start : Natural := Path'First;
   begin
      if Path = "" or else Path (Path'First) in '/' | '\' then
         return False;
      end if;
      for Index in Path'Range loop
         if Path (Index) in '/' | '\' then
            if Path (Start .. Index - 1) in "" | "." | ".." then
               return False;
            end if;
            Start := Index + 1;
         end if;
      end loop;
      return Start <= Path'Last and then Path (Start .. Path'Last) not in "." | "..";
   end Safe_Changed_Relative;

   procedure Validate_Changed_Components
     (Canonical_Root : String;
      Relative_Path  : String)
   is
      Current : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String (Canonical_Root);
      Start   : Natural := Relative_Path'First;
   begin
      for Index in Relative_Path'Range loop
         if Relative_Path (Index) in '/' | '\' then
            Append (Current, "/" & Relative_Path (Start .. Index - 1));
            if Project_Tools.Links.Is_Link (To_String (Current)) then
               raise Constraint_Error with "changed source path traverses a symbolic link";
            end if;
            Start := Index + 1;
         end if;
      end loop;
      Append (Current, "/" & Relative_Path (Start .. Relative_Path'Last));
      if Project_Tools.Links.Is_Link (To_String (Current)) then
         raise Constraint_Error with "changed source path is a symbolic link";
      end if;
   end Validate_Changed_Components;

   function Validated_Changed_Source
     (Canonical_Root : String;
      Relative_Path  : String) return String
   is
      Path : constant String := Ada.Directories.Full_Name (Canonical_Root & "/" & Relative_Path);
      Rel  : constant String := "/" & Relative_Path;
   begin
      if Path'Length <= Canonical_Root'Length
        or else Path (Path'First .. Path'First + Canonical_Root'Length - 1) /= Canonical_Root
        or else Path (Path'First + Canonical_Root'Length) not in '/' | '\'
      then
         raise Constraint_Error with "changed source path escapes the project root";
      elsif not Project_Tools.Files.File_Exists (Path) then
         raise Constraint_Error with "changed source path is not an ordinary file";
      elsif not (Has_Suffix (Lower (Path), ".ads") or else Has_Suffix (Lower (Path), ".adb")) then
         raise Constraint_Error with "changed source path is not Ada source";
      elsif Contains (Rel, "/config/")
        and then (Contains (Ada.Directories.Simple_Name (Path), "_config.ads")
                  or else Contains (Ada.Directories.Simple_Name (Path), "_config.adb"))
      then
         raise Constraint_Error with "generated configuration source is not change-scoped input";
      end if;
      return Path;
   end Validated_Changed_Source;

   function Changed_Source_Files
     (Root    : String;
      Changed : Project_Tools.Files.Path_List) return Text_Vectors.Vector
   is
      Canonical_Root : constant String := Ada.Directories.Full_Name (Root);
      Result         : Text_Vectors.Vector;
   begin
      if Changed'Length > Maximum_Project_Files then
         raise Constraint_Error with "changed source set exceeds maximum file count";
      end if;
      for Value of Changed loop
         declare
            Relative_Path : constant String := To_String (Value);
         begin
            if not Safe_Changed_Relative (Relative_Path) then
               raise Constraint_Error with "changed source path is not project-relative";
            end if;
            Validate_Changed_Components (Canonical_Root, Relative_Path);
            declare
               Path : constant String := Validated_Changed_Source (Canonical_Root, Relative_Path);
            begin
               if not Result.Contains (To_Unbounded_String (Path)) then
                  Result.Append (To_Unbounded_String (Path));
               end if;
            end;
         end;
      end loop;
      Text_Sorting.Sort (Result);
      return Result;
   end Changed_Source_Files;

   function Analyze_Changed_Sources
     (Root    : String;
      Changed : Project_Tools.Files.Path_List;
      Policy  : Ada_Quality.Policy.Quality_Policy) return Source_Analysis
   is
      Canonical_Root : constant String := Ada.Directories.Full_Name (Root);
      Files          : constant Text_Vectors.Vector := Changed_Source_Files (Canonical_Root, Changed);
      Result         : Source_Analysis;
   begin
      Scan_Source (Canonical_Root, Files, False, Policy, Result);
      return Result;
   end Analyze_Changed_Sources;

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

   function Inspected_Output_Result
     (Indicator       : Indicator_Id;
      Run             : Ada_Quality.Execution.Run_Result;
      Requirement_Met : Boolean;
      Success          : String;
      Violation        : String) return Indicator_Result
   is
      Evidence : constant String := To_String (Run.Command) & " exit=" & Integer'Image (Run.Exit_Code) &
        (if Run.Truncated then " output-truncated" else "");
   begin
      if Run.Status = Ada_Quality.Execution.Completed and then Run.Exit_Code = 0 and then Run.Truncated then
         return Blocked_Result
           (Indicator, "tool diagnostics were truncated before the requirement could be evaluated", Evidence);
      elsif Run.Status /= Ada_Quality.Execution.Completed or else Run.Exit_Code /= 0 then
         return Tool_Result (Indicator, Run, Success, Violation);
      elsif Requirement_Met then
         return Passed (Indicator, Success, Evidence);
      else
         return Violated (Indicator, Violation, Evidence);
      end if;
   end Inspected_Output_Result;

   function Toolchain_Identified
     (Run : Ada_Quality.Execution.Run_Result) return Boolean is
     (Run.Status = Ada_Quality.Execution.Completed and then
      Run.Exit_Code = 0 and then not Run.Truncated and then
      Contains (To_String (Run.Output), "GNAT"));

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
      Policy     : Ada_Quality.Policy.Quality_Policy;
      Coverage_Evidence_Enabled : Boolean := True) return Assessment is separate;
end Ada_Quality.Checks;
