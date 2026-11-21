with Ada_Quality.JSON_Reports;
with Ada_Quality.Project_Inventory;
with Ada_Quality.Resource_Limits;
with Ada_Quality.Storage.Registry;
with Project_Tools.Links;

separate (Ada_Quality.CLI)
function Run_Project_Discover
  (Store : in out Ada_Quality.Storage.Store;
   Root : String;
   Add, Remove_Missing : Boolean) return Natural
is
   Found : Text_Vectors.Vector;
   Seen_Entries : Natural := 0;
   Results : Ada_Quality.Command_Models.Discovery_Vectors.Vector;
   Format : constant String :=
     Selected_Output_Format
       ("text", "text|json", "project discover format requires text or json");

   function Less
     (Left, Right : Ada.Strings.Unbounded.Unbounded_String) return Boolean is
     (To_String (Left) < To_String (Right));
   package Sorting is new Text_Vectors.Generic_Sorting ("<" => Less);

   procedure Walk (Directory : String; Depth : Positive);
   procedure Search_Directory (Directory : String; Depth : Positive);

   function Is_Project (Directory : String) return Boolean is
     (Ada.Directories.Exists (Directory & "/alire.toml") and then
      Ada.Directories.Kind (Directory & "/alire.toml") = Ada.Directories.Ordinary_File);

   function Should_Descend
     (Item : Ada.Directories.Directory_Entry_Type; Name, Path : String) return Boolean is
     (not Project_Tools.Links.Is_Link (Path) and then
      Ada.Directories.Kind (Item) = Ada.Directories.Directory and then
      not Ada_Quality.Project_Inventory.Is_Excluded_Source_Directory (Name));

   procedure Visit
     (Item : Ada.Directories.Directory_Entry_Type; Depth : Positive)
   is
      Name : constant String := Ada.Directories.Simple_Name (Item);
      Path : constant String := Ada.Directories.Full_Name (Item);
   begin
      if Name in "." | ".." then
         return;
      end if;
      if Seen_Entries = Ada_Quality.Resource_Limits.Maximum_Project_Files then
         raise Usage_Error with "project discovery exceeds the entry limit";
      end if;
      Seen_Entries := Seen_Entries + 1;
      if Should_Descend (Item, Name, Path) then
         Walk (Path, Depth + 1);
      end if;
   end Visit;

   procedure Search_Directory (Directory : String; Depth : Positive) is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Opened : Boolean := False;
   begin
      Ada.Directories.Start_Search (Search, Directory, "");
      Opened := True;
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Visit (Item, Depth);
      end loop;
      Ada.Directories.End_Search (Search);
      Opened := False;
   exception
      when others =>
         if Opened then Ada.Directories.End_Search (Search); end if;
         raise;
   end Search_Directory;

   procedure Walk (Directory : String; Depth : Positive) is
   begin
      if Depth > Ada_Quality.Resource_Limits.Maximum_Tree_Depth then
         raise Usage_Error with "project discovery exceeds the directory-depth limit";
      end if;
      if Is_Project (Directory) then
         Found.Append (To_Unbounded_String (Ada.Directories.Full_Name (Directory)));
      end if;
      Search_Directory (Directory, Depth);
   end Walk;

   Registered : constant Ada_Quality.Storage.Project_Vectors.Vector :=
     Ada_Quality.Storage.Registry.Projects (Store);

   function Existing_Project (Name : String) return Natural is
   begin
      for Project of Registered loop
         if To_String (Project.Path) = Name and then not Project.Removed then
            return Project.Id;
         end if;
      end loop;
      return 0;
   end Existing_Project;

   procedure Record_Found_Projects is
   begin
   for Path of Found loop
      declare
         Name : constant String := To_String (Path);
         Existing : constant Natural := Existing_Project (Name);
      begin
         if Existing > 0 then
            Results.Append
              (Ada_Quality.Command_Models.Discovery_Item'
                 (Path => Path, Project_Id => Existing,
                  Status => Ada_Quality.Command_Models.Already_Registered));
         elsif Add then
            declare
               Id : constant Positive :=
                 Ada_Quality.Storage.Registry.Add_Project (Store, Name);
            begin
               Results.Append
                 (Ada_Quality.Command_Models.Discovery_Item'
                    (Path => Path, Project_Id => Id, Status => Ada_Quality.Command_Models.Added));
            end;
         else
            Results.Append
              (Ada_Quality.Command_Models.Discovery_Item'
                 (Path => Path, Project_Id => 0, Status => Ada_Quality.Command_Models.Discovered));
         end if;
      end;
   end loop;
   end Record_Found_Projects;

   function Is_Present (Name : String) return Boolean is
   begin
      for Path of Found loop
         if To_String (Path) = Name then
            return True;
         end if;
      end loop;
      return False;
   end Is_Present;

   procedure Record_Missing_Projects is
      Canonical_Root : constant String := Ada.Directories.Full_Name (Root);
   begin
      for Project of Registered loop
         declare
            Name : constant String := To_String (Project.Path);
            Under_Root : constant Boolean :=
              Name = Canonical_Root or else
              (Name'Length > Canonical_Root'Length and then
               Name (Name'First .. Name'First + Canonical_Root'Length - 1) = Canonical_Root and then
               Name (Name'First + Canonical_Root'Length) = '/');
         begin
            if Under_Root and then not Project.Removed and then not Is_Present (Name) then
               if Remove_Missing then
                  Ada_Quality.Storage.Registry.Remove_Project
                    (Store, Project.Id);
               end if;
               Results.Append
                 (Ada_Quality.Command_Models.Discovery_Item'
                    (Path => Project.Path, Project_Id => Project.Id,
                     Status => (if Remove_Missing then Ada_Quality.Command_Models.Removed
                                else Ada_Quality.Command_Models.Missing)));
            end if;
         end;
      end loop;
   end Record_Missing_Projects;

   procedure Emit_Result is
   begin
      if Format = "json" then
         Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
         Emit_Document
           (Ada_Quality.JSON_Reports.Render_Discovery (Results, Pretty => True));
      else
         declare
            Output : Ada.Strings.Unbounded.Unbounded_String;
         begin
            for Item of Results loop
               Append
                 (Output, (case Item.Status is
                     when Ada_Quality.Command_Models.Already_Registered =>
                       "registered" & Natural'Image (Item.Project_Id),
                     when Ada_Quality.Command_Models.Added =>
                       "added" & Natural'Image (Item.Project_Id),
                     when Ada_Quality.Command_Models.Discovered => "found",
                     when Ada_Quality.Command_Models.Missing =>
                       "missing" & Natural'Image (Item.Project_Id),
                     when Ada_Quality.Command_Models.Removed =>
                       "removed" & Natural'Image (Item.Project_Id)) &
                  " " & To_String (Item.Path) & ASCII.LF);
            end loop;
            Emit_Document (To_String (Output));
         end;
      end if;
   end Emit_Result;
begin
   if Root'Length = 0 or else not Ada.Directories.Exists (Root) or else
     Ada.Directories.Kind (Root) /= Ada.Directories.Directory or else Project_Tools.Links.Is_Link (Root)
   then
      raise Usage_Error with "project discover requires an existing nonsymlink directory";
   end if;
   Walk (Ada.Directories.Full_Name (Root), 1);
   Sorting.Sort (Found);
   Record_Found_Projects;
   Record_Missing_Projects;
   Emit_Result;
   return 0;
end Run_Project_Discover;
