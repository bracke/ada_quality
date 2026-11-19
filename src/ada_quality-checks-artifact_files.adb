separate (Ada_Quality.Checks)
--  AQ-WAIVER: SRC-03 target=walk owner=core expires=2099-12-31 justification=bounded-recursive-artifact-inventory
   function Artifact_Files (Root : String) return Text_Vectors.Vector is
      Result : Text_Vectors.Vector;

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
               In_Artifact : constant Boolean := Inside_Artifact or else
                 Ada_Quality.Project_Inventory.Is_Artifact_Directory (Name);
            begin
               if Name in "." | ".." or else
                 (not Inside_Artifact and then
                  Ada_Quality.Project_Inventory.Is_Excluded_Source_Directory (Name) and then
                  not Ada_Quality.Project_Inventory.Is_Artifact_Directory (Name))
               then
                  null;
               elsif Project_Tools.Links.Is_Link (Path) then
                  if In_Artifact then Result.Append (To_Unbounded_String (Path)); end if;
               elsif Ada.Directories.Kind (Item) = Ada.Directories.Directory then
                  Walk (Path, In_Artifact, Depth + 1);
               elsif In_Artifact and then Ada.Directories.Kind (Item) = Ada.Directories.Ordinary_File then
                  Result.Append (To_Unbounded_String (Path));
               end if;
               if Result.Length > Ada.Containers.Count_Type (Maximum_Project_Files) then
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
