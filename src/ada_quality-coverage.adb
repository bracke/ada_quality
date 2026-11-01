with Ada.Directories;
with Project_Tools.Files;

package body Ada_Quality.Coverage is
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
end Ada_Quality.Coverage;
