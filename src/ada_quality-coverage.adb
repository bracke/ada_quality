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

      procedure Include (Path : String; Is_Body : Boolean) is
         Stem  : constant String := Stem_Of (Path);
         Found : Boolean := False;
      begin
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
                  Spec_Path => (if Is_Body then Null_Unbounded_String else To_Unbounded_String (Path))));
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
end Ada_Quality.Coverage;
