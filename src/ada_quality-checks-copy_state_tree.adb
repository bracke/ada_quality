separate (Ada_Quality.Checks)
--  AQ-WAIVER: SRC-03 target=copy_directory owner=core expires=2099-12-31 justification=bounded-recursive-baseline-copy
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
