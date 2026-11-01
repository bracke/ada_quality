with Ada.Calendar.Formatting;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Wide_Wide_Unbounded;
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
   use type Interfaces.Unsigned_64;

   LF : constant Character := Character'Val (10);

   type Schema_Array is array (Positive range 1 .. Logical_Table_Count) of Database.Schema.Table_Schema;

   ------------------------------------------------------------------------------------------------------------------
   --  Text helpers
   ------------------------------------------------------------------------------------------------------------------

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

   function Parse_Timestamp (Text : String; Context : String) return Optional_Timestamp is
      function Digits_At (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               raise Integrity_Error with Context & ": malformed timestamp " & Text;
            end if;
            Result := Result * 10 + (Character'Pos (Text (Index)) - Character'Pos ('0'));
         end loop;
         return Result;
      end Digits_At;
   begin
      if Text'Length = 0 then
         return (Present => False);
      elsif Text'Length /= 20 or else Text (Text'First + 4) /= '-' or else Text (Text'First + 7) /= '-' or else
        Text (Text'First + 10) /= 'T' or else Text (Text'First + 13) /= ':' or else
        Text (Text'First + 16) /= ':' or else Text (Text'Last) /= 'Z'
      then
         raise Integrity_Error with Context & ": malformed timestamp " & Text;
      end if;
      declare
         F : constant Positive := Text'First;
      begin
         return
           (Present => True,
            Value   => Ada.Calendar.Formatting.Time_Of
              (Year => Ada.Calendar.Year_Number (Digits_At (F, F + 3)),
               Month => Ada.Calendar.Month_Number (Digits_At (F + 5, F + 6)),
               Day => Ada.Calendar.Day_Number (Digits_At (F + 8, F + 9)),
               Hour => Ada.Calendar.Formatting.Hour_Number (Digits_At (F + 11, F + 12)),
               Minute => Ada.Calendar.Formatting.Minute_Number (Digits_At (F + 14, F + 15)),
               Second => Ada.Calendar.Formatting.Second_Number (Digits_At (F + 17, F + 18)),
               Time_Zone => 0));
      end;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         raise Integrity_Error with Context & ": invalid timestamp " & Text;
   end Parse_Timestamp;

   function Context_Of (Table : String; Id : Positive) return String is
     (Table & " row" & Positive'Image (Id));

   --  Return the value of a lossless field, which must be present and well formed.
   function Required_Field (Payload, Name, Context : String) return String is
      Valid : Boolean;
   begin
      if not Has_Field (Payload, Name) then
         raise Integrity_Error with Context & ": missing field " & Name;
      end if;
      declare
         Value : constant String := Unescape (Field (Payload, Name), Valid);
      begin
         if not Valid then
            raise Integrity_Error with Context & ": malformed field " & Name;
         end if;
         return Value;
      end;
   end Required_Field;

   ------------------------------------------------------------------------------------------------------------------
   --  Enumeration decoding
   ------------------------------------------------------------------------------------------------------------------

   function Parse_Indicator (Text, Context : String) return Indicator_Id is
      Id : Indicator_Id;
   begin
      if not Ada_Quality.Indicators.Parse (Text, Id) or else Image (Id) /= Text then
         raise Integrity_Error with Context & ": unknown indicator " & Text;
      end if;
      return Id;
   end Parse_Indicator;

   function Parse_Execution (Text, Context : String) return Execution_Status is
   begin
      for Value in Execution_Status loop
         if Image (Value) = Text then return Value; end if;
      end loop;
      raise Integrity_Error with Context & ": unknown execution state " & Text;
   end Parse_Execution;

   function Parse_Compliance (Text, Context : String) return Compliance_Status is
   begin
      for Value in Compliance_Status loop
         if Image (Value) = Text then return Value; end if;
      end loop;
      raise Integrity_Error with Context & ": unknown compliance state " & Text;
   end Parse_Compliance;

   function Parse_Severity (Text, Context : String) return Severity is
   begin
      for Value in Severity loop
         if Severity'Image (Value) = Text then return Value; end if;
      end loop;
      raise Integrity_Error with Context & ": unknown severity " & Text;
   end Parse_Severity;

   function Parse_Value_Kind (Text, Context : String) return Value_Kind is
   begin
      for Value in Value_Kind loop
         if Value_Kind'Image (Value) = Text then return Value; end if;
      end loop;
      raise Integrity_Error with Context & ": unknown measurement kind " & Text;
   end Parse_Value_Kind;

   function Parse_Run_State (Text, Context : String) return Assessment_Status is
   begin
      if Text = "running" then return Assessment_Running;
      elsif Text = "completed" then return Assessment_Completed;
      elsif Text = "invalid" then return Assessment_Invalid;
      elsif Text = "interrupted" then return Assessment_Interrupted;
      end if;
      raise Integrity_Error with Context & ": unknown lifecycle state " & Text;
   end Parse_Run_State;

   function Parse_Number (Text, Context : String) return Long_Long_Integer is
      Value : Long_Long_Integer;
   begin
      Value := Long_Long_Integer'Value (Text);
      if Long_Long_Integer'Image (Value) /= Text then
         raise Integrity_Error with Context & ": noncanonical number " & Text;
      end if;
      return Value;
   exception
      when Constraint_Error =>
         raise Integrity_Error with Context & ": invalid number " & Text;
   end Parse_Number;

   ------------------------------------------------------------------------------------------------------------------
   --  Snapshot loading
   ------------------------------------------------------------------------------------------------------------------

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
   begin
      for C of Text loop
         State := (State xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#0000_0100_0000_01B3#;
      end loop;
      State := (State xor 16#1F#) * 16#0000_0100_0000_01B3#;
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
     (Path : String; Limits : Load_Limits; Version : out Positive; Rows : out Entity_Table_Array)
   is
      DB      : Database.Handle;
      Tx      : Database.Transactions.Transaction;
      Schemas : Schema_Array;

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
            Rows (Table).Append (Entity_Tables.Element (Cursor));
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
      Meta   : Entity;

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
      begin
         Database.Transactions.Begin_Read (DB, Tx);
         if not Database.Transactions.Is_Active (Tx) then
            raise Busy_Error with "read snapshot unavailable: " & Message_Of (Database.Transactions.Result (Tx));
         end if;
         Status := Entity_Tables.Find (Tx, DB, Schemas (Metadata_Table), 1, Meta);
         if not Database.Status.Is_Ok (Status) or else S (Meta.Kind) /= "schema_version" then
            raise Schema_Error with "schema version metadata is missing: " & Path;
         end if;
         declare
            Text : constant String := S (Meta.Payload);
         begin
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
         Scan (Indicator_Results_Table, Positive'Last, "indicator results");
         Scan (Measurements_Table, Positive'Last, "measurements");
         Scan (Findings_Table, Limits.Max_Findings, "findings");
      end Load_Rows;
   begin
      Version := Supported_Schema;
      Open_Database;
      Load_Version;
      Load_Rows;
      Require_Read (Database.Transactions.Commit (Tx), "complete read snapshot");
      Database.Close (DB);
   exception
      when others =>  --  AQ: audited exception boundary
         Release;
         raise;
   end Read_Tables;

   function Less (Left, Right : Entity) return Boolean is (Left.Id < Right.Id);
   package Entity_Sorting is new Entity_Vectors.Generic_Sorting ("<" => Less);

   function To_Detail (Row : Entity) return Ada_Quality.Storage.Detail_Info is
     (Id => Row.Id, Run_Id => Positive (Row.Parent_Id),
      Kind => To_Unbounded_String (S (Row.Kind)), State => To_Unbounded_String (S (Row.State)),
      Summary => To_Unbounded_String (S (Row.Payload)));

   procedure Decode_Snapshot (Item : in out Session; Rows : in out Entity_Table_Array) is
      Digest : Interfaces.Unsigned_64 := 16#CBF2_9CE4_8422_2325#;
      Known_Projects : Run_Index_Maps.Map;
      procedure Index_Rows is
      begin
         for Table in Rows'Range loop
            Entity_Sorting.Sort (Rows (Table));
            Hash (Digest, Positive'Image (Table));
            for Row of Rows (Table) loop
               Hash (Digest, Positive'Image (Row.Id));
               Hash (Digest, Natural'Image (Row.Parent_Id));
               Hash (Digest, S (Row.Kind));
               Hash (Digest, S (Row.State));
               Hash (Digest, S (Row.Payload));
               Hash (Digest, Boolean'Image (Row.Active));
            end loop;
         end loop;
         Item.Identity := To_Unbounded_String ("fnv1a64:" & Hex (Digest));
      end Index_Rows;

      procedure Decode_Projects is
      begin
         for Row of Rows (Projects_Table) loop
            declare
               Context : constant String := Context_Of ("project", Row.Id);
               State   : constant String := S (Row.State);
            begin
               if S (Row.Kind) /= "ada_project" or else State not in "registered" | "removed" or else
                 Row.Parent_Id /= 0 or else Length (Row.Payload) = 0
               then
                  raise Integrity_Error with Context & ": malformed registry entry";
               end if;
               Item.All_Projects.Append
                 (Project_Record'(Id => Row.Id, Path => To_Unbounded_String (S (Row.Payload)), Enabled => Row.Active,
                   Removed => State = "removed"));
               Known_Projects.Insert (Row.Id, Item.All_Projects.Last_Index);
            end;
         end loop;
      end Decode_Projects;

      procedure Decode_Runs is
      begin
         for Row of Rows (Assessments_Table) loop
            declare
               Context : constant String := Context_Of ("assessment run", Row.Id);
               Payload : constant String := S (Row.Payload);
               State   : constant Assessment_Status := Parse_Run_State (S (Row.State), Context);
               Format  : constant String := Field (Payload, "evidence_format");
            begin
               if S (Row.Kind) /= "assessment" or else not Known_Projects.Contains (Row.Parent_Id) then
                  raise Integrity_Error with Context & ": run is not owned by a registered project";
               elsif Row.Active /= (State = Assessment_Completed) then
                  raise Integrity_Error with Context & ": completion flag contradicts lifecycle state";
               elsif Has_Field (Payload, "evidence_format") and then Format /= Lossless_Evidence_Format then
                  raise Integrity_Error with Context & ": unsupported evidence format " & Format;
               end if;
               Item.All_Runs.Append
                 (Run_Record'(Id => Row.Id, Project_Id => Row.Parent_Id, State => State,
                   Source_Id => To_Unbounded_String (Field (Payload, "source")),
                   Policy_Id => To_Unbounded_String (Field (Payload, "policy")),
                   Toolchain_Id => To_Unbounded_String (Field (Payload, "toolchain")),
                   Started_At => Parse_Timestamp (Field (Payload, "started_at"), Context),
                   Finished_At => Parse_Timestamp (Field (Payload, "finished_at"), Context),
                   Format => (if Has_Field (Payload, "evidence_format") then Lossless_Evidence else Legacy_Evidence)));
               Item.Run_Index.Insert (Row.Id, Item.All_Runs.Last_Index);
               Item.Payloads.Append
                 (Ada_Quality.Storage.History_Item'
                    (Id => Row.Id, Project_Id => Row.Parent_Id, Status => To_Unbounded_String (S (Row.State)),
                   Summary => To_Unbounded_String (Payload),
                   Source_Fingerprint => To_Unbounded_String (Field (Payload, "source")),
                   Policy_Fingerprint => To_Unbounded_String (Field (Payload, "policy")),
                   Toolchain_Fingerprint => To_Unbounded_String (Field (Payload, "toolchain"))));
               Item.Details.Insert (Row.Id, (others => <>));
            end;
         end loop;
      end Decode_Runs;

      procedure Decode_Details is
      begin
         for Table in Indicator_Results_Table .. Findings_Table loop
            for Row of Rows (Table) loop
               if not Item.Details.Contains (Row.Parent_Id) then
                  raise Integrity_Error with
                    Context_Of (Decode (Table_Name (Table)), Row.Id) & ": orphaned evidence";
               end if;
               declare
                  Group : Detail_Group renames Item.Details.Reference (Row.Parent_Id);
               begin
                  case Table is
                     when Indicator_Results_Table => Group.Results.Append (To_Detail (Row));
                     when Measurements_Table => Group.Measurements.Append (To_Detail (Row));
                     when others => Group.Findings.Append (To_Detail (Row));
                  end case;
               end;
            end loop;
         end loop;
      end Decode_Details;
   begin
      Index_Rows;
      Decode_Projects;
      Decode_Runs;
      Decode_Details;
   end Decode_Snapshot;

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
      Read_Tables (Path, Limits, Item.Version, Rows);
      Decode_Snapshot (Item, Rows);
      Item.Opened := True;
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
      Item.All_Projects.Clear;
      Item.All_Runs.Clear;
      Item.Run_Index.Clear;
      Item.Payloads.Clear;
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

   ------------------------------------------------------------------------------------------------------------------
   --  Queries
   ------------------------------------------------------------------------------------------------------------------

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

   function Runs (Item : Session; Project_Id : Natural := 0) return Run_Vectors.Vector is
      Result : Run_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         if Project_Id = 0 or else Run.Project_Id = Project_Id then
            Result.Append (Run);
         end if;
      end loop;
      return Result;
   end Runs;

   function Completed_Run (Item : Session; Run_Id : Positive) return Run_Record is
   begin
      Require_Open (Item);
      if not Item.Run_Index.Contains (Run_Id) then
         raise Reporting_Error with "assessment not found:" & Positive'Image (Run_Id);
      end if;
      declare
         Run : constant Run_Record := Item.All_Runs (Item.Run_Index.Element (Run_Id));
      begin
         if Run.State /= Assessment_Completed then
            raise Reporting_Error with "assessment is not completed:" & Positive'Image (Run_Id);
         end if;
         return Run;
      end;
   end Completed_Run;

   function Decode_Measurement (Row : Ada_Quality.Storage.Detail_Info; Context : String) return Measurement_Value is
      Kind : constant Value_Kind := Parse_Value_Kind (To_String (Row.State), Context);
      Text : constant String := To_String (Row.Summary);
   begin
      case Kind is
         when Unavailable_Value =>
            return (Kind => Unavailable_Value, Reason => Row.Summary);
         when Boolean_Value =>
            if Text = "TRUE" then
               return (Kind => Boolean_Value, Boolean_Data => True);
            elsif Text = "FALSE" then
               return (Kind => Boolean_Value, Boolean_Data => False);
            end if;
            raise Integrity_Error with Context & ": invalid Boolean measurement " & Text;
         when Integer_Value =>
            return (Kind => Integer_Value, Integer_Data => Parse_Number (Text, Context));
         when Decimal_Value =>
            return (Kind => Decimal_Value, Basis_Points => Parse_Number (Text, Context));
         when Text_Value =>
            return (Kind => Text_Value, Text_Data => Row.Summary);
         when Enum_Value =>
            return (Kind => Enum_Value, Text_Data => Row.Summary);
      end case;
   end Decode_Measurement;

   function Decode_Finding
     (Row : Ada_Quality.Storage.Detail_Info; Format : Evidence_Format) return Finding
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
            Result.Indicator := Parse_Indicator (Required_Field (Payload, "indicator", Context), Context);
            Result.Rule := To_Unbounded_String (Required_Field (Payload, "rule", Context));
            Result.Message := To_Unbounded_String (Required_Field (Payload, "message", Context));
            Result.Relative_Path := To_Unbounded_String (Required_Field (Payload, "path", Context));
            declare
               Line : constant Long_Long_Integer := Parse_Number (" " & Required_Field (Payload, "line", Context),
                                                                  Context);
            begin
               if Line < 0 or else Line > Long_Long_Integer (Natural'Last) then
                  raise Integrity_Error with Context & ": line number out of range";
               end if;
               Result.Line := Natural (Line);
            end;
            if Finding_Payload (Result) /= Payload then
               raise Integrity_Error with Context & ": noncanonical finding payload";
            end if;
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

   function Read_Assessment (Item : Session; Run_Id : Positive) return Assessment_Record is
      Run     : constant Run_Record := Completed_Run (Item, Run_Id);
      Group   : constant Detail_Group := Item.Details.Element (Run_Id);
      Decoded : array (Indicator_Id) of Indicator_Result;
      Has_Result, Has_Measurement : array (Indicator_Id) of Boolean := [others => False];
      Output  : Assessment_Record;
      procedure Decode_Results is
      begin
         for Row of Group.Results loop
            declare
               Context : constant String := Context_Of ("indicator result", Row.Id);
               Id      : constant Indicator_Id := Parse_Indicator (To_String (Row.Kind), Context);
               State   : constant String := To_String (Row.State);
               Slash   : constant Natural := Ada.Strings.Fixed.Index (State, "/");
               Payload : constant String := To_String (Row.Summary);
               Value   : Indicator_Result;
            begin
               if Has_Result (Id) then
                  raise Integrity_Error with Context & ": duplicate result for " & Image (Id);
               elsif Slash = 0 then
                  raise Integrity_Error with Context & ": malformed result state " & State;
               end if;
               Value.Indicator := Id;
               Value.Execution := Parse_Execution (State (State'First .. Slash - 1), Context);
               Value.Compliance := Parse_Compliance (State (Slash + 1 .. State'Last), Context);
               case Run.Format is
                  when Lossless_Evidence =>
                     declare
                        Applicable : constant String := Required_Field (Payload, "applicable", Context);
                     begin
                        if Applicable not in "true" | "false" then
                           raise Integrity_Error with Context & ": malformed applicability";
                        end if;
                        Value.Applicable := Applicable = "true";
                        Value.Summary := To_Unbounded_String (Required_Field (Payload, "summary", Context));
                        Value.Evidence := To_Unbounded_String (Required_Field (Payload, "evidence", Context));
                        if Result_Payload (Value) /= Payload then
                           raise Integrity_Error with Context & ": noncanonical result payload";
                        end if;
                     end;
                  when Legacy_Evidence =>
                     declare
                        Split : constant Natural := Ada.Strings.Fixed.Index (Payload, [LF]);
                     begin
                        if Split = 0 then
                           raise Integrity_Error with Context & ": malformed legacy result payload";
                        end if;
                        Value.Applicable := Value.Execution /= Not_Applicable;
                        Value.Summary := To_Unbounded_String (Payload (Payload'First .. Split - 1));
                        Value.Evidence := To_Unbounded_String (Payload (Split + 1 .. Payload'Last));
                     end;
               end case;
               Decoded (Id) := Value;
               Has_Result (Id) := True;
            end;
         end loop;
         for Id in Indicator_Id loop
            if not Has_Result (Id) then
               raise Integrity_Error with
                 "assessment" & Positive'Image (Run_Id) & ": missing result for " & Image (Id);
            end if;
         end loop;
      end Decode_Results;

      procedure Decode_Measurements is
      begin
         for Row of Group.Measurements loop
            declare
               Context : constant String := Context_Of ("measurement", Row.Id);
               Id      : constant Indicator_Id := Parse_Indicator (To_String (Row.Kind), Context);
            begin
               if Has_Measurement (Id) then
                  raise Integrity_Error with Context & ": duplicate measurement for " & Image (Id);
               end if;
               Decoded (Id).Measurement := Decode_Measurement (Row, Context);
               Has_Measurement (Id) := True;
            end;
         end loop;
      end Decode_Measurements;

      procedure Decode_Findings is
      begin
         for Row of Group.Findings loop
            declare
               Value : constant Finding := Decode_Finding (Row, Run.Format);
            begin
               Decoded (Value.Indicator).Findings.Append (Value);
            end;
         end loop;
      end Decode_Findings;

      procedure Validate_Results is
      begin
         for Id in Indicator_Id loop
            if not Has_Measurement (Id) then
               raise Integrity_Error with
                 "assessment" & Positive'Image (Run_Id) & ": missing measurement for " & Image (Id);
            elsif not Is_Valid (Decoded (Id)) then
               raise Integrity_Error with
                 "assessment" & Positive'Image (Run_Id) & ": inconsistent evidence for " & Image (Id);
            end if;
         end loop;
      end Validate_Results;
   begin
      Decode_Results;
      Decode_Measurements;
      Decode_Findings;
      Validate_Results;

      Output.Run := Run;
      for Id in Indicator_Id loop
         Output.Results.Append (Decoded (Id));
      end loop;
      return Output;
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

   function History_Items
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.Storage.History_Vectors.Vector
   is
      Result : Ada_Quality.Storage.History_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.Payloads loop
         if Project_Id = 0 or else Run.Project_Id = Project_Id then
            Result.Append (Run);
         end if;
      end loop;
      return Result;
   end History_Items;

   function Read_History_Evidence (Item : Session; Run_Id : Positive) return History_Evidence is
      Validated : constant Assessment_Record := Read_Assessment (Item, Run_Id);
      Group     : constant Detail_Group := Item.Details.Element (Validated.Run.Id);
   begin
      return (Results => Group.Results, Measurements => Group.Measurements, Findings => Group.Findings);
   end Read_History_Evidence;

   function All_Measurements
     (Item : Session; Project_Id : Natural := 0) return Ada_Quality.Storage.Detail_Vectors.Vector
   is
      Result : Ada_Quality.Storage.Detail_Vectors.Vector;
   begin
      Require_Open (Item);
      for Run of Item.All_Runs loop
         if Run.State = Assessment_Completed and then (Project_Id = 0 or else Run.Project_Id = Project_Id) then
            declare
               Validated : constant Assessment_Record := Read_Assessment (Item, Run.Id);
            begin
               Result.Append (Item.Details.Element (Validated.Run.Id).Measurements);
            end;
         end if;
      end loop;
      return Result;
   end All_Measurements;
end Ada_Quality.Reporting;
