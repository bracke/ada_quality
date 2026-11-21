with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Indicators;
with Ada_Quality.Persistence;
with Database.Catalog;
with Database.Predicates;
with Database.Transactions;

package body Ada_Quality.Storage is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Ada_Quality.Persistence;
   use Ada_Quality.Types;

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

   function Assessment_Status_Image (Value : Assessment_Status) return String is
   begin
      case Value is
         when Assessment_Running => return "running";
         when Assessment_Completed => return "completed";
         when Assessment_Invalid => return "invalid";
         when Assessment_Interrupted => return "interrupted";
      end case;
   end Assessment_Status_Image;

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
