with Ada.Containers;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Indicators;
with Ada_Quality.Manifests;
with Ada_Quality.Persistence;
with Ada_Quality.Reporting;
with Ada_Quality.Temporary_Directories;
with Database.Catalog;
with Database.Backup;
with Database.Export;
with Database.Import;
with Database.Predicates;
with Database.Restore;
with Database.Status;
with Database.Transactions;
with Database.Vacuum;
with Project_Tools.Links;
with Project_Tools.Files;

--  AQ-WAIVER: SRC-03 target=source_occurrence owner=aq expires=2099-12-31 justification=merge-boundary
package body Ada_Quality.Storage is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Ada_Quality.Persistence;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;

   Current_Schema_Version  : constant String :=
     Ada.Strings.Fixed.Trim (Positive'Image (Ada_Quality.Persistence.Current_Schema_Version), Ada.Strings.Both);
   function Measurement_State (Id : Indicator_Id; Kind : Value_Kind) return String is
      Registry : constant Ada_Quality.Indicators.Descriptor_Array := Ada_Quality.Indicators.Registry;
      Descriptor : constant Ada_Quality.Indicators.Indicator_Descriptor :=
        Registry (Id);
      function Trimmed (Value : Positive) return String is
        (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));
   begin
      return Value_Kind'Image (Kind) & ";indicator_version=" & Trimmed (Descriptor.Version) &
        ";method_version=" & Trimmed (Descriptor.Measurement_Version);
   end Measurement_State;

   procedure Trigger_Testing_Fault (Item : in out Store; Point : Testing_Fault_Point) is
   begin
      if Item.Next_Testing_Fault = Point then
         Item.Next_Testing_Fault := No_Testing_Fault;
         raise Storage_Error with "injected storage fault at " & Testing_Fault_Point'Image (Point);
      end if;
   end Trigger_Testing_Fault;

   procedure Initialize_Identifiers (Item : in out Store);

   function Project_Less (Left, Right : Project_Info) return Boolean is (Left.Id < Right.Id);
   package Project_Sorting is new Project_Vectors.Generic_Sorting ("<" => Project_Less);

   function History_Less (Left, Right : History_Item) return Boolean is (Left.Id < Right.Id);
   package History_Sorting is new History_Vectors.Generic_Sorting ("<" => History_Less);

   function Detail_Less (Left, Right : Detail_Info) return Boolean is (Left.Id < Right.Id);
   package Detail_Sorting is new Detail_Vectors.Generic_Sorting ("<" => Detail_Less);

   package Tag_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "<" => Ada.Strings.Unbounded."<", "=" => Ada.Strings.Unbounded."=");

   function Tag_Set (Tags : String) return Tag_Sets.Set is
      Result : Tag_Sets.Set;
      Start  : Natural := (if Tags'Length = 0 then 0 else Tags'First);
   begin
      while Start /= 0 and then Start <= Tags'Last loop
         declare
            Stop : Natural := Ada.Strings.Fixed.Index (Tags, ",", From => Start);
         begin
            if Stop = 0 then Stop := Tags'Last + 1; end if;
            Result.Include (To_Unbounded_String (Tags (Start .. Stop - 1)));
            Start := Stop + 1;
         end;
      end loop;
      return Result;
   end Tag_Set;

   function Tag_List (Tags : Tag_Sets.Set) return String is
      Result : Unbounded_String;
   begin
      for Tag of Tags loop
         if Length (Result) > 0 then Append (Result, ","); end if;
         Append (Result, Tag);
      end loop;
      return To_String (Result);
   end Tag_List;

   procedure Require_OK (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Storage_Error with Context & ": " & Decode (To_Wide_Wide_String (Status.Message));
      end if;
   end Require_OK;

   procedure Register_Schemas (Item : in out Store) is
      Status : Database.Status.Result;
   begin
      for J in Item.Schemas'Range loop
         Item.Schemas (J) := New_Schema (Table_Name (J));
         Status := Entity_Tables.Register (Item.DB, Item.Schemas (J));
         Require_OK (Status, "register " & Decode (Table_Name (J)));
      end loop;

      declare
         Tx : Database.Transactions.Transaction;
      begin
         Database.Transactions.Begin_Write (Item.DB, Tx);
         Status := Entity_Tables.Insert
           (Tx, Item.DB, Item.Schemas (Metadata_Table),
            (Id => 1, Parent_Id => 0, Kind => WW ("schema_version"), State => WW ("active"),
             Payload => WW (Current_Schema_Version), Active => True));
         if not Database.Status.Is_Ok (Status) then
            Database.Transactions.Rollback (Tx);
            Require_OK (Status, "write schema metadata");
         end if;
         Trigger_Testing_Fault (Item, Schema_Creation_Commit);
         Require_OK (Database.Transactions.Commit (Tx), "commit schema metadata");
      end;
   end Register_Schemas;

   procedure Load_Schemas (Item : in out Store) is
      Status : Database.Status.Result;
   begin
      for J in Item.Schemas'Range loop
         Status := Database.Catalog.Find_By_Name
           (Database.Catalog_State_Key (Item.DB), Table_Name (J), Item.Schemas (J));
         Require_OK (Status, "load " & Decode (Table_Name (J)));
      end loop;
   end Load_Schemas;

   procedure Migrate (Item : in out Store) is
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Metadata_Table), 1, Row);
      Require_OK (Status, "read schema version for migration");
      if S (Row.Payload) = Current_Schema_Version then
         Require_OK (Database.Transactions.Commit (Tx), "complete schema version check");
      elsif S (Row.Payload) in "1" | "2" | "3" | "4" then
         if S (Row.Payload) = "1" then
            declare
               Cursor : Entity_Tables.Cursor;
               Legacy : Entity_Vectors.Vector;
            begin
               Status := Entity_Tables.Scan
                 (Tx, Item.DB, Item.Schemas (Assessments_Table), Database.Predicates.True_Predicate, Cursor);
               Require_OK (Status, "scan legacy assessments");
               while Entity_Tables.Has_Element (Cursor) loop
                  Legacy.Append (Entity_Tables.Element (Cursor));
                  Status := Entity_Tables.Next
                    (Tx, Item.DB, Item.Schemas (Assessments_Table), Database.Predicates.True_Predicate, Cursor);
                  Require_OK (Status, "advance legacy assessment scan");
               end loop;
               for Assessment_Row of Legacy loop
                  declare
                     Payload : constant String := S (Assessment_Row.Payload);
                     Split   : constant Natural := Ada.Strings.Fixed.Index (Payload, "|");
                     Updated : Entity := Assessment_Row;
                  begin
                     if Field (Payload, "source") = "" and then Split > Payload'First and then Split < Payload'Last then
                        Updated.Payload := WW
                          (Assessment_Payload
                             (Payload (Payload'First .. Split - 1), Payload (Split + 1 .. Payload'Last), ""));
                        Status := Entity_Tables.Update
                          (Tx, Item.DB, Item.Schemas (Assessments_Table), Updated);
                        Require_OK (Status, "migrate legacy assessment fingerprints");
                     end if;
                  end;
               end loop;
            end;
         end if;
         --  Version 5 changes only the project payload, preserving the canonical path and adding an empty tag set.
         declare
            Cursor   : Entity_Tables.Cursor;
            Projects : Entity_Vectors.Vector;
         begin
            Status := Entity_Tables.Scan
              (Tx, Item.DB, Item.Schemas (Projects_Table), Database.Predicates.True_Predicate, Cursor);
            Require_OK (Status, "scan projects for tag migration");
            while Entity_Tables.Has_Element (Cursor) loop
               Projects.Append (Entity_Tables.Element (Cursor));
               Status := Entity_Tables.Next
                 (Tx, Item.DB, Item.Schemas (Projects_Table), Database.Predicates.True_Predicate, Cursor);
               Require_OK (Status, "advance project tag migration");
            end loop;
            for Project_Row of Projects loop
               declare
                  Updated : Entity := Project_Row;
                  Existing_Path, Existing_Tags : Unbounded_String;
               begin
                  if not Decode_Project_Payload
                    (S (Project_Row.Payload), Existing_Path, Existing_Tags)
                  then
                     Updated.Payload := WW (Project_Payload (S (Project_Row.Payload), ""));
                  end if;
                  Require_OK
                    (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Projects_Table), Updated),
                     "migrate project tags");
               end;
            end loop;
         end;
         Row.Payload := WW (Current_Schema_Version);
         Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Metadata_Table), Row);
         Require_OK (Status, "migrate schema metadata to the current version");
         Trigger_Testing_Fault (Item, Schema_Migration_Commit);
         Require_OK (Database.Transactions.Commit (Tx), "commit schema migration");
      else
         Database.Transactions.Rollback (Tx);
         raise Storage_Error with "unsupported schema version: " & S (Row.Payload);
      end if;
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Migrate;

   procedure Open (Item : in out Store; Path : String; Create_If_Missing : Boolean := True) is
      Exists : constant Boolean := Ada.Directories.Exists (Path);
   begin
      if Item.Opened then Close (Item); end if;
      if Exists then
         Database.Open (Item.DB, Encode (Path));
      elsif Create_If_Missing then
         Database.Create (Item.DB, Encode (Path));
      else
         raise Storage_Error with "database not found: " & Path;
      end if;
      Require_OK (Database.Last_Result (Item.DB), "open database");
      Item.Opened := True;
      if Exists then
         Load_Schemas (Item);
         Migrate (Item);
      else
         Register_Schemas (Item);
      end if;
      Initialize_Identifiers (Item);
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Is_Open (Item.DB) then Database.Close (Item.DB); end if;
         Item.Opened := False;
         raise;
   end Open;

   procedure Close (Item : in out Store) is
   begin
      if Item.Opened then
         Database.Close (Item.DB);
         Item.Opened := False;
      end if;
   end Close;

   procedure Compact (Item : in out Store) is
      Tx : Database.Transactions.Transaction;
   begin
      if not Item.Opened then
         raise Storage_Error with "database is not open";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Require_OK (Database.Vacuum.Vacuum (Tx), "compact database");
      Require_OK (Database.Transactions.Commit (Tx), "commit database compaction");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Compact;

   function Is_Open (Item : Store) return Boolean is (Item.Opened);

   overriding procedure Finalize (Item : in out Store) is
   begin
      Close (Item);
   end Finalize;

   procedure Initialize_Identifiers (Item : in out Store) is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      for Table in Item.Schemas'Range loop
         declare
            Max_Id : Natural := 0;
         begin
            Status := Entity_Tables.Scan
              (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
            Require_OK (Status, "initialize table identifier");
            while Entity_Tables.Has_Element (Cursor) loop
               Max_Id := Natural'Max (Max_Id, Entity_Tables.Element (Cursor).Id);
               Status := Entity_Tables.Next
                 (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
               Require_OK (Status, "advance identifier initialization");
            end loop;
            if Max_Id = Positive'Last then
               raise Storage_Error with "identifier space exhausted for " & Decode (Table_Name (Table));
            end if;
            Item.Next_Identifiers (Table) := Max_Id + 1;
         end;
      end loop;
      Require_OK (Database.Transactions.Commit (Tx), "complete identifier initialization");
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Initialize_Identifiers;

   function Reserve_Ids
     (Item : in out Store; Table : Positive; Count : Natural) return Positive
   is
      Result : constant Positive := Item.Next_Identifiers (Table);
   begin
      if Count > Natural (Positive'Last - Result) then
         raise Storage_Error with "identifier space exhausted for " & Decode (Table_Name (Table));
      end if;
      --  The store owns an exclusive database lock, so reserving from this
      --  open-session high-water mark is collision-free. Failed transactions
      --  may leave harmless gaps but never reuse an identifier.
      Item.Next_Identifiers (Table) := Result + Count;
      return Result;
   end Reserve_Ids;

   function Next_Id (Item : in out Store; Table : Positive) return Positive is
   begin
      return Reserve_Ids (Item, Table, 1);
   end Next_Id;

   function Projects (Item : in out Store; Include_Removed : Boolean := False) return Project_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
      Result : Project_Vectors.Vector;
      Row    : Entity;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Projects_Table), Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan projects");
      while Entity_Tables.Has_Element (Cursor) loop
         Row := Entity_Tables.Element (Cursor);
         if Include_Removed or else S (Row.State) /= "removed" then
            declare Path, Tags : Unbounded_String; begin
               if not Decode_Project_Payload (S (Row.Payload), Path, Tags) then
                  raise Storage_Error with "malformed project row" & Positive'Image (Row.Id);
               end if;
               Result.Append
                 (Project_Info'(Id => Row.Id, Path => Path, Tags => Tags,
                  Enabled => Row.Active, Removed => S (Row.State) = "removed"));
            end;
         end if;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Projects_Table), Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance projects");
      end loop;
      Require_OK (Database.Transactions.Commit (Tx), "complete projects query");
      Project_Sorting.Sort (Result);
      return Result;
   end Projects;

   function Project (Item : in out Store; Id : Positive) return Project_Info is
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         raise Storage_Error with "project not found:" & Positive'Image (Id);
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "read project");
      declare Path, Tags : Unbounded_String; begin
         if not Decode_Project_Payload (S (Row.Payload), Path, Tags) then
            raise Storage_Error with "malformed project row" & Positive'Image (Id);
         end if;
         return (Id => Row.Id, Path => Path, Tags => Tags,
                 Enabled => Row.Active, Removed => S (Row.State) = "removed");
      end;
   end Project;

   function Validated_Project_Path (Path : String) return String is
      Input_Is_Link : constant Boolean := Project_Tools.Links.Is_Link (Path);
      Canonical : constant String := Ada.Directories.Full_Name (Path);
      Manifest  : constant String := Canonical & "/alire.toml";
   begin
      if not Ada.Directories.Exists (Canonical) or else
        not Ada.Directories.Exists (Canonical & "/alire.toml")
      then
         raise Storage_Error with "project must be an existing Alire crate: " & Canonical;
      elsif Input_Is_Link or else Project_Tools.Links.Is_Link (Canonical) then
         raise Storage_Error with "project root must not be a symbolic link: " & Canonical;
      end if;
      declare
         Content : constant String := Project_Tools.Files.Read_Raw_File (Manifest);
         Name, Version : Ada.Strings.Unbounded.Unbounded_String;
      begin
         if not Ada_Quality.Manifests.Top_Level_String (Content, "name", Name) or else
           not Ada_Quality.Manifests.Top_Level_String (Content, "version", Version)
         then
            raise Storage_Error with "project has a malformed Alire manifest: " & Manifest;
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
            raise Storage_Error with "project already registered:" & Positive'Image (P.Id);
         end if;
      end loop;
      Id := Next_Id (Item, Projects_Table);
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Projects_Table),
         (Id => Id, Parent_Id => 0, Kind => WW ("ada_project"), State => WW ("registered"),
          Payload => WW (Project_Payload (Canonical, "")), Active => True));
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "insert project");
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "commit project");
      return Id;
   end Add_Project;

   procedure Update_Project
     (Item : in out Store; Id : Positive; Enabled : Boolean; State : String) is
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         raise Storage_Error with "project not found:" & Positive'Image (Id);
      end if;
      Row.Active := Enabled;
      Row.State := WW (State);
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Projects_Table), Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "update project");
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "commit project update");
   end Update_Project;

   procedure Set_Enabled (Item : in out Store; Id : Positive; Enabled : Boolean) is
   begin
      Update_Project (Item, Id, Enabled, "registered");
   end Set_Enabled;

   procedure Remove_Project (Item : in out Store; Id : Positive) is
   begin
      Update_Project (Item, Id, False, "removed");
   end Remove_Project;

   procedure Relocate_Project (Item : in out Store; Id : Positive; Path : String) is
      Canonical : constant String := Validated_Project_Path (Path);
      Existing  : constant Project_Vectors.Vector := Projects (Item, True);
      Tx         : Database.Transactions.Transaction;
      Row        : Entity;
      Status     : Database.Status.Result;
   begin
      for P of Existing loop
         if P.Id = Id and then P.Removed then
            raise Storage_Error with "removed project cannot be relocated:" & Positive'Image (Id);
         elsif P.Id /= Id and then not P.Removed and then To_String (P.Path) = Canonical then
            raise Storage_Error with "project path already registered:" & Positive'Image (P.Id);
         end if;
      end loop;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         raise Storage_Error with "project not found:" & Positive'Image (Id);
      end if;
      declare Existing_Path, Tags : Unbounded_String; begin
         if not Decode_Project_Payload (S (Row.Payload), Existing_Path, Tags) then
            raise Storage_Error with "malformed project row" & Positive'Image (Id);
         end if;
         Row.Payload := WW (Project_Payload (Canonical, To_String (Tags)));
      end;
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Projects_Table), Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "relocate project");
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "commit project relocation");
   end Relocate_Project;

   function Has_Project_Tag (Project : Project_Info; Name : String) return Boolean is
     (Project_Tag_Is_Valid (Name) and then Tag_Set (To_String (Project.Tags)).Contains
        (To_Unbounded_String (Name)));

   function Is_Project_Tag_Name (Name : String) return Boolean is
     (Project_Tag_Is_Valid (Name));

   procedure Update_Project_Tag
     (Item : in out Store; Id : Positive; Name : String; Add : Boolean)
   is
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
      Path, Tags : Unbounded_String;
   begin
      if not Project_Tag_Is_Valid (Name) then
         raise Storage_Error with
           "project tag must contain 1..64 lowercase letters, digits, hyphens, or underscores";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Projects_Table), Id, Row);
      Require_OK (Status, "load project for tag update");
      if S (Row.State) = "removed" then
         raise Storage_Error with "removed project cannot be tagged:" & Positive'Image (Id);
      elsif not Decode_Project_Payload (S (Row.Payload), Path, Tags) then
         raise Storage_Error with "malformed project row" & Positive'Image (Id);
      end if;
      declare Values : Tag_Sets.Set := Tag_Set (To_String (Tags)); begin
         if Add then Values.Include (To_Unbounded_String (Name));
         else Values.Exclude (To_Unbounded_String (Name));
         end if;
         Row.Payload := WW (Project_Payload (To_String (Path), Tag_List (Values)));
      end;
      Require_OK
        (Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Projects_Table), Row),
         "update project tag");
      Require_OK (Database.Transactions.Commit (Tx), "commit project tag update");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Update_Project_Tag;

   procedure Add_Project_Tag (Item : in out Store; Id : Positive; Name : String) is
   begin
      Update_Project_Tag (Item, Id, Name, Add => True);
   end Add_Project_Tag;

   procedure Remove_Project_Tag (Item : in out Store; Id : Positive; Name : String) is
   begin
      Update_Project_Tag (Item, Id, Name, Add => False);
   end Remove_Project_Tag;

   procedure Backup (Item : in out Store; Destination : String) is
   begin
      if Ada.Directories.Exists (Destination) then
         raise Storage_Error with "backup destination already exists: " & Destination;
      end if;
      Require_OK
        (Database.Backup.Create_Physical_Backup (Item.DB, Encode (Destination)),
         "create database backup");
   end Backup;

   procedure Export (Item : in out Store; Destination : String) is
      Tx     : Database.Transactions.Transaction;
      Status : Database.Status.Result;
   begin
      if Ada.Directories.Exists (Destination) then
         raise Storage_Error with "export destination already exists: " & Destination;
      end if;
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Database.Export.Export_Database (Tx, Encode (Destination));
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "export database");
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "complete database export");
   end Export;

   procedure Restore (Source, Destination : String) is
   begin
      Require_OK
        (Database.Restore.Restore_Physical_Backup (Encode (Source), Encode (Destination)),
         "restore database backup");
   end Restore;

   procedure Import (Source, Destination : String) is
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;
   begin
      if Ada.Directories.Exists (Destination) then
         raise Storage_Error with "import destination already exists: " & Destination;
      elsif not Ada.Directories.Exists (Source) then
         raise Storage_Error with "logical export not found: " & Source;
      end if;
      Database.Create (DB, Encode (Destination));
      Require_OK (Database.Last_Result (DB), "create import destination");
      Database.Transactions.Begin_Write (DB, Tx);
      Require_OK (Database.Import.Import_Database (Tx, Encode (Source)), "import database");
      Require_OK (Database.Transactions.Commit (Tx), "commit database import");
      Database.Close (DB);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         if Database.Is_Open (DB) then Database.Close (DB); end if;
         Project_Tools.Files.Delete_File_If_Present (Destination);
         Project_Tools.Files.Delete_File_If_Present (Destination & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Destination & ".lock");
         raise;
   end Import;

   procedure Merge
     (Item : in out Store; Source : String;
      Added_Projects, Added_Assessments : out Natural)
   is
      package Id_Maps is new Ada.Containers.Ordered_Maps (Positive, Positive);
      Temp : Ada_Quality.Temporary_Directories.Temporary_Directory;
      Source_Path : Unbounded_String := To_Unbounded_String (Source);
      Session : Ada_Quality.Reporting.Session;
      Projects_Map : Id_Maps.Map;
      Runs_Map : Id_Maps.Map;

      function Insert_Project
        (Path, Tags : String; Enabled, Removed : Boolean) return Positive
      is
         Id : constant Positive := Next_Id (Item, Projects_Table);
         Tx : Database.Transactions.Transaction;
      begin
         Database.Transactions.Begin_Write (Item.DB, Tx);
         Require_OK
           (Entity_Tables.Insert
              (Tx, Item.DB, Item.Schemas (Projects_Table),
               (Id => Id, Parent_Id => 0, Kind => WW ("ada_project"),
                State => WW (if Removed then "removed" else "registered"),
                Payload => WW (Project_Payload (Path, Tags)), Active => Enabled and then not Removed)),
            "insert merged project");
         Require_OK (Database.Transactions.Commit (Tx), "commit merged project");
         return Id;
      exception
         when others =>
            if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
            raise;
      end Insert_Project;

      function Existing_Run
        (Project_Id : Positive; Run : Ada_Quality.Reporting.Run_Record;
         Occurrence : Positive) return Natural
      is
         Seen : Natural := 0;
      begin
         for Candidate of History (Item, Project_Id) loop
            if To_String (Candidate.Status) = "completed" and then
              Candidate.Source_Fingerprint = Run.Source_Id and then
              Candidate.Policy_Fingerprint = Run.Policy_Id and then
              Candidate.Toolchain_Fingerprint = Run.Toolchain_Id
            then
               Seen := Seen + 1;
               if Seen = Occurrence then return Candidate.Id; end if;
            end if;
         end loop;
         return 0;
      end Existing_Run;

      function Source_Occurrence (Run : Ada_Quality.Reporting.Run_Record) return Positive is
         Result : Natural := 0;
      begin
         for Candidate of Ada_Quality.Reporting.Runs (Session, Run.Project_Id) loop
            exit when Candidate.Id > Run.Id;
            if Candidate.State = Assessment_Completed and then
              Candidate.Source_Id = Run.Source_Id and then Candidate.Policy_Id = Run.Policy_Id and then
              Candidate.Toolchain_Id = Run.Toolchain_Id
            then
               Result := Result + 1;
            end if;
         end loop;
         return Positive (Result);
      end Source_Occurrence;
   begin
      Added_Projects := 0;
      Added_Assessments := 0;
      begin
         Ada_Quality.Reporting.Open (Session, Source);
      exception
         when Ada_Quality.Reporting.Reporting_Error | Ada_Quality.Reporting.Schema_Error |
           Ada_Quality.Reporting.Integrity_Error =>
            Ada_Quality.Temporary_Directories.Create (Temp, "ada-quality-merge");
            Source_Path := To_Unbounded_String
              (Ada_Quality.Temporary_Directories.Child (Temp, "source.db"));
            Import (Source, To_String (Source_Path));
            Ada_Quality.Reporting.Open (Session, To_String (Source_Path));
      end;

      for Source_Project of Ada_Quality.Reporting.Projects (Session, Include_Removed => True) loop
         declare Target_Id : Natural := 0; begin
            for Target of Projects (Item, Include_Removed => True) loop
               if Target.Path = Source_Project.Path then Target_Id := Target.Id; end if;
            end loop;
            if Target_Id = 0 then
               Target_Id := Insert_Project
                 (To_String (Source_Project.Path), To_String (Source_Project.Tags),
                  Source_Project.Enabled, Source_Project.Removed);
               Added_Projects := Added_Projects + 1;
            else
               declare Target : constant Project_Info := Project (Item, Positive (Target_Id)); begin
                  if not Target.Removed then
                     for Tag of Tag_Set (To_String (Source_Project.Tags)) loop
                        Add_Project_Tag (Item, Target.Id, To_String (Tag));
                     end loop;
                  end if;
               end;
            end if;
            Projects_Map.Insert (Source_Project.Id, Positive (Target_Id));
         end;
      end loop;

      for Run of Ada_Quality.Reporting.Runs (Session) loop
         if Run.State = Assessment_Completed then
            declare
               Target_Project : constant Positive := Projects_Map.Element (Run.Project_Id);
               Existing : constant Natural := Existing_Run
                 (Target_Project, Run, Source_Occurrence (Run));
               Target_Run : Positive;
            begin
               if Existing > 0 then
                  Target_Run := Positive (Existing);
               else
                  declare
                     Stored : constant Ada_Quality.Reporting.Assessment_Record :=
                       Ada_Quality.Reporting.Read_Assessment (Session, Run.Id);
                     Value : Assessment;
                  begin
                     Value.Project_Id := Target_Project;
                     Value.Project_Path := Project (Item, Target_Project).Path;
                     Value.Source_Fingerprint := Run.Source_Id;
                     Value.Policy_Fingerprint := Run.Policy_Id;
                     Value.Toolchain_Fingerprint := Run.Toolchain_Id;
                     Value.Status := Assessment_Completed;
                     Value.Results := Stored.Results;
                     for Execution of Stored.Executions loop
                        Value.Executions.Append
                          (Tool_Execution'
                             (Tool => Execution.Tool, Command => Execution.Command,
                              Status => Execution.Status, Exit_Code => Execution.Exit_Code,
                              Output_Digest => Execution.Output_Digest,
                              Output_Bytes => Execution.Output_Bytes, Truncated => Execution.Truncated));
                     end loop;
                     Target_Run := Publish (Item, Value);
                     Added_Assessments := Added_Assessments + 1;
                  end;
               end if;
               Runs_Map.Insert (Run.Id, Target_Run);
            end;
         end if;
      end loop;

      declare Existing_Aliases : Tag_Sets.Set; begin
         for Event of Events (Item) loop
            if To_String (Event.Kind) = "alias" then Existing_Aliases.Include (Event.Summary); end if;
         end loop;
         for Alias of Ada_Quality.Reporting.Aliases (Session) loop
            if Runs_Map.Contains (Alias.Run_Id) and then not Existing_Aliases.Contains (Alias.Name) then
               Add_Assessment_Alias (Item, Runs_Map.Element (Alias.Run_Id), To_String (Alias.Name));
               Existing_Aliases.Include (Alias.Name);
            end if;
         end loop;
      end;
      Check (Item);
   end Merge;

   function Retention_Candidates
     (Item : in out Store; Before : Ada.Calendar.Time; Keep : Natural)
      return History_Vectors.Vector
   is
      package Count_Maps is new Ada.Containers.Ordered_Maps (Positive, Natural);
      Runs : constant History_Vectors.Vector := History (Item);
      Result : History_Vectors.Vector;
      Per_Project : Count_Maps.Map;
      use type Ada.Calendar.Time;
   begin
      for Index in reverse Runs.First_Index .. Runs.Last_Index loop
         declare
            Run : constant History_Item := Runs (Index);
            Payload : Assessment_Payload_Data;
            Seen : Natural :=
              (if Per_Project.Contains (Run.Project_Id)
               then Per_Project.Element (Run.Project_Id) else 0);
         begin
            if To_String (Run.Status) /= "running" and then
              Decode_Assessment_Payload (To_String (Run.Summary), Payload)
            then
               if Seen < Keep then
                  Seen := Seen + 1;
               elsif Payload.Finished_At.Present and then Payload.Finished_At.Value < Before then
                  Result.Prepend (Run);
               end if;
               Per_Project.Include (Run.Project_Id, Seen);
            end if;
         end;
      end loop;
      return Result;
   end Retention_Candidates;

   --  AQ-WAIVER: SRC-03 target=less owner=aq expires=2099-12-31 justification=archive-prune-boundary
   procedure Archive_And_Prune
     (Item        : in out Store;
      Destination : String;
      Before      : Ada.Calendar.Time;
      Keep        : Natural;
      Removed     : out Natural)
   is
      package Id_Sets is new Ada.Containers.Ordered_Sets (Positive);
      Tx         : Database.Transactions.Transaction;
      Cursor     : Entity_Tables.Cursor;
      Status     : Database.Status.Result;
      Deleted    : Id_Sets.Set;
      Candidates : constant History_Vectors.Vector := Retention_Candidates (Item, Before, Keep);
   begin
      if not Item.Opened then raise Storage_Error with "database is not open"; end if;
      Export (Item, Destination);
      Database.Transactions.Begin_Write (Item.DB, Tx);
      for Run of Candidates loop Deleted.Include (Run.Id); end loop;

      for Table in Indicator_Results_Table .. Events_Table loop
         declare
            Children : Entity_Vectors.Vector;
         begin
            Status := Entity_Tables.Scan
              (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
            Require_OK (Status, "scan archived assessment details");
            while Entity_Tables.Has_Element (Cursor) loop
               declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
                  if Row.Parent_Id > 0 and then Deleted.Contains (Positive (Row.Parent_Id)) then
                     Children.Append (Row);
                  end if;
               end;
               Status := Entity_Tables.Next
                 (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
               Require_OK (Status, "advance archived detail scan");
            end loop;
            for Row of Children loop
               Require_OK
                 (Entity_Tables.Delete (Tx, Item.DB, Item.Schemas (Table), Row.Id),
                  "delete archived assessment detail");
            end loop;
         end;
      end loop;
      for Id of Deleted loop
         Require_OK
           (Entity_Tables.Delete (Tx, Item.DB, Item.Schemas (Assessments_Table), Id),
            "delete archived assessment");
      end loop;
      Require_OK (Database.Transactions.Commit (Tx), "commit assessment retention");
      Removed := Natural (Deleted.Length);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Archive_And_Prune;

   function Assessment_Status_Image (Value : Assessment_Status) return String is
   begin
      case Value is
         when Assessment_Running => return "running";
         when Assessment_Completed => return "completed";
         when Assessment_Invalid => return "invalid";
         when Assessment_Interrupted => return "interrupted";
      end case;
   end Assessment_Status_Image;

   function Start_Assessment
     (Item               : in out Store;
      Project_Id         : Positive;
      Source_Fingerprint : String;
      Policy_Fingerprint : String) return Positive
   is
      Registered : constant Project_Info := Project (Item, Project_Id);
      Run_Id   : Positive := 1;
      Event_Id : Positive := 1;
      Tx       : Database.Transactions.Transaction;
      Status   : Database.Status.Result;
   begin
      if not Fingerprint_Is_Valid (Source_Fingerprint) or else
        not Fingerprint_Is_Valid (Policy_Fingerprint)
      then
         raise Storage_Error with "assessment fingerprints must be nonempty single-line identities";
      elsif Registered.Removed or else not Registered.Enabled then
         raise Storage_Error with "assessment project must be active and enabled";
      end if;
      Run_Id := Next_Id (Item, Assessments_Table);
      Event_Id := Next_Id (Item, Events_Table);
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Assessments_Table),
         (Id => Run_Id, Parent_Id => Project_Id, Kind => WW ("assessment"), State => WW ("running"),
          Payload => WW (Assessment_Payload (Source_Fingerprint, Policy_Fingerprint, "", Started_At => UTC_Now)),
          Active => False));
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "start assessment");
      end if;
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Events_Table),
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("started"), State => WW ("running"),
          Payload => WW ("assessment created before external tools"), Active => True));
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "record assessment start");
      end if;
      Trigger_Testing_Fault (Item, Assessment_Start_Commit);
      Require_OK (Database.Transactions.Commit (Tx), "commit assessment start");
      return Run_Id;
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Start_Assessment;

   function Publish (Item : in out Store; Value : Assessment) return Positive is
      function Finding_Count return Natural is
         Result : Natural := 0;
      begin
         for Indicator of Value.Results loop
            Result := Result + Natural (Indicator.Findings.Length);
         end loop;
         return Result;
      end Finding_Count;

      Result_Count : constant Natural := Natural (Value.Results.Length);
      Run_Id       : Positive := 1;
      Result_Id    : Natural := 0;
      Measure_Id   : Natural := 0;
      Finding_Id   : Natural := 0;
      Execution_Id : Natural := 0;
      Event_Id     : Positive := 1;
      Stamp      : constant String := (if Item.Legacy_Testing_Evidence then "" else UTC_Now);
      Tx         : Database.Transactions.Transaction;
      Status     : Database.Status.Result;
      Run_Row    : Entity;

      procedure Insert (Table : Positive; Row : Entity; Context : String) is
      begin
         Status := Entity_Tables.Insert (Tx, Item.DB, Item.Schemas (Table), Row);
         if not Database.Status.Is_Ok (Status) then
            raise Storage_Error with Context;
         end if;
      end Insert;

      procedure Publish_Run is
      begin
         if Value.Id = 0 then
            Insert
              (Assessments_Table,
               (Id => Run_Id, Parent_Id => Value.Project_Id, Kind => WW ("assessment"),
                State => WW (Assessment_Status_Image (Value.Status)),
                Payload => WW (Assessment_Payload
                  (To_String (Value.Source_Fingerprint), To_String (Value.Policy_Fingerprint),
                   To_String (Value.Toolchain_Fingerprint), Started_At => Stamp, Finished_At => Stamp,
                   Lossless => not Item.Legacy_Testing_Evidence)),
                Active => Value.Status = Assessment_Completed), "insert assessment");
         else
            Status := Entity_Tables.Find
              (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Id, Run_Row);
            if not Database.Status.Is_Ok (Status) or else S (Run_Row.State) /= "running" then
               raise Storage_Error with "assessment publication requires a running record";
            elsif Run_Row.Parent_Id /= Value.Project_Id then
               raise Storage_Error with "assessment publication project does not own the running record";
            end if;
            Run_Row.State := WW (Assessment_Status_Image (Value.Status));
            Run_Row.Payload :=
              WW (Assessment_Payload
                (To_String (Value.Source_Fingerprint), To_String (Value.Policy_Fingerprint),
                 To_String (Value.Toolchain_Fingerprint), Started_At => Field (S (Run_Row.Payload), "started_at"),
                 Finished_At => Stamp, Lossless => not Item.Legacy_Testing_Evidence));
            Run_Row.Active := Value.Status = Assessment_Completed;
            Status := Entity_Tables.Update
              (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Row);
            if not Database.Status.Is_Ok (Status) then
               raise Storage_Error with "update running assessment";
            end if;
         end if;
      end Publish_Run;

      procedure Publish_Children is
      begin
         for R of Value.Results loop
            Insert
              (Indicator_Results_Table,
               (Id => Positive (Result_Id), Parent_Id => Run_Id, Kind => WW (Image (R.Indicator)),
                State => WW (Image (R.Execution) & "/" & Image (R.Compliance)),
                Payload => WW
                  (if Item.Legacy_Testing_Evidence then
                     To_String (R.Summary) & Character'Val (10) & To_String (R.Evidence)
                   else Result_Payload (R)),
                Active => R.Compliance = Pass), "insert indicator result");
            Result_Id := Result_Id + 1;
            Insert
              (Measurements_Table,
               (Id => Positive (Measure_Id), Parent_Id => Run_Id, Kind => WW (Image (R.Indicator)),
                State => WW (Measurement_State (R.Indicator, R.Measurement.Kind)),
                Payload => WW (Image (R.Measurement)), Active => R.Execution = Succeeded), "insert measurement");
            Measure_Id := Measure_Id + 1;
            for F of R.Findings loop
               Insert
                 (Findings_Table,
                  (Id => Positive (Finding_Id), Parent_Id => Run_Id, Kind => WW (To_String (F.Fingerprint)),
                   State => WW (Severity'Image (F.Level)),
                   Payload => WW
                     (if Item.Legacy_Testing_Evidence then
                        To_String (F.Rule) & Character'Val (10) & To_String (F.Message)
                      else Finding_Payload (F)),
                   Active => True),
                  "insert finding");
               Finding_Id := Finding_Id + 1;
            end loop;
         end loop;
         for Execution of Value.Executions loop
            Insert
              (Executions_Table,
               (Id => Positive (Execution_Id), Parent_Id => Run_Id, Kind => WW (To_String (Execution.Tool)),
                State => WW (Image (Execution.Status)),
                Payload => WW (Execution_Payload (Execution)),
                Active => Execution.Status = Tool_Completed),
               "insert tool execution");
            Execution_Id := Execution_Id + 1;
         end loop;
         Insert
           (Events_Table,
            (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("published"),
             State => WW (Assessment_Status_Image (Value.Status)),
             Payload => WW ("atomic publication"), Active => True),
            "insert event");
      end Publish_Children;
   begin
      if not Is_Publishable (Value) then
         raise Storage_Error with "assessment is not a complete valid terminal result set";
      end if;
      if Value.Id = 0 then
         declare
            Registered : constant Project_Info := Project (Item, Positive (Value.Project_Id));
            pragma Unreferenced (Registered);
         begin
            null;
         end;
      end if;
      --  Reserve identifiers only after the complete value and its project
      --  ownership have passed validation.
      Run_Id :=
        (if Value.Id = 0 then Next_Id (Item, Assessments_Table) else Positive (Value.Id));
      Result_Id := Reserve_Ids (Item, Indicator_Results_Table, Result_Count);
      Measure_Id := Reserve_Ids (Item, Measurements_Table, Result_Count);
      Finding_Id := Reserve_Ids (Item, Findings_Table, Finding_Count);
      Execution_Id := Reserve_Ids
        (Item, Executions_Table, Natural (Value.Executions.Length));
      Event_Id := Next_Id (Item, Events_Table);
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Publish_Run;
      Publish_Children;
      Trigger_Testing_Fault (Item, Assessment_Publication_Commit);
      Require_OK (Database.Transactions.Commit (Tx), "publish assessment");
      return Run_Id;
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Publish;

   function History (Item : in out Store; Project_Id : Natural := 0) return History_Vectors.Vector is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
      Result : History_Vectors.Vector;
      Row    : Entity;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Assessments_Table), Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan history");
      while Entity_Tables.Has_Element (Cursor) loop
         Row := Entity_Tables.Element (Cursor);
         if Project_Id = 0 or else Row.Parent_Id = Project_Id then
            Result.Append
              (History_Item'(Id => Row.Id, Project_Id => Positive (Row.Parent_Id),
               Status => To_Unbounded_String (S (Row.State)), Summary => To_Unbounded_String (S (Row.Payload)),
               Source_Fingerprint => To_Unbounded_String (Field (S (Row.Payload), "source")),
               Policy_Fingerprint => To_Unbounded_String (Field (S (Row.Payload), "policy")),
               Toolchain_Fingerprint => To_Unbounded_String (Field (S (Row.Payload), "toolchain"))));
         end if;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Assessments_Table), Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance history");
      end loop;
      Require_OK (Database.Transactions.Commit (Tx), "complete history query");
      History_Sorting.Sort (Result);
      return Result;
   end History;

   function Details
     (Item : in out Store; Table : Positive; Run_Id : Natural) return Detail_Vectors.Vector
   is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
      Result : Detail_Vectors.Vector;
      Row    : Entity;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan details");
      while Entity_Tables.Has_Element (Cursor) loop
         Row := Entity_Tables.Element (Cursor);
         if Run_Id = 0 or else Row.Parent_Id = Run_Id then
            Result.Append
              (Detail_Info'(Id => Row.Id, Run_Id => Positive (Row.Parent_Id),
               Kind => To_Unbounded_String (S (Row.Kind)), State => To_Unbounded_String (S (Row.State)),
               Summary => To_Unbounded_String (S (Row.Payload))));
         end if;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance details");
      end loop;
      Require_OK (Database.Transactions.Commit (Tx), "complete details query");
      Detail_Sorting.Sort (Result);
      return Result;
   end Details;

   function Results (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector is
     (Details (Item, Indicator_Results_Table, Run_Id));

   function Measurements (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector is
     (Details (Item, Measurements_Table, Run_Id));

   function Findings (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector is
     (Details (Item, Findings_Table, Run_Id));

   function Executions (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector is
     (Details (Item, Executions_Table, Run_Id));

   function Events (Item : in out Store; Run_Id : Natural := 0) return Detail_Vectors.Vector is
     (Details (Item, Events_Table, Run_Id));

   procedure Add_Assessment_Alias (Item : in out Store; Run_Id : Positive; Name : String) is
      Event_Id : Positive := 1;
      Tx       : Database.Transactions.Transaction;
      Cursor   : Entity_Tables.Cursor;
      Run_Row  : Entity;
      Status   : Database.Status.Result;
   begin
      if not Assessment_Alias_Is_Valid (Name) then
         raise Storage_Error with
           "assessment alias must begin with a lowercase letter and contain only lowercase letters," &
           " digits, dots, underscores, or hyphens (maximum 64 characters)";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Id, Run_Row);
      Require_OK (Status, "load assessment for alias");
      if S (Run_Row.State) /= "completed" then
         raise Storage_Error with "only completed assessments may be aliased";
      end if;
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Events_Table), Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan assessment aliases");
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row : constant Entity := Entity_Tables.Element (Cursor);
         begin
            if S (Row.Kind) = "alias" and then S (Row.Payload) = Name then
               raise Storage_Error with "assessment alias already exists: " & Name;
            end if;
         end;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Events_Table), Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance assessment alias scan");
      end loop;
      Event_Id := Next_Id (Item, Events_Table);
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Events_Table),
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("alias"), State => WW ("alias"),
          Payload => WW (Name), Active => True));
      Require_OK (Status, "record assessment alias");
      Require_OK (Database.Transactions.Commit (Tx), "commit assessment alias");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Add_Assessment_Alias;

   procedure Interrupt_Assessment (Item : in out Store; Run_Id : Positive; Reason : String) is
      Event_Id : constant Positive := Next_Id (Item, Events_Table);
      Tx       : Database.Transactions.Transaction;
      Row      : Entity;
      Status   : Database.Status.Result;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Id, Row);
      Require_OK (Status, "load assessment to interrupt");
      if S (Row.State) /= "running" then
         Database.Transactions.Rollback (Tx);
         return;
      end if;
      Row.State := WW ("interrupted");
      Row.Active := False;
      Row.Payload := WW (With_Field (S (Row.Payload), "finished_at", UTC_Now));
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Assessments_Table), Row);
      Require_OK (Status, "mark assessment interrupted");
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Events_Table),
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("interrupted"), State => WW ("interrupted"),
          Payload => WW (Reason), Active => True));
      Require_OK (Status, "record assessment interruption");
      Trigger_Testing_Fault (Item, Assessment_Interruption_Commit);
      Require_OK (Database.Transactions.Commit (Tx), "commit assessment interruption");
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Interrupt_Assessment;

   procedure Recover (Item : in out Store; Count : out Natural) is
      Runs     : constant History_Vectors.Vector := History (Item);
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Count := 0;
      for Run of Runs loop
         if To_String (Run.Status) = "running" then
            declare
               Event_Id : constant Positive := Next_Id (Item, Events_Table);
            begin
               Database.Transactions.Begin_Write (Item.DB, Tx);
               Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Assessments_Table), Run.Id, Row);
               Require_OK (Status, "load abandoned assessment");
               Row.State := WW ("interrupted");
               Row.Active := False;
               Row.Payload := WW (With_Field (S (Row.Payload), "finished_at", UTC_Now));
               Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Assessments_Table), Row);
               Require_OK (Status, "mark assessment interrupted");
               Status := Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Events_Table),
                  (Id => Event_Id, Parent_Id => Run.Id, Kind => WW ("recovered"),
                   State => WW ("interrupted"), Payload => WW ("abandoned running assessment"), Active => True));
               Require_OK (Status, "record assessment recovery");
               Trigger_Testing_Fault (Item, Assessment_Recovery_Commit);
               Require_OK (Database.Transactions.Commit (Tx), "commit recovery");
               Count := Count + 1;
            exception
               when others =>  --  AQ: audited exception boundary
                  if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
                  raise;
            end;
         end if;
      end loop;
   end Recover;

   procedure Check (Item : in out Store; Limits : Integrity_Limits := (others => <>)) is separate;

   function Schema_Version (Item : in out Store) return Positive is
      Row    : Entity;
      Tx     : Database.Transactions.Transaction;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Metadata_Table), 1, Row);
      Require_OK (Status, "read schema version");
      Require_OK (Database.Transactions.Commit (Tx), "complete schema version read");
      return Positive'Value (S (Row.Payload));
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Schema_Version;

   procedure Testing_Set_Schema_Version (Item : in out Store; Version : Positive) is
      Row    : Entity;
      Tx     : Database.Transactions.Transaction;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Metadata_Table), 1, Row);
      Require_OK (Status, "read schema version for migration fixture");
      Row.Payload := WW (Ada.Strings.Fixed.Trim (Positive'Image (Version), Ada.Strings.Both));
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Metadata_Table), Row);
      Require_OK (Status, "write schema version migration fixture");
      Require_OK (Database.Transactions.Commit (Tx), "commit schema version migration fixture");
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Testing_Set_Schema_Version;

   procedure Testing_Inject_Next_Fault (Item : in out Store; Point : Testing_Fault_Point) is
   begin
      Item.Next_Testing_Fault := Point;
   end Testing_Inject_Next_Fault;

   procedure Testing_Use_Legacy_Evidence (Item : in out Store; Enabled : Boolean) is
   begin
      Item.Legacy_Testing_Evidence := Enabled;
   end Testing_Use_Legacy_Evidence;

   procedure Find_Testing_Evidence
     (Item   : in out Store;
      Tx     : in out Database.Transactions.Transaction;
      Table  : Positive;
      Run_Id : Positive;
      Target : out Entity;
      Found  : out Boolean)
   is
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
   begin
      Found := False;
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan rows to corrupt");
      while not Found and then Entity_Tables.Has_Element (Cursor) loop
         if Entity_Tables.Element (Cursor).Parent_Id = Run_Id then
            Target := Entity_Tables.Element (Cursor);
            Found := True;
         else
            Status := Entity_Tables.Next
              (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
            Require_OK (Status, "advance rows to corrupt");
         end if;
      end loop;
   end Find_Testing_Evidence;

   function Testing_Corruption_Table (Kind : Testing_Corruption) return Positive is
     (case Kind is
         when Duplicate_Result | Missing_Result | Inconsistent_Result | Contradictory_Result_Active |
           Nonterminal_Result | Noncanonical_Result | Noncanonical_Indicator =>
            Indicator_Results_Table,
         when Invalid_Measurement | Contradictory_Measurement_Active | Noncanonical_Measurement |
           Missing_Measurement_Semantics | Noncanonical_Measurement_Semantics => Measurements_Table,
         when Duplicate_Finding | Malformed_Finding | Noncanonical_Finding | Inactive_Finding |
           Mismatched_Finding => Findings_Table,
         when Malformed_Execution | Noncanonical_Execution => Executions_Table,
         when Invalid_Run_State | Unsupported_Evidence_Format | Malformed_Run_Timestamp |
           Incomplete_Run_Timestamps | Orphaned_Run_Finish | Inverted_Run_Timestamps =>
            Assessments_Table,
         when Missing_Terminal_Event => Events_Table,
         when Malformed_Metadata | Extra_Metadata => Metadata_Table);

   procedure Testing_Corrupt
     (Item : in out Store; Run_Id : Positive; Kind : Testing_Corruption) is separate;
end Ada_Quality.Storage;
