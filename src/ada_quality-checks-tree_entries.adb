separate (Ada_Quality.Checks)
--  AQ-WAIVER: SRC-03 target=walk owner=core expires=2027-11-21 justification=bounded-recursive-project-tree-walk
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
               if Result.Length > Ada.Containers.Count_Type (Maximum_Project_Files) then
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
