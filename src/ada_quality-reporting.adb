with Ada.Calendar.Formatting;
with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Indicators;
with Ada_Quality.Persistence;
with Database;
with Database.Catalog;
with Database.Predicates;
with Database.Schema;
with Database.Status;
with Database.Transactions;
with Interfaces;

package body Ada_Quality.Reporting is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Ada_Quality.Persistence;
   use Ada_Quality.Types;
   use type Ada.Directories.File_Kind;
   use type Database.Status_Code;
   use type Ada_Quality.History.Comparison_Status;
   use type Ada_Quality.History.Incompatibility;
   use type Interfaces.Unsigned_64;

   LF : constant Character := Character'Val (10);

   type Schema_Array is array (Positive range 1 .. Logical_Table_Count) of Database.Schema.Table_Schema;

   package Finding_Key_Sets is new Ada.Containers.Ordered_Sets
     (Element_Type => UString,
      "<" => Ada.Strings.Unbounded."<",
      "=" => Ada.Strings.Unbounded."=");

   --  Text helpers

   function Image (Item : Optional_Timestamp) return String is
   begin
      if not Item.Present then
         return "";
      end if;
      declare
         Raw : constant String :=
           Ada.Calendar.Formatting.Image (Item.Value, Include_Time_Fraction => False, Time_Zone => 0);
      begin
         return Raw (Raw'First .. Raw'First + 9) & "T" & Raw (Raw'First + 11 .. Raw'Last) & "Z";
      end;
   end Image;

   function Context_Of (Table : String; Id : Positive) return String is
     (Table & " row" & Positive'Image (Id));

   --  Enumeration decoding

   function Parse_Indicator (Text, Context : String) return Indicator_Id is
      Id : Indicator_Id;
   begin
      if not Ada_Quality.Indicators.Parse_Canonical (Text, Id) then
         raise Integrity_Error with Context & ": unknown indicator " & Text;
      end if;
      return Id;
   end Parse_Indicator;

   function Parse_Severity (Text, Context : String) return Severity is
      Value : Severity;
   begin
      if Decode_Severity (Text, Value) then return Value; end if;
      raise Integrity_Error with Context & ": unknown severity " & Text;
   end Parse_Severity;

   --  Snapshot loading

   function Message_Of (Status : Database.Status.Result) return String is
     (Decode (To_Wide_Wide_String (Status.Message)));

   procedure Raise_Open_Failure (Status : Database.Status.Result; Path : String) is
   begin
      case Status.Code is
         when Database.Lock_Error =>
            raise Busy_Error with "database is locked by another process: " & Path;
         when Database.Recovery_Required =>
            raise Integrity_Error with "database requires recovery by ada-quality before reporting: " & Path;
         when Database.Invalid_File | Database.Corrupt_File | Database.Corrupt_Index | Database.WAL_Corruption |
              Database.Corruption_Detected | Database.Serialization_Error =>
            raise Integrity_Error with "database is corrupt: " & Path & ": " & Message_Of (Status);
         when others =>
            raise Reporting_Error with "database cannot be opened read-only: " & Path & ": " & Message_Of (Status);
      end case;
   end Raise_Open_Failure;

   procedure Require_Read (Status : Database.Status.Result; Context : String) is
   begin
      if not Database.Status.Is_Ok (Status) then
         raise Reporting_Error with Context & ": " & Message_Of (Status);
      end if;
   end Require_Read;

   procedure Hash (State : in out Interfaces.Unsigned_64; Text : String) is
      Length_Image : constant String :=
        Ada.Strings.Fixed.Trim (Natural'Image (Text'Length), Ada.Strings.Both);
      Framed : constant String := Length_Image & ":" & Text;
   begin
      for C of Framed loop
         State := (State xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#0000_0100_0000_01B3#;
      end loop;
   end Hash;

   function Hex (Value : Interfaces.Unsigned_64) return String is
      Symbols : constant String := "0123456789abcdef";
      Result  : String (1 .. 16);
      Rest    : Interfaces.Unsigned_64 := Value;
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Symbols (Natural (Rest mod 16) + 1);
         Rest := Rest / 16;
      end loop;
      return Result;
   end Hex;

   type Entity_Table_Array is array (Positive range 1 .. Logical_Table_Count) of Entity_Vectors.Vector;

   procedure Read_Tables
     (Path : String; Limits : Load_Limits; Version : out Positive;
      Stats : out Snapshot_Statistics; Rows : out Entity_Table_Array)
   is
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Schemas : Schema_Array;
      Total_Rows : Natural := 0;
      Total_Text_Bytes : Long_Long_Integer := 0;

      function Text_Bytes (Row : Entity) return Long_Long_Integer is
        (Long_Long_Integer (S (Row.Kind)'Length) +
         Long_Long_Integer (S (Row.State)'Length) +
         Long_Long_Integer (S (Row.Payload)'Length));

      procedure Account (Row : Entity; Label : String) is
         Bytes : constant Long_Long_Integer := Text_Bytes (Row);
      begin
         if Total_Rows >= Limits.Max_Total_Rows then
            raise Limit_Error with
              "snapshot rows exceed the reporting limit of" & Positive'Image (Limits.Max_Total_Rows);
         elsif Bytes > Long_Long_Integer (Limits.Max_Text_Bytes) - Total_Text_Bytes then
            raise Limit_Error with
              Label & " exceed the reporting text limit of" & Positive'Image (Limits.Max_Text_Bytes) & " bytes";
         end if;
         Total_Rows := Total_Rows + 1;
         Total_Text_Bytes := Total_Text_Bytes + Bytes;
      end Account;

      procedure Scan (Table : Positive; Limit : Positive; Label : String) is
         Cursor : Entity_Tables.Cursor;
         Status : Database.Status.Result;
      begin
         Status := Entity_Tables.Scan
           (Tx, DB, Schemas (Table), Database.Predicates.True_Predicate, Cursor);
         Require_Read (Status, "scan " & Label);
         while Entity_Tables.Has_Element (Cursor) loop
            if Natural (Rows (Table).Length) >= Limit then
               raise Limit_Error with Label & " exceed the reporting limit of" & Positive'Image (Limit);
            end if;
            declare
               Row : constant Entity := Entity_Tables.Element (Cursor);
            begin
               Account (Row, Label);
               Rows (Table).Append (Row);
            end;
            Status := Entity_Tables.Next
              (Tx, DB, Schemas (Table), Database.Predicates.True_Predicate, Cursor);
            Require_Read (Status, "advance " & Label);
         end loop;
      end Scan;

      procedure Release is
      begin
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         if Database.Is_Open (DB) then
            Database.Close (DB);
         end if;
      end Release;

      Status : Database.Status.Result;

      procedure Open_Database is
      begin
         Database.Open_Read_Only (DB, Encode (Path));
         if not Database.Is_Open (DB) or else not Database.Last_Operation_Succeeded (DB) then
            Raise_Open_Failure (Database.Last_Result (DB), Path);
         end if;
         if Database.Catalog.Table_Count (Database.Catalog_State_Key (DB)) /= Logical_Table_Count then
            raise Schema_Error with "database must contain exactly eight logical tables: " & Path;
         end if;
         for Table in Schemas'Range loop
            Status := Database.Catalog.Find_By_Name
              (Database.Catalog_State_Key (DB), Table_Name (Table), Schemas (Table));
            if not Database.Status.Is_Ok (Status) then
               raise Schema_Error with "missing logical table " & Decode (Table_Name (Table)) & ": " & Path;
            end if;
         end loop;
      end Open_Database;

      procedure Load_Version is
         Cursor : Entity_Tables.Cursor;
      begin
         Database.Transactions.Begin_Read (DB, Tx);
         if not Database.Transactions.Is_Active (Tx) then
            raise Busy_Error with "read snapshot unavailable: " & Message_Of (Database.Transactions.Result (Tx));
         end if;
         Status := Entity_Tables.Scan
           (Tx, DB, Schemas (Metadata_Table), Database.Predicates.True_Predicate, Cursor);
         Require_Read (Status, "scan schema metadata");
         while Entity_Tables.Has_Element (Cursor) loop
            if not Rows (Metadata_Table).Is_Empty then
               raise Integrity_Error with "database must contain exactly one schema metadata row: " & Path;
            end if;
            declare
               Row : constant Entity := Entity_Tables.Element (Cursor);
            begin
               Account (Row, "schema metadata");
               Rows (Metadata_Table).Append (Row);
            end;
            Status := Entity_Tables.Next
              (Tx, DB, Schemas (Metadata_Table), Database.Predicates.True_Predicate, Cursor);
            Require_Read (Status, "advance schema metadata");
         end loop;
         if Rows (Metadata_Table).Is_Empty then
            raise Schema_Error with "schema version metadata is missing: " & Path;
         end if;
         declare
            Meta : constant Entity := Rows (Metadata_Table).First_Element;
            Text : constant String := S (Meta.Payload);
         begin
            if not Metadata_Row_Is_Valid (Meta) then
               raise Integrity_Error with "schema metadata is malformed: " & Path;
            end if;
            Version := Positive'Value (Text);
            if Ada.Strings.Fixed.Trim (Positive'Image (Version), Ada.Strings.Both) /= Text then
               raise Constraint_Error;
            end if;
         exception
            when Constraint_Error =>
               raise Schema_Error with "schema version metadata is malformed: " & Text;
         end;
         if Version /= Supported_Schema then
            raise Schema_Error with
              "unsupported schema version" & Positive'Image (Version) & "; reporting requires version" &
              Positive'Image (Supported_Schema) &
              (if Version < Supported_Schema then " (open the database with ada-quality to migrate it)" else "");
         end if;
      end Load_Version;

      procedure Load_Rows is
      begin
         Scan (Projects_Table, Limits.Max_Projects, "projects");
         Scan (Assessments_Table, Limits.Max_Runs, "assessment runs");
         Scan (Indicator_Results_Table, Limits.Max_Results, "indicator results");
         Scan (Measurements_Table, Limits.Max_Measurements, "measurements");
         Scan (Findings_Table, Limits.Max_Findings, "findings");
         Scan (Executions_Table, Limits.Max_Executions, "tool executions");
         Scan (Events_Table, Limits.Max_Events, "assessment events");
      end Load_Rows;
   begin
      Version := Supported_Schema;
      Stats := (Row_Limit => Limits.Max_Total_Rows, Text_Limit => Limits.Max_Text_Bytes, others => <>);
      Open_Database;
      Load_Version;
      Load_Rows;
      Stats.Projects := Natural (Rows (Projects_Table).Length);
      Stats.Assessments := Natural (Rows (Assessments_Table).Length);
      Stats.Results := Natural (Rows (Indicator_Results_Table).Length);
      Stats.Measurements := Natural (Rows (Measurements_Table).Length);
      Stats.Findings := Natural (Rows (Findings_Table).Length);
      Stats.Executions := Natural (Rows (Executions_Table).Length);
      Stats.Events := Natural (Rows (Events_Table).Length);
      Stats.Total_Rows := Total_Rows;
      Stats.Text_Bytes := Total_Text_Bytes;
      Require_Read (Database.Transactions.Commit (Tx), "complete read snapshot");
      Database.Close (DB);
   exception
      when others =>  --  AQ: audited exception boundary
         Release;
         raise;
   end Read_Tables;

   function Less (Left, Right : Entity) return Boolean is (Left.Id < Right.Id);
   package Entity_Sorting is new Entity_Vectors.Generic_Sorting ("<" => Less);

   function To_Detail (Row : Entity) return Ada_Quality.History_Data.Detail_Info is
     (Id => Row.Id, Run_Id => Positive (Row.Parent_Id),
      Kind => To_Unbounded_String (S (Row.Kind)), State => To_Unbounded_String (S (Row.State)),
      Summary => To_Unbounded_String (S (Row.Payload)));

   procedure Decode_Snapshot (Item : in out Session; Rows : in out Entity_Table_Array) is separate;

   function Decode_Assessment
     (Item : Session; Run_Id : Positive; Allow_Terminal : Boolean) return Assessment_Record;

   procedure Validate_Snapshot (Item : in out Session) is separate;

   procedure Open (Item : in out Session; Path : String; Limits : Load_Limits := (others => <>)) is
      Rows : Entity_Table_Array;
   begin
      Close (Item);
      if Path'Length = 0 then
         raise Reporting_Error with "database path is empty";
      elsif not Ada.Directories.Exists (Path) then
         raise Reporting_Error with "database not found: " & Path;
      elsif Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File then
         raise Reporting_Error with "database path is not a regular file: " & Path;
      end if;
      Read_Tables (Path, Limits, Item.Version, Item.Stats, Rows);
      Decode_Snapshot (Item, Rows);
      Item.Opened := True;
      Validate_Snapshot (Item);
   exception
      when Reporting_Error | Schema_Error | Integrity_Error | Busy_Error | Limit_Error =>
         Close (Item);
         raise;
      when Error : others =>  --  AQ: audited exception boundary
         Close (Item);
         raise Integrity_Error with
           "database evidence cannot be decoded: " & Path & ": " & Ada.Exceptions.Exception_Message (Error);
   end Open;

   procedure Close (Item : in out Session) is
   begin
      Item.Opened := False;
      Item.Version := Supported_Schema;
      Item.Identity := Null_Unbounded_String;
      Item.Stats := (others => <>);
      Item.All_Projects.Clear;
      Item.All_Runs.Clear;
      Item.Project_Index.Clear;
      Item.Run_Index.Clear;
      Item.Payloads.Clear;
      Item.Project_Runs.Clear;
      Item.Project_Histories.Clear;
      Item.Details.Clear;
   end Close;

   overriding procedure Finalize (Item : in out Session) is
   begin
      Close (Item);
   end Finalize;

   function Is_Open (Item : Session) return Boolean is (Item.Opened);

   procedure Require_Open (Item : Session) is
   begin
      if not Item.Opened then
         raise Reporting_Error with "reporting session is not open";
      end if;
   end Require_Open;

   --  Queries

   function Projects (Item : Session; Include_Removed : Boolean := False) return Project_Vectors.Vector is
      Result : Project_Vectors.Vector;
   begin
      Require_Open (Item);
      for Project of Item.All_Projects loop
         if Include_Removed or else not Project.Removed then
            Result.Append (Project);
         end if;
      end loop;
      return Result;
   end Projects;

   function Project (Item : Session; Project_Id : Positive) return Project_Record is
   begin
      Require_Open (Item);
      if not Item.Project_Index.Contains (Project_Id) then
         raise Reporting_Error with "project not found:" & Positive'Image (Project_Id);
      end if;
      return Item.All_Projects (Item.Project_Index.Element (Project_Id));
   end Project;

   function Runs (Item : Session; Project_Id : Natural := 0) return Run_Vectors.Vector is
      Result : Run_Vectors.Vector;
   begin
      Require_Open (Item);
      if Project_Id = 0 then
         return Item.All_Runs;
      elsif Item.Project_Runs.Contains (Project_Id) then
         for Position of Item.Project_Runs.Element (Project_Id) loop
            Result.Append (Item.All_Runs (Position));
         end loop;
      end if;
      return Result;
   end Runs;

   procedure Visit_Projects
     (Item            : Session;
      Include_Removed : Boolean := False;
      Process         : not null access procedure (Project : Project_Record))
   is
   begin
      Require_Open (Item);
      for Project_Item of Item.All_Projects loop
         if Include_Removed or else not Project_Item.Removed then
            Process (Project_Item);
         end if;
      end loop;
   end Visit_Projects;

   procedure Visit_Runs
     (Item       : Session;
      Project_Id : Natural := 0;
      Descending : Boolean := False;
      Process    : not null access procedure (Run : Run_Record))
   is
      procedure Visit_Positions (Positions : History_Position_Vectors.Vector) is
      begin
         if Descending then
            for Index in reverse Positions.First_Index .. Positions.Last_Index loop
               Process (Item.All_Runs (Positions (Index)));
            end loop;
         else
            for Position of Positions loop
               Process (Item.All_Runs (Position));
            end loop;
         end if;
      end Visit_Positions;
   begin
      Require_Open (Item);
      if Project_Id > 0 then
         if Item.Project_Runs.Contains (Project_Id) then
            Visit_Positions (Item.Project_Runs.Element (Project_Id));
         end if;
      elsif Descending then
         for Index in reverse Item.All_Runs.First_Index .. Item.All_Runs.Last_Index loop
            Process (Item.All_Runs (Index));
         end loop;
      else
         for Run_Item of Item.All_Runs loop
            Process (Run_Item);
         end loop;
      end if;
   end Visit_Runs;

   function Evidence_Run
     (Item : Session; Run_Id : Positive; Allow_Terminal : Boolean) return Run_Record
   is separate;

   function Decode_Measurement
     (Row : Ada_Quality.History_Data.Detail_Info;
      Context : String;
      Require_Versioned : Boolean) return Measurement_Value
   is
      Value : Measurement_Value;
   begin
      if not Ada_Quality.Persistence.Decode_Measurement
        (To_String (Row.State), To_String (Row.Summary), Value, Require_Versioned)
      then
         raise Integrity_Error with Context & ": invalid or noncanonical measurement";
      end if;
      return Value;
   end Decode_Measurement;

   function Decode_Finding
     (Row : Ada_Quality.History_Data.Detail_Info; Format : Evidence_Format) return Finding
   is
      Context     : constant String := Context_Of ("finding", Row.Id);
      Fingerprint : constant String := To_String (Row.Kind);
      Payload     : constant String := To_String (Row.Summary);
      Result      : Finding;
   begin
      if Fingerprint'Length = 0 then
         raise Integrity_Error with Context & ": empty fingerprint";
      end if;
      Result.Fingerprint := Row.Kind;
      Result.Level := Parse_Severity (To_String (Row.State), Context);
      case Format is
         when Lossless_Evidence =>
            declare
               Value : Finding;
            begin
               if not Decode_Finding_Payload (Payload, Value) then
                  raise Integrity_Error with Context & ": invalid or noncanonical finding payload";
               elsif not Ada_Quality.Finding_Identity.Matches
                 (Fingerprint, Value.Indicator, To_String (Value.Rule),
                  To_String (Value.Relative_Path), To_String (Value.Message))
               then
                  raise Integrity_Error with Context & ": fingerprint contradicts finding payload";
               end if;
               Value.Fingerprint := Row.Kind;
               Value.Level := Result.Level;
               return Value;
            end;
         when Legacy_Evidence =>
            declare
               Split : constant Natural := Ada.Strings.Fixed.Index (Payload, [LF]);
            begin
               if Split = 0 or else Fingerprint'Length < 7 or else Fingerprint (Fingerprint'First + 6) /= ':' then
                  raise Integrity_Error with Context & ": malformed legacy finding";
               end if;
               Result.Indicator :=
                 Parse_Indicator (Fingerprint (Fingerprint'First .. Fingerprint'First + 5), Context);
               Result.Rule := To_Unbounded_String (Payload (Payload'First .. Split - 1));
               Result.Message := To_Unbounded_String (Payload (Split + 1 .. Payload'Last));
            end;
      end case;
      return Result;
   end Decode_Finding;

   function Decode_Assessment
     (Item : Session; Run_Id : Positive; Allow_Terminal : Boolean) return Assessment_Record
   is separate;


   function Read_Assessment (Item : Session; Run_Id : Positive) return Assessment_Record is
      Run : constant Run_Record := Evidence_Run (Item, Run_Id, Allow_Terminal => False);
   begin
      return Decode_Assessment (Item, Run.Id, Allow_Terminal => False);
   end Read_Assessment;

   function Supported_Schema_Version (Item : Session) return Positive is
   begin
      Require_Open (Item);
      return Item.Version;
   end Supported_Schema_Version;

   function Snapshot_Identity (Item : Session) return String is
   begin
      Require_Open (Item);
      return To_String (Item.Identity);
   end Snapshot_Identity;

   function Statistics (Item : Session) return Snapshot_Statistics is
   begin
      Require_Open (Item);
      return Item.Stats;
   end Statistics;

   function Aliases (Item : Session; Run_Id : Natural := 0) return Alias_Vectors.Vector is
      Result : Alias_Vectors.Vector;

      procedure Append_Alias (Value : Assessment_Alias) is
      begin
         Result.Append (Value);
      end Append_Alias;
   begin
      Visit_Aliases (Item, Run_Id, Append_Alias'Access);
      return Result;
   end Aliases;

   procedure Visit_Aliases
     (Item    : Session;
      Run_Id  : Natural := 0;
      Process : not null access procedure (Value : Assessment_Alias))
   is
   begin
      Require_Open (Item);
      if Run_Id > 0 and then not Item.Run_Index.Contains (Positive (Run_Id)) then
         raise Reporting_Error with "assessment not found:" & Natural'Image (Run_Id);
      end if;
      for Run of Item.All_Runs loop
         if Run_Id = 0 or else Run.Id = Run_Id then
            declare
               Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
            begin
               for Event of Group.Events loop
                  if To_String (Event.Kind) = "alias" then
                     Process
                       (Assessment_Alias'
                          (Name => Event.Summary, Run_Id => Run.Id, Event_Id => Event.Id));
                  end if;
               end loop;
            end;
         end if;
      end loop;
   end Visit_Aliases;

   function Resolve_Assessment (Item : Session; Reference : String) return Positive is
   begin
      Require_Open (Item);
      begin
         declare
            Id : constant Positive := Positive'Value (Reference);
         begin
            if not Item.Run_Index.Contains (Id) then
               raise Reporting_Error with "assessment not found: " & Reference;
            end if;
            return Id;
         end;
      exception
         when Constraint_Error => null;
      end;
      if not Assessment_Alias_Is_Valid (Reference) then
         raise Reporting_Error with "invalid assessment reference: " & Reference;
      end if;
      for Candidate of Aliases (Item) loop
         if To_String (Candidate.Name) = Reference then
            return Candidate.Run_Id;
         end if;
      end loop;
      raise Reporting_Error with "assessment alias not found: " & Reference;
   end Resolve_Assessment;

   function History_Items
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.History_Data.History_Vectors.Vector
   is
      Result : Ada_Quality.History_Data.History_Vectors.Vector;
   begin
      Require_Open (Item);
      if Project_Id = 0 then
         return Item.Payloads;
      elsif Item.Project_Histories.Contains (Project_Id) then
         for Position of Item.Project_Histories.Element (Project_Id) loop
            Result.Append (Item.Payloads (Position));
         end loop;
         return Result;
      else
         return Ada_Quality.History_Data.History_Vectors.Empty_Vector;
      end if;
   end History_Items;

   function Select_Project_Comparison
     (Item : Session; Project_Id : Positive) return Ada_Quality.History.Comparison_Selection is
     (Ada_Quality.History.Select_Comparison (History_Items (Item, Project_Id)));

   --  Select and compare the last assessment of Runs, an ordered project history.
   function Compare_Runs
     (Item : Session; Project_Id : Positive; Runs : Ada_Quality.History_Data.History_Vectors.Vector)
      return Project_Comparison
   is
      Selection : constant Ada_Quality.History.Comparison_Selection :=
        Ada_Quality.History.Select_Comparison (Runs);
      Result : Project_Comparison :=
        (Project_Id => Project_Id, Selection => Selection, Changes => <>);

      function Find_Run (Id : Positive) return Ada_Quality.History_Data.History_Item is
      begin
         for Run of Runs loop
            if Run.Id = Id then
               return Run;
            end if;
         end loop;
         raise Integrity_Error with "selected assessment is absent from project history";
      end Find_Run;
   begin
      if Selection.Status /= Ada_Quality.History.Comparison_Available then
         return Result;
      end if;
      declare
         Current : constant Ada_Quality.History_Data.History_Item :=
           Find_Run (Positive (Selection.Current_Id));
         Baseline : constant Ada_Quality.History_Data.History_Item :=
           Find_Run (Positive (Selection.Baseline_Id));
         Older_Findings : Ada_Quality.History.Finding_Index;
      begin
         for Run of Runs loop
            exit when Run.Id = Baseline.Id;
            if Ada_Quality.History.Compatible (Run, Current) then
               declare
                  Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
               begin
                  Ada_Quality.History.Include_Findings (Older_Findings, Group.Findings);
               end;
            end if;
         end loop;
         declare
            Baseline_Group : Detail_Group renames Item.Details.Constant_Reference (Baseline.Id);
            Current_Group  : Detail_Group renames Item.Details.Constant_Reference (Current.Id);
         begin
            Result.Changes := Ada_Quality.History.Compare
              (Baseline, Current,
               Baseline_Group.Results, Current_Group.Results,
               Baseline_Group.Measurements, Current_Group.Measurements,
               Baseline_Group.Findings, Current_Group.Findings, Older_Findings);
         end;
      end;
      return Result;
   end Compare_Runs;

   function Compare_Project (Item : Session; Project_Id : Positive) return Project_Comparison is
     (Compare_Runs (Item, Project_Id, History_Items (Item, Project_Id)));

   function Compare_Project
     (Item : Session; Project_Id : Positive; Current_Id : Positive) return Project_Comparison
   is
      Through : Ada_Quality.History_Data.History_Vectors.Vector;
   begin
      for Run of History_Items (Item, Project_Id) loop
         if Run.Id <= Current_Id then
            Through.Append (Run);
         end if;
      end loop;
      return Compare_Runs (Item, Project_Id, Through);
   end Compare_Project;

   function Compare_Assessments
     (Item : Session; Baseline_Id, Current_Id : Positive) return Project_Comparison
   is
      function Selected_Run (Run_Id : Positive) return Run_Record is
      begin
         Require_Open (Item);
         if not Item.Run_Index.Contains (Run_Id) then
            raise Reporting_Error with "assessment not found:" & Positive'Image (Run_Id);
         end if;
         return Item.All_Runs (Item.Run_Index.Element (Run_Id));
      end Selected_Run;

      Baseline_Run : constant Run_Record := Selected_Run (Baseline_Id);
      Current_Run  : constant Run_Record := Selected_Run (Current_Id);
      Runs         : constant Ada_Quality.History_Data.History_Vectors.Vector :=
        History_Items (Item, Current_Run.Project_Id);
      Selection    : constant Ada_Quality.History.Comparison_Selection :=
        (Status => Ada_Quality.History.No_Compatible_Baseline,
         Current_Id => Current_Id, Baseline_Id => Baseline_Id, Policy_Changed => False);
      Result       : Project_Comparison :=
        (Project_Id => Current_Run.Project_Id, Selection => Selection, Changes => <>);

      function Find_Run (Id : Positive) return Ada_Quality.History_Data.History_Item is
      begin
         for Run of Runs loop
            if Run.Id = Id then
               return Run;
            end if;
         end loop;
         raise Integrity_Error with "selected assessment is absent from project history";
      end Find_Run;
   begin
      if Baseline_Run.Project_Id /= Current_Run.Project_Id then
         raise Reporting_Error with "selected assessments belong to different projects";
      elsif Baseline_Id >= Current_Id then
         raise Reporting_Error with "baseline assessment must precede current assessment";
      elsif Current_Run.State /= Assessment_Completed then
         Result.Selection.Status := Ada_Quality.History.Current_Incomplete;
         return Result;
      elsif Baseline_Run.State /= Assessment_Completed then
         Result.Selection.Status := Ada_Quality.History.No_Completed_Baseline;
         return Result;
      end if;

      declare
         Baseline : constant Ada_Quality.History_Data.History_Item := Find_Run (Baseline_Id);
         Current  : constant Ada_Quality.History_Data.History_Item := Find_Run (Current_Id);
      begin
         if Ada_Quality.History.Compatible (Baseline, Current) then
            Result.Selection.Status := Ada_Quality.History.Comparison_Available;
         elsif Ada_Quality.History.Policy_Comparable (Baseline, Current) then
            Result.Selection.Status := Ada_Quality.History.Comparison_Available;
            Result.Selection.Policy_Changed := True;
         elsif Ada_Quality.History.Incompatibility_Of (Baseline, Current) =
           Ada_Quality.History.Toolchain_Changed
         then
            Result.Selection.Status := Ada_Quality.History.Toolchain_Changed;
            return Result;
         else
            return Result;
         end if;

         declare
            Older_Findings : Ada_Quality.History.Finding_Index;
            Baseline_Group : Detail_Group renames Item.Details.Constant_Reference (Baseline_Id);
            Current_Group  : Detail_Group renames Item.Details.Constant_Reference (Current_Id);
         begin
            for Run of Runs loop
               exit when Run.Id = Baseline_Id;
               if Ada_Quality.History.Compatible (Run, Current) then
                  declare
                     Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
                  begin
                     Ada_Quality.History.Include_Findings (Older_Findings, Group.Findings);
                  end;
               end if;
            end loop;
            Result.Changes := Ada_Quality.History.Compare
              (Baseline, Current,
               Baseline_Group.Results, Current_Group.Results,
               Baseline_Group.Measurements, Current_Group.Measurements,
               Baseline_Group.Findings, Current_Group.Findings, Older_Findings);
         end;
      end;
      return Result;
   end Compare_Assessments;

   function Read_History_Evidence (Item : Session; Run_Id : Positive) return History_Evidence is
      Validated : constant Run_Record := Evidence_Run (Item, Run_Id, Allow_Terminal => False);
      Group     : Detail_Group renames Item.Details.Constant_Reference (Validated.Id);
   begin
      return (Results => Group.Results, Measurements => Group.Measurements, Findings => Group.Findings);
   end Read_History_Evidence;

   function All_Measurements
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.History_Data.Detail_Vectors.Vector
   is
      Result : Ada_Quality.History_Data.Detail_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         if Run.State = Assessment_Completed and then (Project_Id = 0 or else Run.Project_Id = Project_Id) then
            declare
               Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
            begin
               Result.Append (Group.Measurements);
            end;
         end if;
      end loop;
      return Result;
   end All_Measurements;

   function All_Persisted_Measurements
     (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector
   is
      Result : Ada_Quality.History_Data.Detail_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         declare
            Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
         begin
            Result.Append (Group.Measurements);
         end;
      end loop;
      return Result;
   end All_Persisted_Measurements;

   function All_Results (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector is
      Result : Ada_Quality.History_Data.Detail_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         declare
            Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
         begin
            Result.Append (Group.Results);
         end;
      end loop;
      return Result;
   end All_Results;

   function All_Findings (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector is
      Result : Ada_Quality.History_Data.Detail_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         declare
            Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
         begin
            Result.Append (Group.Findings);
         end;
      end loop;
      return Result;
   end All_Findings;

   function All_Executions (Item : Session) return Execution_Vectors.Vector is
      Result : Execution_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         declare
            Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
         begin
            Result.Append (Group.Executions);
         end;
      end loop;
      return Result;
   end All_Executions;

   function All_Events (Item : Session) return Ada_Quality.History_Data.Detail_Vectors.Vector is
      Result : Ada_Quality.History_Data.Detail_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         declare
            Group : Detail_Group renames Item.Details.Constant_Reference (Run.Id);
         begin
            Result.Append (Group.Events);
         end;
      end loop;
      return Result;
   end All_Events;

   procedure Require_Run (Item : Session; Run_Id : Positive) is
   begin
      Require_Open (Item);
      if not Item.Details.Contains (Run_Id) then
         raise Reporting_Error with "assessment not found:" & Positive'Image (Run_Id);
      end if;
   end Require_Run;

   function Results
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector
   is
   begin
      Require_Run (Item, Run_Id);
      declare
         Group : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
      begin
         return Group.Results;
      end;
   end Results;

   function Measurements
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector
   is
   begin
      Require_Run (Item, Run_Id);
      declare
         Group : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
      begin
         return Group.Measurements;
      end;
   end Measurements;

   function Findings
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector
   is
   begin
      Require_Run (Item, Run_Id);
      declare
         Group : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
      begin
         return Group.Findings;
      end;
   end Findings;

   function Executions
     (Item : Session; Run_Id : Positive) return Execution_Vectors.Vector
   is
   begin
      Require_Run (Item, Run_Id);
      declare
         Group : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
      begin
         return Group.Executions;
      end;
   end Executions;

   function Events
     (Item : Session; Run_Id : Positive) return Ada_Quality.History_Data.Detail_Vectors.Vector
   is
   begin
      Require_Run (Item, Run_Id);
      declare
         Group : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
      begin
         return Group.Events;
      end;
   end Events;

   procedure Visit_Details
     (Item    : Session;
      Run_Id  : Positive;
      Kind    : Detail_Collection;
      Process : not null access procedure (Row : Ada_Quality.History_Data.Detail_Info))
   is
   begin
      Require_Run (Item, Run_Id);
      declare
         Group : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
      begin
         case Kind is
            when Result_Details =>
               for Row of Group.Results loop Process (Row); end loop;
            when Measurement_Details =>
               for Row of Group.Measurements loop Process (Row); end loop;
            when Finding_Details =>
               for Row of Group.Findings loop Process (Row); end loop;
            when Event_Details =>
               for Row of Group.Events loop Process (Row); end loop;
         end case;
      end;
   end Visit_Details;

   procedure Visit_Executions
     (Item    : Session;
      Run_Id  : Positive;
      Process : not null access procedure (Row : Execution_Record))
   is
   begin
      Require_Run (Item, Run_Id);
      declare
         Group : Detail_Group renames Item.Details.Constant_Reference (Run_Id);
      begin
         for Row of Group.Executions loop Process (Row); end loop;
      end;
   end Visit_Executions;
end Ada_Quality.Reporting;
