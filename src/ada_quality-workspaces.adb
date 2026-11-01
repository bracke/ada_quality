with Ada.Directories;
with Ada.Containers.Vectors;
with Ada.Characters.Latin_1;
with Ada.Strings.Fixed;
with Project_Tools.Files;
with Project_Tools.Links;

package body Ada_Quality.Workspaces is
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

      function Without_Comments (Text : String) return String is
         Result    : String := Text;
         In_String : Boolean := False;
         Quote     : Character := Character'Val (0);
         Escaped   : Boolean := False;
         In_Comment : Boolean := False;
      begin
         for J in Text'Range loop
            if Text (J) = Ada.Characters.Latin_1.LF then
               In_Comment := False;
               In_String := False;
               Escaped := False;
            elsif In_Comment then
               Result (J) := ' ';
            elsif not In_String and then Text (J) = '#' then
               In_Comment := True;
               Result (J) := ' ';
            elsif In_String then
               if Text (J) = Quote and then not Escaped then In_String := False; end if;
               Escaped := Text (J) = '\' and then not Escaped;
            elsif Text (J) in ''' | '"' then
               In_String := True;
               Quote := Text (J);
            end if;
         end loop;
         return Result;
      end Without_Comments;

      procedure Copy_Crate (From, Into : String);

      procedure Copy_Pins (Canonical, Into, Manifest : String) is
         Data   : constant String := Without_Comments (Project_Tools.Files.Read_Raw_File (Manifest));
         Cursor : Natural := Data'First;
      begin
         while Cursor <= Data'Last loop
            declare
               Marker : constant Natural := Ada.Strings.Fixed.Index (Data, "path =", From => Cursor);
            begin
               exit when Marker = 0;
               declare
                  Equal : constant Natural := Ada.Strings.Fixed.Index (Data, "=", From => Marker + 4);
                  Quote : constant Natural :=
                    (if Equal = 0 then 0 else Ada.Strings.Fixed.Index (Data, """", From => Equal + 1));
                  Last_Quote : constant Natural :=
                    (if Quote = 0 then 0 else Ada.Strings.Fixed.Index (Data, """", From => Quote + 1));
               begin
                  if Equal = 0 or else Quote = 0 or else Last_Quote = 0 then exit; end if;
                  declare
                     Relative : constant String := Data (Quote + 1 .. Last_Quote - 1);
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
                  end;
                  Cursor := Last_Quote + 1;
               end;
            end;
         end loop;
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
