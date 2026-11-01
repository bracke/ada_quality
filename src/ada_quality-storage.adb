with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Strings.Wide_Wide_Unbounded;
with Database.Catalog;
with Database.Predicates;
with Database.Rows;
with Database.Status;
with Database.Tables;
with Database.Transactions;
with Database.Types;
with Database.Values;
with Project_Tools.Links;
with Project_Tools.Files;
with Project_Tools.TOML;

package body Ada_Quality.Storage is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Ada_Quality.Types;
   use type Project_Tools.TOML.String_Parse_Status;

   Projects_Table          : constant Positive := 1;
   Assessments_Table       : constant Positive := 2;
   Indicator_Results_Table : constant Positive := 3;
   Measurements_Table      : constant Positive := 4;
   Findings_Table          : constant Positive := 5;
   Executions_Table        : constant Positive := 6;
   Events_Table            : constant Positive := 7;
   Metadata_Table          : constant Positive := 8;
   Current_Schema_Version  : constant String := "2";
   Next_Testing_Fault      : Testing_Fault_Point := No_Testing_Fault;

   procedure Trigger_Testing_Fault (Point : Testing_Fault_Point) is
   begin
      if Next_Testing_Fault = Point then
         Next_Testing_Fault := No_Testing_Fault;
         raise Storage_Error with "injected storage fault at " & Testing_Fault_Point'Image (Point);
      end if;
   end Trigger_Testing_Fault;

   Table_Names : constant array (Positive range 1 .. 8) of access constant Wide_Wide_String :=
     [new Wide_Wide_String'("projects"), new Wide_Wide_String'("assessment_runs"),
      new Wide_Wide_String'("indicator_results"), new Wide_Wide_String'("measurements"),
      new Wide_Wide_String'("findings"), new Wide_Wide_String'("tool_executions"),
      new Wide_Wide_String'("assessment_events"), new Wide_Wide_String'("schema_metadata")];

   type Entity is record
      Id        : Positive;
      Parent_Id : Natural := 0;
      Kind      : Unbounded_Wide_Wide_String;
      State     : Unbounded_Wide_Wide_String;
      Payload   : Unbounded_Wide_Wide_String;
      Active    : Boolean := True;
   end record;

   package Entity_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Entity);

   function To_Row (Item : Entity) return Database.Rows.Row is
      Result : Database.Rows.Row;
   begin
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Item.Id)));
      Database.Rows.Append (Result, Database.Values.From_Integer (Integer (Item.Parent_Id)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Item.Kind)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Item.State)));
      Database.Rows.Append (Result, Database.Values.From_Text (To_Wide_Wide_String (Item.Payload)));
      Database.Rows.Append (Result, Database.Values.From_Boolean (Item.Active));
      return Result;
   end To_Row;

   function From_Row (Row : Database.Rows.Row) return Entity is
   begin
      return
        (Id => Positive (Database.Rows.Get (Row, 0).Int),
         Parent_Id => Natural (Database.Rows.Get (Row, 1).Int),
         Kind => Database.Rows.Get (Row, 2).Text,
         State => Database.Rows.Get (Row, 3).Text,
         Payload => Database.Rows.Get (Row, 4).Text,
         Active => Database.Rows.Get (Row, 5).Bool);
   end From_Row;

   function Key_Of (Item : Entity) return Positive is (Item.Id);
   function Key_Value (Key : Positive) return Database.Values.Value is
     (Database.Values.From_Integer (Integer (Key)));

   package Entity_Tables is new Database.Tables.Typed
     (Row_Type => Entity, Key_Type => Positive, To_Row => To_Row, From_Row => From_Row,
      Key_Of => Key_Of, Key_Value => Key_Value);

   function Project_Less (Left, Right : Project_Info) return Boolean is (Left.Id < Right.Id);
   package Project_Sorting is new Project_Vectors.Generic_Sorting ("<" => Project_Less);

   function History_Less (Left, Right : History_Item) return Boolean is (Left.Id < Right.Id);
   package History_Sorting is new History_Vectors.Generic_Sorting ("<" => History_Less);

   function Detail_Less (Left, Right : Detail_Info) return Boolean is (Left.Id < Right.Id);
   package Detail_Sorting is new Detail_Vectors.Generic_Sorting ("<" => Detail_Less);

   function Encode (Text : String) return Wide_Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text));

   function Decode (Text : Wide_Wide_String) return String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (Text));

   function WW (Text : String) return Unbounded_Wide_Wide_String is
     (To_Unbounded_Wide_Wide_String (Encode (Text)));

   function S (Text : Unbounded_Wide_Wide_String) return String is
     (Decode (To_Wide_Wide_String (Text)));

   function Field (Payload, Name : String) return String is
      Prefix : constant String := Name & "=";
      Start  : Natural := Payload'First;
   begin
      while Start <= Payload'Last loop
         declare
            Stop : Natural := Start;
         begin
            while Stop <= Payload'Last and then Payload (Stop) /= Character'Val (10) loop
               Stop := Stop + 1;
            end loop;
            if Stop > Start and then Stop - Start >= Prefix'Length and then
              Payload (Start .. Start + Prefix'Length - 1) = Prefix
            then
               return Payload (Start + Prefix'Length .. Stop - 1);
            end if;
            Start := Stop + 1;
         end;
      end loop;
      return "";
   end Field;

   function Assessment_Payload
     (Source_Fingerprint, Policy_Fingerprint, Toolchain_Fingerprint : String) return String is
     ("source=" & Source_Fingerprint & Character'Val (10) &
      "policy=" & Policy_Fingerprint & Character'Val (10) &
      "toolchain=" & Toolchain_Fingerprint);

   procedure Require_OK (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Storage_Error with Context & ": " & Decode (To_Wide_Wide_String (Status.Message));
      end if;
   end Require_OK;

   function New_Schema (Name : Wide_Wide_String) return Database.Schema.Table_Schema is
      Result : Database.Schema.Table_Schema;
   begin
      Result.Name := To_Unbounded_Wide_Wide_String (Name);
      Database.Schema.Add_Column (Result, "id", Database.Types.Integer_Value, False, True);
      Database.Schema.Add_Column (Result, "parent_id", Database.Types.Integer_Value, False);
      Database.Schema.Add_Column (Result, "kind", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "state", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "payload", Database.Types.Text_Value, False);
      Database.Schema.Add_Column (Result, "active", Database.Types.Boolean_Value, False);
      return Result;
   end New_Schema;

   procedure Register_Schemas (Item : in out Store) is
      Status : Database.Status.Result;
   begin
      for J in Item.Schemas'Range loop
         Item.Schemas (J) := New_Schema (Table_Names (J).all);
         Status := Entity_Tables.Register (Item.DB, Item.Schemas (J));
         Require_OK (Status, "register " & Decode (Table_Names (J).all));
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
         Trigger_Testing_Fault (Schema_Creation_Commit);
         Require_OK (Database.Transactions.Commit (Tx), "commit schema metadata");
      end;
   end Register_Schemas;

   procedure Load_Schemas (Item : in out Store) is
      Status : Database.Status.Result;
   begin
      for J in Item.Schemas'Range loop
         Status := Database.Catalog.Find_By_Name
           (Database.Catalog_State_Key (Item.DB), Table_Names (J).all, Item.Schemas (J));
         Require_OK (Status, "load " & Decode (Table_Names (J).all));
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
      elsif S (Row.Payload) = "1" then
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
         Row.Payload := WW (Current_Schema_Version);
         Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Metadata_Table), Row);
         Require_OK (Status, "migrate schema metadata from version 1");
         Trigger_Testing_Fault (Schema_Migration_Commit);
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

   function Next_Id (Item : in out Store; Table : Positive) return Positive is
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
      Max_Id : Natural := 0;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan table for next id");
      while Entity_Tables.Has_Element (Cursor) loop
         Max_Id := Natural'Max (Max_Id, Entity_Tables.Element (Cursor).Id);
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance table scan");
      end loop;
      Require_OK (Database.Transactions.Commit (Tx), "complete table scan");
      return Max_Id + 1;
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

   function Add_Project (Item : in out Store; Path : String) return Positive is
      Input_Is_Link : constant Boolean := Project_Tools.Links.Is_Link (Path);
      Canonical : constant String := Ada.Directories.Full_Name (Path);
      Existing  : constant Project_Vectors.Vector := Projects (Item, True);
      Id        : constant Positive := Next_Id (Item, Projects_Table);
      Manifest  : constant String := Canonical & "/alire.toml";
      Tx        : Database.Transactions.Transaction;
      Status    : Database.Status.Result;
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
         Name    : constant Project_Tools.TOML.String_Parse_Result :=
           Project_Tools.TOML.Parse_String_After (Content, "name", Content'First);
         Version : constant Project_Tools.TOML.String_Parse_Result :=
           Project_Tools.TOML.Parse_String_After (Content, "version", Content'First);
      begin
         if Name.Status /= Project_Tools.TOML.Parsed_String or else
           Version.Status /= Project_Tools.TOML.Parsed_String or else
           Length (Name.Value) = 0 or else Length (Version.Value) = 0
         then
            raise Storage_Error with "project has a malformed Alire manifest: " & Manifest;
         end if;
      end;
      for P of Existing loop
         if To_String (P.Path) = Canonical and then not P.Removed then
            raise Storage_Error with "project already registered:" & Positive'Image (P.Id);
         end if;
      end loop;
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
      Run_Id   : constant Positive := Next_Id (Item, Assessments_Table);
      Event_Id : constant Positive := Next_Id (Item, Events_Table);
      Tx       : Database.Transactions.Transaction;
      Status   : Database.Status.Result;
   begin
      if Registered.Removed or else not Registered.Enabled then
         raise Storage_Error with "assessment project must be active and enabled";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Assessments_Table),
         (Id => Run_Id, Parent_Id => Project_Id, Kind => WW ("assessment"), State => WW ("running"),
          Payload => WW (Assessment_Payload (Source_Fingerprint, Policy_Fingerprint, "")), Active => False));
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
      Trigger_Testing_Fault (Assessment_Start_Commit);
      Require_OK (Database.Transactions.Commit (Tx), "commit assessment start");
      return Run_Id;
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Start_Assessment;

   function Publish (Item : in out Store; Value : Assessment) return Positive is
      Run_Id    : constant Positive :=
        (if Value.Id = 0 then Next_Id (Item, Assessments_Table) else Positive (Value.Id));
      Result_Id : Natural := Next_Id (Item, Indicator_Results_Table);
      Measure_Id : Natural := Next_Id (Item, Measurements_Table);
      Finding_Id : Natural := Next_Id (Item, Findings_Table);
      Execution_Id : Natural := Next_Id (Item, Executions_Table);
      Event_Id   : constant Positive := Next_Id (Item, Events_Table);
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
      Database.Transactions.Begin_Write (Item.DB, Tx);
      if Value.Id = 0 then
         Insert
           (Assessments_Table,
            (Id => Run_Id, Parent_Id => Value.Project_Id, Kind => WW ("assessment"),
             State => WW (Assessment_Status_Image (Value.Status)),
             Payload => WW (Assessment_Payload
               (To_String (Value.Source_Fingerprint), To_String (Value.Policy_Fingerprint),
                To_String (Value.Toolchain_Fingerprint))),
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
              To_String (Value.Toolchain_Fingerprint)));
         Run_Row.Active := Value.Status = Assessment_Completed;
         Status := Entity_Tables.Update
           (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Row);
         if not Database.Status.Is_Ok (Status) then
            raise Storage_Error with "update running assessment";
         end if;
      end if;
      for R of Value.Results loop
         Insert
           (Indicator_Results_Table,
            (Id => Positive (Result_Id), Parent_Id => Run_Id, Kind => WW (Image (R.Indicator)),
             State => WW (Image (R.Execution) & "/" & Image (R.Compliance)),
             Payload => WW (To_String (R.Summary) & Character'Val (10) & To_String (R.Evidence)),
             Active => R.Compliance = Pass), "insert indicator result");
         Result_Id := Result_Id + 1;
         Insert
           (Measurements_Table,
            (Id => Positive (Measure_Id), Parent_Id => Run_Id, Kind => WW (Image (R.Indicator)),
             State => WW (Value_Kind'Image (R.Measurement.Kind)),
             Payload => WW (Image (R.Measurement)), Active => R.Execution = Succeeded), "insert measurement");
         Measure_Id := Measure_Id + 1;
         for F of R.Findings loop
            Insert
              (Findings_Table,
               (Id => Positive (Finding_Id), Parent_Id => Run_Id, Kind => WW (To_String (F.Fingerprint)),
                State => WW (Severity'Image (F.Level)),
                Payload => WW (To_String (F.Rule) & Character'Val (10) & To_String (F.Message)), Active => True),
               "insert finding");
            Finding_Id := Finding_Id + 1;
         end loop;
      end loop;
      for Execution of Value.Executions loop
         Insert
           (Executions_Table,
            (Id => Positive (Execution_Id), Parent_Id => Run_Id, Kind => WW (To_String (Execution.Tool)),
             State => WW (Image (Execution.Status)),
             Payload => WW
               ("command=" & To_String (Execution.Command) & Character'Val (10) &
                "exit_code=" & Integer'Image (Execution.Exit_Code) & Character'Val (10) &
                "output_digest=" & To_String (Execution.Output_Digest) & Character'Val (10) &
                "output_bytes=" & Natural'Image (Execution.Output_Bytes) & Character'Val (10) &
                "truncated=" & Boolean'Image (Execution.Truncated)),
             Active => Execution.Status = Tool_Completed),
            "insert tool execution");
         Execution_Id := Execution_Id + 1;
      end loop;
      Insert
        (Events_Table,
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("published"),
          State => WW (Assessment_Status_Image (Value.Status)), Payload => WW ("atomic publication"), Active => True),
         "insert event");
      Trigger_Testing_Fault (Assessment_Publication_Commit);
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
      Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Assessments_Table), Row);
      Require_OK (Status, "mark assessment interrupted");
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Events_Table),
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("interrupted"), State => WW ("interrupted"),
          Payload => WW (Reason), Active => True));
      Require_OK (Status, "record assessment interruption");
      Trigger_Testing_Fault (Assessment_Interruption_Commit);
      Require_OK (Database.Transactions.Commit (Tx), "commit assessment interruption");
   exception
      when others =>  --  AQ: audited exception boundary
         if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
         raise;
   end Interrupt_Assessment;

   procedure Recover (Item : in out Store; Count : out Natural) is
      Runs     : constant History_Vectors.Vector := History (Item);
      Event_Id : Natural := Next_Id (Item, Events_Table);
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Count := 0;
      for Run of Runs loop
         if To_String (Run.Status) = "running" then
            begin
               Database.Transactions.Begin_Write (Item.DB, Tx);
               Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Assessments_Table), Run.Id, Row);
               Require_OK (Status, "load abandoned assessment");
               Row.State := WW ("interrupted");
               Row.Active := False;
               Status := Entity_Tables.Update (Tx, Item.DB, Item.Schemas (Assessments_Table), Row);
               Require_OK (Status, "mark assessment interrupted");
               Status := Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Events_Table),
                  (Id => Positive (Event_Id), Parent_Id => Run.Id, Kind => WW ("recovered"),
                   State => WW ("interrupted"), Payload => WW ("abandoned running assessment"), Active => True));
               Require_OK (Status, "record assessment recovery");
               Trigger_Testing_Fault (Assessment_Recovery_Commit);
               Require_OK (Database.Transactions.Commit (Tx), "commit recovery");
               Event_Id := Event_Id + 1;
               Count := Count + 1;
            exception
               when others =>  --  AQ: audited exception boundary
                  if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
                  raise;
            end;
         end if;
      end loop;
   end Recover;

   procedure Check (Item : in out Store) is
      Status : Database.Status.Result;
      Row    : Entity;
      Tx     : Database.Transactions.Transaction;
   begin
      if not Item.Opened or else not Database.Is_Open (Item.DB) then
         raise Storage_Error with "database is not open";
      end if;
      if Database.Catalog.Table_Count (Database.Catalog_State_Key (Item.DB)) /= 8 then
         raise Storage_Error with "database must contain exactly eight logical tables";
      end if;
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Find (Tx, Item.DB, Item.Schemas (Metadata_Table), 1, Row);
      Require_OK (Status, "read schema version");
      Require_OK (Database.Transactions.Commit (Tx), "database integrity read");
      if S (Row.Payload) /= Current_Schema_Version then
         raise Storage_Error with "unsupported schema version";
      end if;
   end Check;

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

   procedure Testing_Inject_Next_Fault (Point : Testing_Fault_Point) is
   begin
      Next_Testing_Fault := Point;
   end Testing_Inject_Next_Fault;
end Ada_Quality.Storage;
