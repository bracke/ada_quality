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
with Database.Catalog;
with Database.Backup;
with Database.Export;
with Database.Predicates;
with Database.Restore;
with Database.Status;
with Database.Transactions;
with Database.Vacuum;
with Project_Tools.Links;
with Project_Tools.Files;

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
      elsif S (Row.Payload) in "1" | "2" | "3" then
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
         --  Version 3 adds run timestamps and lossless child payloads for new runs only. Version 4 adds an alias
         --  event vocabulary. Both transitions leave existing evidence rows byte-identical.
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
            Result.Append
              (Project_Info'(Id => Row.Id, Path => To_Unbounded_String (S (Row.Payload)),
               Enabled => Row.Active, Removed => S (Row.State) = "removed"));
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
      return (Id => Row.Id, Path => To_Unbounded_String (S (Row.Payload)),
              Enabled => Row.Active, Removed => S (Row.State) = "removed");
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
          Payload => WW (Canonical), Active => True));
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
      Row.Payload := WW (Canonical);
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Projects_Table), Row);
      if not Database.Status.Is_Ok (Status) then
         Database.Transactions.Rollback (Tx);
         Require_OK (Status, "relocate project");
      end if;
      Require_OK (Database.Transactions.Commit (Tx), "commit project relocation");
   end Relocate_Project;

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
