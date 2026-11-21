with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada_Quality.Bounded_Files;
with Ada_Quality.Manifests;
with Ada_Quality.Persistence;
with Ada_Quality.Resource_Limits;
with Database.Predicates;
with Database.Status;
with Database.Transactions;
with Project_Tools.Links;

package body Ada_Quality.Storage.Registry is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Persistence;

   function Project_Less (Left, Right : Project_Info) return Boolean is
     (Left.Id < Right.Id);
   package Project_Sorting is new Project_Vectors.Generic_Sorting
     ("<" => Project_Less);

   function Projects
     (Item : in out Store; Include_Removed : Boolean := False)
      return Project_Vectors.Vector
   is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
      Result : Project_Vectors.Vector;
      Row    : Entity;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Projects_Table),
         Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan projects");
      while Entity_Tables.Has_Element (Cursor) loop
         Row := Entity_Tables.Element (Cursor);
         if Include_Removed or else S (Row.State) /= "removed" then
            declare
               Path, Tags : Unbounded_String;
            begin
               if not Decode_Project_Payload (S (Row.Payload), Path, Tags) then
                  raise Storage_Error with
                    "malformed project row" & Positive'Image (Row.Id);
               end if;
               Result.Append
                 (Project_Info'
                    (Id => Row.Id, Path => Path, Tags => Tags,
                     Enabled => Row.Active,
                     Removed => S (Row.State) = "removed"));
            end;
         end if;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Projects_Table),
            Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance projects");
      end loop;
      Require_OK
        (Database.Transactions.Commit (Tx), "complete projects query");
      Project_Sorting.Sort (Result);
      return Result;
   end Projects;

   function Project (Item : in out Store; Id : Positive) return Project_Info is
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         raise Storage_Error with "project not found:" & Positive'Image (Id);
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "read project");
      declare
         Path, Tags : Unbounded_String;
      begin
         if not Decode_Project_Payload (S (Row.Payload), Path, Tags) then
            raise Storage_Error with
              "malformed project row" & Positive'Image (Id);
         end if;
         return
           (Id      => Row.Id,
            Path    => Path,
            Tags    => Tags,
            Enabled => Row.Active,
            Removed => S (Row.State) = "removed");
      end;
   end Project;

   function Validated_Project_Path (Path : String) return String is
      Input_Is_Link : constant Boolean := Project_Tools.Links.Is_Link (Path);
      Canonical     : constant String := Ada.Directories.Full_Name (Path);
      Manifest      : constant String := Canonical & "/alire.toml";
   begin
      if not Ada.Directories.Exists (Canonical) or else
        not Ada.Directories.Exists (Manifest)
      then
         raise Storage_Error with
           "project must be an existing Alire crate: " & Canonical;
      elsif Input_Is_Link or else Project_Tools.Links.Is_Link (Canonical) then
         raise Storage_Error with
           "project root must not be a symbolic link: " & Canonical;
      end if;
      declare
         Content : constant String := Ada_Quality.Bounded_Files.Read
           (Manifest, Ada_Quality.Resource_Limits.Maximum_File_Bytes);
         Name, Version : Unbounded_String;
      begin
         if not Ada_Quality.Manifests.Top_Level_String
           (Content, "name", Name)
           or else not Ada_Quality.Manifests.Top_Level_String
             (Content, "version", Version)
         then
            raise Storage_Error with
              "project has a malformed Alire manifest: " & Manifest;
         end if;
      end;
      return Canonical;
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         raise Storage_Error with "project path cannot be resolved: " & Path;
   end Validated_Project_Path;

   function Add_Project (Item : in out Store; Path : String) return Positive is
      Canonical : constant String := Validated_Project_Path (Path);
      Existing  : constant Project_Vectors.Vector := Projects (Item, True);
      Id        : Positive := 1;
      Tx        : Database.Transactions.Transaction;
      Status    : Database.Status.Result;
   begin
      for P of Existing loop
         if To_String (P.Path) = Canonical and then not P.Removed then
            raise Storage_Error with
              "project already registered:" & Positive'Image (P.Id);
         end if;
      end loop;
      Id := Next_Id (Item, Projects_Table);
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Projects_Table),
         (Id        => Id,
          Parent_Id => 0,
          Kind      => WW ("ada_project"),
          State     => WW ("registered"),
          Payload   => WW (Project_Payload (Canonical, "")),
          Active    => True));
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "insert project");
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "commit project");
      return Id;
   end Add_Project;

   procedure Update_Project
     (Item : in out Store; Id : Positive; Enabled : Boolean; State : String)
   is
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         raise Storage_Error with "project not found:" & Positive'Image (Id);
      end if;
      Row.Active := Enabled;
      Row.State := WW (State);
      Status := Entity_Tables.Update
        (Tx, Item.DB, Item.Schemas (Projects_Table), Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "update project");
      end if;
      Require_OK
        (Database.Transactions.Commit (Tx), "commit project update");
   end Update_Project;

   procedure Set_Enabled
     (Item : in out Store; Id : Positive; Enabled : Boolean) is
   begin
      Update_Project (Item, Id, Enabled, "registered");
   end Set_Enabled;

   procedure Remove_Project (Item : in out Store; Id : Positive) is
   begin
      Update_Project (Item, Id, False, "removed");
   end Remove_Project;

   procedure Relocate_Project
     (Item : in out Store; Id : Positive; Path : String)
   is
      Canonical : constant String := Validated_Project_Path (Path);
      Existing  : constant Project_Vectors.Vector := Projects (Item, True);
      Tx         : Database.Transactions.Transaction;
      Row        : Entity;
      Status     : Database.Status.Result;
   begin
      for P of Existing loop
         if P.Id = Id and then P.Removed then
            raise Storage_Error with
              "removed project cannot be relocated:" & Positive'Image (Id);
         elsif P.Id /= Id and then not P.Removed and then
           To_String (P.Path) = Canonical
         then
            raise Storage_Error with
              "project path already registered:" & Positive'Image (P.Id);
         end if;
      end loop;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         raise Storage_Error with "project not found:" & Positive'Image (Id);
      end if;
      declare
         Existing_Path, Tags : Unbounded_String;
      begin
         if not Decode_Project_Payload
           (S (Row.Payload), Existing_Path, Tags)
         then
            raise Storage_Error with
              "malformed project row" & Positive'Image (Id);
         end if;
         Row.Payload := WW
           (Project_Payload (Canonical, To_String (Tags)));
      end;
      Status := Entity_Tables.Update
        (Tx, Item.DB, Item.Schemas (Projects_Table), Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "relocate project");
      end if;
      Require_OK
        (Database.Transactions.Commit (Tx), "commit project relocation");
   end Relocate_Project;

   function Has_Tag (Project : Project_Info; Name : String) return Boolean is
     (Project_Tag_Is_Valid (Name) and then
      Project_Tags_Contain (To_String (Project.Tags), Name));

   function Is_Tag_Name (Name : String) return Boolean is
     (Project_Tag_Is_Valid (Name));

   procedure Update_Project_Tag
     (Item : in out Store; Id : Positive; Name : String; Add : Boolean)
   is
      Tx         : Database.Transactions.Transaction;
      Row        : Entity;
      Status     : Database.Status.Result;
      Path, Tags : Unbounded_String;
   begin
      if not Project_Tag_Is_Valid (Name) then
         raise Storage_Error with
           "project tag must contain 1..64 lowercase letters, digits, hyphens, or underscores";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      Require_OK (Status, "load project for tag update");
      if S (Row.State) = "removed" then
         raise Storage_Error with
           "removed project cannot be tagged:" & Positive'Image (Id);
      elsif not Decode_Project_Payload (S (Row.Payload), Path, Tags) then
         raise Storage_Error with
           "malformed project row" & Positive'Image (Id);
      end if;
      Row.Payload := WW
        (Project_Payload
           (To_String (Path),
            Update_Project_Tags (To_String (Tags), Name, Add)));
      Require_OK
        (Entity_Tables.Update
           (Tx, Item.DB, Item.Schemas (Projects_Table), Row),
         "update project tag");
      Require_OK
        (Database.Transactions.Commit (Tx), "commit project tag update");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Update_Project_Tag;

   procedure Add_Tag (Item : in out Store; Id : Positive; Name : String) is
   begin
      Update_Project_Tag (Item, Id, Name, Add => True);
   end Add_Tag;

   procedure Remove_Tag (Item : in out Store; Id : Positive; Name : String) is
   begin
      Update_Project_Tag (Item, Id, Name, Add => False);
   end Remove_Tag;
end Ada_Quality.Storage.Registry;
