with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with Project_Tools.Files;

package body Ada_Quality.Coverage is
   function Decimal_Digits (Text : String) return Boolean is
   begin
      if Text'Length = 0 then return False; end if;
      for Value of Text loop
         if Value not in '0' .. '9' then return False; end if;
      end loop;
      return True;
   end Decimal_Digits;

   function Valid_Percentage (Text : String) return Boolean is
      Dot_At : constant Natural := Ada.Strings.Fixed.Index (Text, ".");
   begin
      if Dot_At = 0 then return Decimal_Digits (Text); end if;
      return Dot_At > Text'First and then Dot_At < Text'Last and then
        Ada.Strings.Fixed.Index (Text, ".", From => Dot_At + 1) = 0 and then
        Decimal_Digits (Text (Text'First .. Dot_At - 1)) and then
        Decimal_Digits (Text (Dot_At + 1 .. Text'Last));
   end Valid_Percentage;

   function Valid_Lines_Summary (Line : String) return Boolean is
      Prefix       : constant String := "Lines executed:";
      Separator    : constant String := "% of ";
      Separator_At : Natural;
      Total_First  : Natural;
      Total_Last   : Natural := Line'Last;
   begin
      if Line'Length < Prefix'Length or else
        Line (Line'First .. Line'First + Prefix'Length - 1) /= Prefix
      then
         return False;
      end if;
      Separator_At := Ada.Strings.Fixed.Index
        (Line, Separator, From => Line'First + Prefix'Length);
      if Separator_At = 0 or else Separator_At = Line'First + Prefix'Length then
         return False;
      end if;
      Total_First := Separator_At + Separator'Length;
      if Total_Last >= Total_First and then Line (Total_Last) = ASCII.CR then
         Total_Last := Total_Last - 1;
      end if;
      if Total_Last < Total_First then return False; end if;
      return Valid_Percentage
        (Line (Line'First + Prefix'Length .. Separator_At - 1)) and then
        Decimal_Digits (Line (Total_First .. Total_Last));
   end Valid_Lines_Summary;

   use Ada.Strings.Unbounded;

   function Stem_Of (Path : String) return String is
      Name : constant String := Ada.Directories.Simple_Name (Path);
   begin
      return Name (Name'First .. Name'Last - 4);
   end Stem_Of;

   function Production_Units (Root : String) return Production_Unit_Vectors.Vector is
      Result : Production_Unit_Vectors.Vector;

      function Subunit_Parent_Stem (Path : String) return String is
         Text   : constant String := Project_Tools.Files.Read_Raw_File (Path);
         Cursor : Natural := Text'First;

         function Identifier_Start (Value : Character) return Boolean is
           (Value in 'a' .. 'z' | 'A' .. 'Z');

         function Identifier_Part (Value : Character) return Boolean is
           (Identifier_Start (Value) or else Value in '0' .. '9' or else Value = '_');

         procedure Skip_Trivia is
         begin
            loop
               while Cursor <= Text'Last and then
                 Text (Cursor) in ' ' | ASCII.HT | ASCII.CR | ASCII.LF
               loop
                  Cursor := Cursor + 1;
               end loop;
               exit when Cursor >= Text'Last or else Text (Cursor .. Cursor + 1) /= "--";
               Cursor := Cursor + 2;
               while Cursor <= Text'Last and then Text (Cursor) /= ASCII.LF loop
                  Cursor := Cursor + 1;
               end loop;
            end loop;
         end Skip_Trivia;

         function Next_Identifier return String is
            First : constant Natural := Cursor;
         begin
            while Cursor <= Text'Last and then Identifier_Part (Text (Cursor)) loop
               Cursor := Cursor + 1;
            end loop;
            return Ada.Characters.Handling.To_Lower (Text (First .. Cursor - 1));
         end Next_Identifier;

         procedure Skip_String is
         begin
            Cursor := Cursor + 1;
            while Cursor <= Text'Last loop
               if Text (Cursor) /= '"' then
                  Cursor := Cursor + 1;
               elsif Cursor < Text'Last and then Text (Cursor + 1) = '"' then
                  Cursor := Cursor + 2;
               else
                  Cursor := Cursor + 1;
                  return;
               end if;
            end loop;
         end Skip_String;

         function Parent_Name return String is
            Name : Unbounded_String;
         begin
            loop
               Skip_Trivia;
               if Cursor > Text'Last or else not Identifier_Start (Text (Cursor)) then return ""; end if;
               Append (Name, Next_Identifier);
               Skip_Trivia;
               if Cursor > Text'Last then
                  return "";
               elsif Text (Cursor) = ')' then
                  Cursor := Cursor + 1;
                  return To_String (Name);
               elsif Text (Cursor) = '.' then
                  Append (Name, '-');
                  Cursor := Cursor + 1;
               else
                  return "";
               end if;
            end loop;
         end Parent_Name;
      begin
         while Cursor <= Text'Last loop
            Skip_Trivia;
            exit when Cursor > Text'Last;
            if Text (Cursor) = '"' then
               Skip_String;
            elsif Identifier_Start (Text (Cursor)) then
               if Next_Identifier = "separate" then
                  Skip_Trivia;
                  if Cursor <= Text'Last and then Text (Cursor) = '(' then
                     Cursor := Cursor + 1;
                     return Parent_Name;
                  end if;
               end if;
            else
               Cursor := Cursor + 1;
            end if;
         end loop;
         return "";
      end Subunit_Parent_Stem;

      procedure Include_Subunit (Stem, Path : String) is
      begin
         for Index in Result.First_Index .. Result.Last_Index loop
            if To_String (Result (Index).Stem) = Stem then
               declare
                  Item : Production_Unit := Result (Index);
               begin
                  Item.Subunit_Paths.Append (To_Unbounded_String (Path));
                  Result.Replace_Element (Index, Item);
                  return;
               end;
            end if;
         end loop;
         Result.Append
           (Production_Unit'
              (Stem          => To_Unbounded_String (Stem),
               Body_Path     => Null_Unbounded_String,
               Spec_Path     => Null_Unbounded_String,
               Subunit_Paths => Source_Path_Vectors.Empty_Vector));
         Result (Result.Last_Index).Subunit_Paths.Append (To_Unbounded_String (Path));
      end Include_Subunit;

      procedure Include (Path : String; Is_Body : Boolean) is
         Stem  : constant String := Stem_Of (Path);
         Found : Boolean := False;
      begin
         if Is_Body then
            declare
               Parent_Stem : constant String := Subunit_Parent_Stem (Path);
            begin
               if Parent_Stem = "ada_quality_coverage" then
                  return;
               elsif Parent_Stem'Length > 0 then
                  Include_Subunit (Parent_Stem, Path);
                  return;
               end if;
            end;
         end if;
         if Stem = "ada_quality_coverage" then
            return;
         end if;
         for Index in Result.First_Index .. Result.Last_Index loop
            if To_String (Result (Index).Stem) = Stem then
               declare
                  Item : Production_Unit := Result (Index);
               begin
                  if Is_Body then
                     if Length (Item.Body_Path) > 0 and then To_String (Item.Body_Path) /= Path then
                        raise Constraint_Error with "duplicate production body stem: " & Stem;
                     end if;
                     Item.Body_Path := To_Unbounded_String (Path);
                  else
                     if Length (Item.Spec_Path) > 0 and then To_String (Item.Spec_Path) /= Path then
                        raise Constraint_Error with "duplicate production specification stem: " & Stem;
                     end if;
                     Item.Spec_Path := To_Unbounded_String (Path);
                  end if;
                  Result.Replace_Element (Index, Item);
                  Found := True;
                  exit;
               end;
            end if;
         end loop;
         if not Found then
            Result.Append
              (Production_Unit'
                 (Stem => To_Unbounded_String (Stem),
                  Body_Path => (if Is_Body then To_Unbounded_String (Path) else Null_Unbounded_String),
                  Spec_Path => (if Is_Body then Null_Unbounded_String else To_Unbounded_String (Path)),
                  Subunit_Paths => Source_Path_Vectors.Empty_Vector));
         end if;
      end Include;

      function Earlier (Left, Right : Production_Unit) return Boolean is
        (Left.Stem < Right.Stem);

      package Sorting is new Production_Unit_Vectors.Generic_Sorting ("<" => Earlier);
      Source_Root : constant String := Project_Tools.Files.Join (Root, "src");
   begin
      if not Project_Tools.Files.Directory_Exists (Source_Root) then return Result; end if;
      for Path of Project_Tools.Files.List_Tree (Source_Root, "*.adb") loop
         Include (To_String (Path), Is_Body => True);
      end loop;
      for Path of Project_Tools.Files.List_Tree (Source_Root, "*.ads") loop
         Include (To_String (Path), Is_Body => False);
      end loop;
      Sorting.Sort (Result);
      return Result;
   end Production_Units;

   function Missing_Objects
     (Units      : Production_Unit_Vectors.Vector;
      Object_Dir : String) return Production_Unit_Vectors.Vector
   is
      Result : Production_Unit_Vectors.Vector;
   begin
      for Item of Units loop
         if not Project_Tools.Files.File_Exists
           (Project_Tools.Files.Join (Object_Dir, To_String (Item.Stem) & ".gcno"))
         then
            Result.Append (Item);
         end if;
      end loop;
      return Result;
   end Missing_Objects;

   function Has_Source_Record (Output, Source : String) return Boolean is
      Marker : constant String := "File '" & Source & "'";
      Start  : Positive := Output'First;
      Matching_Record : Boolean := False;
   begin
      if Output'Length = 0 or else Source'Length = 0 then return False; end if;
      while Start <= Output'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index (Output, [ASCII.LF], From => Start);
         begin
            if Stop = 0 then Stop := Output'Last + 1; end if;
            declare
               Line : constant String := Output (Start .. Stop - 1);
            begin
               if Line'Length >= 6 and then Line (Line'First .. Line'First + 5) = "File '" then
                  Matching_Record := Line = Marker;
               elsif Matching_Record and then
                 (Valid_Lines_Summary (Line) or else Line = "No executable lines")
               then
                  return True;
               end if;
            end;
            exit when Stop > Output'Last;
            Start := Stop + 1;
         end;
      end loop;
      return False;
   end Has_Source_Record;

   function Has_Complete_Source_Records
     (Output, Notes : String; Unit : Production_Unit) return Boolean
   is
      function Complete (Source : Unbounded_String) return Boolean is
         Path : constant String := To_String (Source);
      begin
         if Length (Source) = 0 then
            return True;
         end if;
         declare
            Header : constant String := "File '" & Path & "'";
            Has_Note : constant Boolean :=
              Ada.Strings.Fixed.Index (Notes, Path) > 0 or else
              Ada.Strings.Fixed.Index (Notes, Ada.Directories.Simple_Name (Path)) > 0;
         begin
            if Has_Source_Record (Output, Path) then
               return True;
            elsif Ada.Strings.Fixed.Index (Output, Header) > 0 or else Has_Note then
               return False;
            else
               return True;
            end if;
         end;
      end Complete;
   begin
      if Notes'Length = 0 or else not Complete (Unit.Body_Path) or else
        not Complete (Unit.Spec_Path)
      then
         return False;
      end if;
      for Path of Unit.Subunit_Paths loop
         if not Complete (Path) then return False; end if;
      end loop;
      return True;
   end Has_Complete_Source_Records;
end Ada_Quality.Coverage;
