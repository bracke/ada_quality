separate (Ada_Quality.Checks)
--  AQ-WAIVER: SRC-03 target=canonical owner=core expires=2099-12-31 justification=lexical-helpers-share-one-source-pass
procedure Scan_Source
  (Root            : String;
   Files           : Text_Vectors.Vector;
   Count_Generated : Boolean;
   Policy          : Ada_Quality.Policy.Quality_Policy;
   Result          : out Source_Analysis)
is
   Total_Bytes : Ada.Directories.File_Size := 0;
begin
   Result := (Findings => <>, others => 0);
   if Files.Length > Ada.Containers.Count_Type (Maximum_Project_Files) then
      raise Constraint_Error with "source analysis exceeds maximum file count";
   end if;
   for Path_Value of Files loop
      declare
         Path : constant String := To_String (Path_Value);
         Size : constant Ada.Directories.File_Size := Ada.Directories.Size (Path);
      begin
         if Size > Ada.Directories.File_Size (Maximum_File_Bytes) then
            raise Constraint_Error with "source file exceeds maximum size: " & Path;
         elsif Total_Bytes >
           Ada.Directories.File_Size (Maximum_Fingerprint_Bytes) - Size
         then
            raise Constraint_Error with "source analysis exceeds aggregate byte limit";
         end if;
         Total_Bytes := Total_Bytes + Size;
      end;
   end loop;
   if Count_Generated then
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
   end if;
   for Path_Value of Files loop
      declare
         Path       : constant String := To_String (Path_Value);
         Name       : constant String := Ada.Directories.Simple_Name (Path);
         Rel_Path   : constant String := "/" & Relative (Root, Path);
         Is_Test    : constant Boolean :=
           Contains (Rel_Path, "/tests/") or else Contains (Rel_Path, "/test/");
         Data       : constant String := Project_Tools.Files.Read_Raw_File (Path);
         Start      : Positive := 1;
         File_Lines : Natural := 0;
         Complexity : Natural := 1;
         File_Max_Complexity : Natural := 1;
         Current_Subprogram : Ada.Strings.Unbounded.Unbounded_String :=
           To_Unbounded_String ("file-elaboration");
         File_Max_Subprogram : Ada.Strings.Unbounded.Unbounded_String := Current_Subprogram;
         Has_Docs   : Boolean := False;
         Pending_Doc : Boolean := False;
         Unit_Name_Checked : Boolean := False;
         Subunit_Parent    : Ada.Strings.Unbounded.Unbounded_String;
         Is_Spec     : constant Boolean :=
           Name'Length >= 4 and then Name (Name'Last - 3 .. Name'Last) = ".ads";

         procedure Note
           (Indicator : Indicator_Id;
            Rule, Message : String;
            Line : Natural := 0;
            Level : Severity := Medium;
            Context : String := "") is
            Rel : constant String := Relative (Root, Path);
            Candidate : constant String :=
              Finding_Fingerprint (Indicator, Rule, Rel, Message, Context);
            Occurrences : Natural := 0;
            Key : Ada.Strings.Unbounded.Unbounded_String;
         begin
            for Existing of Result.Findings loop
               if To_String (Existing.Fingerprint) = Candidate or else
                 Starts_With (To_String (Existing.Fingerprint), Candidate & "#")
               then
                  Occurrences := Occurrences + 1;
               end if;
            end loop;
            Key := To_Unbounded_String
              (Candidate & (if Occurrences = 0 then "" else
                 "#" & Ada.Strings.Fixed.Trim (Natural'Image (Occurrences + 1), Ada.Strings.Both)));
            Result.Findings.Append
              (Finding'(Indicator => Indicator, Rule => To_Unbounded_String (Rule), Level => Level,
               Message => To_Unbounded_String (Message), Relative_Path => To_Unbounded_String (Rel),
               Line => Line, Fingerprint => Key));
         end Note;

         procedure Record_Complexity is
         begin
            if Complexity > File_Max_Complexity then
               File_Max_Complexity := Complexity;
               File_Max_Subprogram := Current_Subprogram;
            end if;
         end Record_Complexity;

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
                     --  A subunit's file is named after its parent followed by the subunit name.
                     if To_String (Words (First)) = "separate" then
                        for K in First + 1 .. Words.Last_Index loop
                           exit when To_String (Words (K)) in "package" | "procedure" | "function";
                           Append (Subunit_Parent, To_String (Words (K)));
                        end loop;
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
                           Unit_Name : Ada.Strings.Unbounded.Unbounded_String := Subunit_Parent;
                           --  The unit name ends before a parameter list.
                           Paren     : constant Natural := Ada.Strings.Fixed.Index (Clean, "(");
                           Name_Words : Natural := Natural (Words.Length);
                        begin
                           if Paren > 0 then
                              Name_Words := 0;
                              for J in Clean'First .. Paren - 1 loop
                                 if Clean (J) in 'a' .. 'z' | '0' .. '9' | '_' and then
                                   (J = Clean'First or else Clean (J - 1) not in 'a' .. 'z' | '0' .. '9' | '_')
                                 then
                                    Name_Words := Name_Words + 1;
                                 end if;
                              end loop;
                           end if;
                           for K in First .. Words.Last_Index loop
                              exit when K - Words.First_Index >= Name_Words;
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
                        Record_Complexity;
                        Complexity := 1;
                        if Following'Length > 0 then
                           Current_Subprogram := To_Unbounded_String (Following);
                        end if;
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
               Note (SRC_01, "line-length", "source line exceeds 120 columns", File_Lines,
                 Context => Line);
            end if;
            if Contains (Line, Character'Val (9) & "") or else
              (Line'Length > 0 and then Line (Line'Last) = ' ')
            then
               Result.Hygiene_Errors := Result.Hygiene_Errors + 1;
               Note (SRC_04, "source-hygiene", "tab or trailing whitespace", File_Lines,
                 Context => Line);
            end if;
            if Decisions > 0 then
               Complexity := Complexity + Decisions;
               Record_Complexity;
            end if;
            if Contains (Clean, "register_routine") or else Contains (Clean, ".add_test") then
               Result.Test_Registrations := Result.Test_Registrations + 1;
            end if;
            if Matches (Secret_Pattern, Clean) then
               Result.Secret_Matches := Result.Secret_Matches + 1;
               Note (SEC_01, "embedded-secret", "possible embedded credential assignment", File_Lines, High,
                 Context => Line);
            end if;
            if Ada_Quality.Source_Safety.Contains_Shell_Invocation (Line) then
               Result.Unsafe_Processes := Result.Unsafe_Processes + 1;
               Note (SEC_02, "shell-execution", "shell-oriented process execution pattern", File_Lines, High,
                 Context => Line);
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
         if File_Lines > Policy.Maximum_Source_Lines then
            declare
               Size_Waiver : constant Review_Waiver :=
                 Find_Review_Waiver (Data, "SRC-06", "file");
            begin
            if Size_Waiver.Valid then
               Result.Review_Waivers := Result.Review_Waivers + 1;
               Note
                 (SRC_06, "review-waiver",
                  "SRC-06 target=file owner=" & To_String (Size_Waiver.Owner) & " expires=" &
                    To_String (Size_Waiver.Expires) & " justification=" &
                    To_String (Size_Waiver.Justification), Level => Low);
            else
               Result.Oversized_Files := Result.Oversized_Files + 1;
               if Size_Waiver.Found then
                  Note
                    (SRC_06, (if Size_Waiver.Expired then "expired-waiver" else "invalid-waiver"),
                     "SRC-06 target=file waiver is " &
                       (if Size_Waiver.Expired then "expired" else "malformed"), Level => Low);
               end if;
               Note (SRC_06, "source-size", "source file exceeds configured line limit");
            end if;
            end;
         end if;
         Record_Complexity;
         Result.Maximum_Complexity := Natural'Max (Result.Maximum_Complexity, File_Max_Complexity);
         if File_Max_Complexity > Policy.Maximum_Complexity then
            declare
               Complexity_Waiver : constant Review_Waiver :=
                 Find_Review_Waiver
                   (Data, "SRC-03", To_String (File_Max_Subprogram));
            begin
            if Complexity_Waiver.Valid then
               Result.Review_Waivers := Result.Review_Waivers + 1;
               Note
                 (SRC_03, "review-waiver",
                  "SRC-03 target=" & To_String (File_Max_Subprogram) & " owner=" &
                    To_String (Complexity_Waiver.Owner) & " expires=" &
                    To_String (Complexity_Waiver.Expires) & " justification=" &
                    To_String (Complexity_Waiver.Justification), Level => Low);
            else
               Result.Complexity_Violations := Result.Complexity_Violations + 1;
               if Complexity_Waiver.Found then
                  Note
                    (SRC_03, (if Complexity_Waiver.Expired then "expired-waiver" else "invalid-waiver"),
                     "SRC-03 target=" & To_String (File_Max_Subprogram) & " waiver is " &
                       (if Complexity_Waiver.Expired then "expired" else "malformed"), Level => Low);
               end if;
               Note
                 (SRC_03, "complexity",
                  "source complexity exceeds configured limit in " & To_String (File_Max_Subprogram));
            end if;
            end;
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
                  Note (SRC_05, "broad-handler", "broad exception handler", Line_Number,
                    Context => Source_Line);
               end if;
            end Visit_Handler;
         begin
            Project_Tools.Ada_Source.Scan_Broad_Exception_Handlers (Path, Visit_Handler'Access);
         end;
      end;
   end loop;
end Scan_Source;
