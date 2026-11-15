with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada_Quality.Indicators;
with Database.Types;

package body Ada_Quality.Persistence is
   use Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;
   use type Ada_Quality.Types.Assessment_Status;
   use type Ada_Quality.Types.Execution_Status;
   use type Ada_Quality.Types.Value_Kind;

   LF : constant Character := Character'Val (10);
   CR : constant Character := Character'Val (13);

   Table_Names : constant array (Positive range 1 .. Logical_Table_Count) of access constant Wide_Wide_String :=
     [new Wide_Wide_String'("projects"), new Wide_Wide_String'("assessment_runs"),
      new Wide_Wide_String'("indicator_results"), new Wide_Wide_String'("measurements"),
      new Wide_Wide_String'("findings"), new Wide_Wide_String'("tool_executions"),
      new Wide_Wide_String'("assessment_events"), new Wide_Wide_String'("schema_metadata")];

   function Table_Name (Table : Positive) return Wide_Wide_String is (Table_Names (Table).all);

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

   function Encode (Text : String) return Wide_Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Decode (Text));

   function Decode (Text : Wide_Wide_String) return String is
     (Ada.Strings.UTF_Encoding.Wide_Wide_Strings.Encode (Text));

   function WW (Text : String) return Unbounded_Wide_Wide_String is
     (To_Unbounded_Wide_Wide_String (Encode (Text)));

   function S (Text : Unbounded_Wide_Wide_String) return String is
     (Decode (To_Wide_Wide_String (Text)));

   function Metadata_Row_Is_Valid (Row : Entity) return Boolean is
     (Row.Id = 1 and then Row.Parent_Id = 0 and then S (Row.Kind) = "schema_version" and then
      S (Row.State) = "active" and then Row.Active);

   function Project_Row_Is_Valid (Row : Entity) return Boolean is
     (Row.Parent_Id = 0 and then S (Row.Kind) = "ada_project" and then
      S (Row.State) in "registered" | "removed" and then Length (Row.Payload) > 0 and then
      (S (Row.State) /= "removed" or else not Row.Active));

   --  Locate the first line starting with Name=, returning the value bounds.
   procedure Find_Field
     (Payload, Name : String; Line_First, Value_First, Line_Last : out Natural)
   is
      Prefix : constant String := Name & "=";
      Start  : Natural := Payload'First;
   begin
      Line_First := 0;
      Value_First := 0;
      Line_Last := 0;
      while Start <= Payload'Last loop
         declare
            Stop : Natural := Start;
         begin
            while Stop <= Payload'Last and then Payload (Stop) /= LF loop
               Stop := Stop + 1;
            end loop;
            if Stop - Start >= Prefix'Length and then Payload (Start .. Start + Prefix'Length - 1) = Prefix then
               Line_First := Start;
               Value_First := Start + Prefix'Length;
               Line_Last := Stop - 1;
               return;
            end if;
            Start := Stop + 1;
         end;
      end loop;
   end Find_Field;

   function Has_Field (Payload, Name : String) return Boolean is
      Line_First, Value_First, Line_Last : Natural;
   begin
      Find_Field (Payload, Name, Line_First, Value_First, Line_Last);
      return Line_First /= 0;
   end Has_Field;

   function Field (Payload, Name : String) return String is
      Line_First, Value_First, Line_Last : Natural;
   begin
      Find_Field (Payload, Name, Line_First, Value_First, Line_Last);
      if Line_First = 0 then
         return "";
      end if;
      return Payload (Value_First .. Line_Last);
   end Field;

   function With_Field (Payload, Name, Value : String) return String is
      Line_First, Value_First, Line_Last : Natural;
   begin
      Find_Field (Payload, Name, Line_First, Value_First, Line_Last);
      if Line_First /= 0 then
         return Payload (Payload'First .. Value_First - 1) & Value & Payload (Line_Last + 1 .. Payload'Last);
      elsif Payload'Length = 0 then
         return Name & "=" & Value;
      else
         return Payload & LF & Name & "=" & Value;
      end if;
   end With_Field;

   function Escape (Text : String) return String is
      Result : Unbounded_String;
   begin
      for C of Text loop
         case C is
            when '\' => Append (Result, "\\");
            when LF  => Append (Result, "\n");
            when CR  => Append (Result, "\r");
            when others => Append (Result, C);
         end case;
      end loop;
      return To_String (Result);
   end Escape;

   function Unescape (Text : String; Valid : out Boolean) return String is
      Result : Unbounded_String;
      Index  : Natural := Text'First;
   begin
      Valid := True;
      while Index <= Text'Last loop
         if Text (Index) = '\' then
            if Index = Text'Last then
               Valid := False;
               return "";
            end if;
            case Text (Index + 1) is
               when '\' => Append (Result, '\');
               when 'n' => Append (Result, LF);
               when 'r' => Append (Result, CR);
               when others =>
                  Valid := False;
                  return "";
            end case;
            Index := Index + 2;
         elsif Text (Index) in LF | CR then
            Valid := False;
            return "";
         else
            Append (Result, Text (Index));
            Index := Index + 1;
         end if;
      end loop;
      return To_String (Result);
   end Unescape;

   function UTC_Now return String is
      Image : constant String :=
        Ada.Calendar.Formatting.Image (Ada.Calendar.Clock, Include_Time_Fraction => False, Time_Zone => 0);
   begin
      --  Formatting.Image returns `YYYY-MM-DD HH:MM:SS`.
      return Image (Image'First .. Image'First + 9) & "T" & Image (Image'First + 11 .. Image'Last) & "Z";
   end UTC_Now;

   function Assessment_Payload
     (Source_Fingerprint, Policy_Fingerprint, Toolchain_Fingerprint : String;
      Started_At  : String := "";
      Finished_At : String := "";
      Lossless    : Boolean := False) return String
   is
      Result : Unbounded_String := To_Unbounded_String
        ("source=" & Source_Fingerprint & LF &
         "policy=" & Policy_Fingerprint & LF &
         "toolchain=" & Toolchain_Fingerprint);
   begin
      if Lossless then
         Append (Result, LF & "evidence_format=" & Lossless_Evidence_Format);
      end if;
      if Started_At'Length > 0 then
         Append (Result, LF & "started_at=" & Started_At);
      end if;
      if Finished_At'Length > 0 then
         Append (Result, LF & "finished_at=" & Finished_At);
      end if;
      return To_String (Result);
   end Assessment_Payload;

   function Decode_Timestamp (Text : String; Item : out Persisted_Timestamp) return Boolean is
      function Digits_At (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               raise Constraint_Error;
            end if;
            Result := Result * 10 + Character'Pos (Text (Index)) - Character'Pos ('0');
         end loop;
         return Result;
      end Digits_At;
   begin
      if Text'Length = 0 then
         Item := (Present => False);
         return True;
      elsif Text'Length /= 20 or else Text (Text'First + 4) /= '-' or else
        Text (Text'First + 7) /= '-' or else Text (Text'First + 10) /= 'T' or else
        Text (Text'First + 13) /= ':' or else Text (Text'First + 16) /= ':' or else
        Text (Text'Last) /= 'Z'
      then
         Item := (Present => False);
         return False;
      end if;
      declare
         First : constant Positive := Text'First;
      begin
         Item :=
           (Present => True,
            Value   => Ada.Calendar.Formatting.Time_Of
              (Year => Ada.Calendar.Year_Number (Digits_At (First, First + 3)),
               Month => Ada.Calendar.Month_Number (Digits_At (First + 5, First + 6)),
               Day => Ada.Calendar.Day_Number (Digits_At (First + 8, First + 9)),
               Hour => Ada.Calendar.Formatting.Hour_Number (Digits_At (First + 11, First + 12)),
               Minute => Ada.Calendar.Formatting.Minute_Number (Digits_At (First + 14, First + 15)),
               Second => Ada.Calendar.Formatting.Second_Number (Digits_At (First + 17, First + 18)),
               Time_Zone => 0));
      end;
      return True;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         Item := (Present => False);
         return False;
   end Decode_Timestamp;

   function Decode_Assessment_Payload
     (Payload : String; Item : out Assessment_Payload_Data) return Boolean
   is
      Source     : constant String := Field (Payload, "source");
      Policy     : constant String := Field (Payload, "policy");
      Toolchain  : constant String := Field (Payload, "toolchain");
      Started    : constant String := Field (Payload, "started_at");
      Finished   : constant String := Field (Payload, "finished_at");
      Has_Format : constant Boolean := Has_Field (Payload, "evidence_format");
      Lossless   : constant Boolean :=
        Has_Format and then Field (Payload, "evidence_format") = Lossless_Evidence_Format;
   begin
      Item := (others => <>);
      if not Ada_Quality.Types.Fingerprint_Is_Valid (Source) or else
        not Ada_Quality.Types.Fingerprint_Is_Valid (Policy) or else
        (Toolchain'Length > 0 and then not Ada_Quality.Types.Fingerprint_Is_Valid (Toolchain)) or else
        (Has_Format and then not Lossless) or else
        not Decode_Timestamp (Started, Item.Started_At) or else
        not Decode_Timestamp (Finished, Item.Finished_At)
      then
         return False;
      end if;
      Item.Source_Fingerprint := To_Unbounded_String (Source);
      Item.Policy_Fingerprint := To_Unbounded_String (Policy);
      Item.Toolchain_Fingerprint := To_Unbounded_String (Toolchain);
      Item.Lossless := Lossless;
      return Payload = Assessment_Payload
        (Source, Policy, Toolchain, Started_At => Started, Finished_At => Finished,
         Lossless => Lossless);
   exception
      when Constraint_Error =>
         Item := (others => <>);
         return False;
   end Decode_Assessment_Payload;

   function Decode_Assessment_State
     (State : String; Item : out Ada_Quality.Types.Assessment_Status) return Boolean
   is
   begin
      if State = "running" then
         Item := Ada_Quality.Types.Assessment_Running;
      elsif State = "completed" then
         Item := Ada_Quality.Types.Assessment_Completed;
      elsif State = "invalid" then
         Item := Ada_Quality.Types.Assessment_Invalid;
      elsif State = "interrupted" then
         Item := Ada_Quality.Types.Assessment_Interrupted;
      else
         Item := Ada_Quality.Types.Assessment_Running;
         return False;
      end if;
      return True;
   end Decode_Assessment_State;

   function Terminal_Timestamps_Are_Valid (Item : Assessment_Payload_Data) return Boolean is
      Both_Timestamps : constant Boolean :=
        Item.Started_At.Present and then Item.Finished_At.Present;
      No_Timestamps : constant Boolean :=
        not Item.Started_At.Present and then not Item.Finished_At.Present;
   begin
      return (if Item.Lossless then Both_Timestamps else Both_Timestamps or else No_Timestamps) and then
        (not Both_Timestamps or else Item.Finished_At.Value >= Item.Started_At.Value);
   end Terminal_Timestamps_Are_Valid;

   function Assessment_Payload_Matches_State
     (Item : Assessment_Payload_Data;
      State : Ada_Quality.Types.Assessment_Status) return Boolean
   is
   begin
      case State is
         when Ada_Quality.Types.Assessment_Running =>
            return not Item.Lossless and then not Item.Finished_At.Present and then
              Length (Item.Toolchain_Fingerprint) = 0;
         when Ada_Quality.Types.Assessment_Completed |
              Ada_Quality.Types.Assessment_Invalid =>
            return Ada_Quality.Types.Fingerprint_Is_Valid (To_String (Item.Toolchain_Fingerprint)) and then
              Terminal_Timestamps_Are_Valid (Item);
         when Ada_Quality.Types.Assessment_Interrupted =>
            return (Length (Item.Toolchain_Fingerprint) = 0 or else
                    Ada_Quality.Types.Fingerprint_Is_Valid (To_String (Item.Toolchain_Fingerprint))) and then
              Terminal_Timestamps_Are_Valid (Item);
      end case;
   end Assessment_Payload_Matches_State;

   function Decode_Assessment_Row
     (Row     : Entity;
      Payload : out Assessment_Payload_Data;
      State   : out Ada_Quality.Types.Assessment_Status) return Boolean
   is
   begin
      Payload := (others => <>);
      State := Ada_Quality.Types.Assessment_Running;
      return Row.Parent_Id > 0 and then S (Row.Kind) = "assessment" and then
        Decode_Assessment_State (S (Row.State), State) and then
        Decode_Assessment_Payload (S (Row.Payload), Payload) and then
        Assessment_Payload_Matches_State (Payload, State) and then
        Row.Active = (State = Ada_Quality.Types.Assessment_Completed);
   exception
      when Constraint_Error =>
         Payload := (others => <>);
         State := Ada_Quality.Types.Assessment_Running;
         return False;
   end Decode_Assessment_Row;

   function Classify_Lifecycle_Event
     (State       : Ada_Quality.Types.Assessment_Status;
      Event_Kind  : String;
      Event_State : String) return Lifecycle_Event_Class
   is
   begin
      if Event_Kind = "started" and then Event_State = "running" then
         return Started_Lifecycle_Event;
      elsif State in Ada_Quality.Types.Assessment_Completed | Ada_Quality.Types.Assessment_Invalid and then
        Event_Kind = "published" and then
        Event_State = (if State = Ada_Quality.Types.Assessment_Completed then "completed" else "invalid")
      then
         return Terminal_Lifecycle_Event;
      elsif State = Ada_Quality.Types.Assessment_Interrupted and then
        Event_Kind in "published" | "interrupted" | "recovered" and then Event_State = "interrupted"
      then
         return Terminal_Lifecycle_Event;
      else
         return Invalid_Lifecycle_Event;
      end if;
   end Classify_Lifecycle_Event;

   function Lifecycle_Counts_Are_Valid
     (State          : Ada_Quality.Types.Assessment_Status;
      Started_Count  : Natural;
      Terminal_Count : Natural;
      Event_Count    : Natural) return Boolean
   is
   begin
      case State is
         when Ada_Quality.Types.Assessment_Running =>
            return Started_Count = 1 and then Terminal_Count = 0 and then Event_Count = 1;
         when Ada_Quality.Types.Assessment_Completed |
              Ada_Quality.Types.Assessment_Invalid |
              Ada_Quality.Types.Assessment_Interrupted =>
            return Started_Count <= 1 and then Terminal_Count = 1 and then
              Event_Count = Started_Count + Terminal_Count;
      end case;
   end Lifecycle_Counts_Are_Valid;

   function Event_Row_Is_Valid (Row : Entity) return Boolean is
     (Row.Parent_Id > 0 and then Length (Row.Kind) > 0 and then Row.Active and then
      S (Row.State) in "running" | "completed" | "invalid" | "interrupted");

   function Result_Payload (Item : Ada_Quality.Types.Indicator_Result) return String is
     ("applicable=" & (if Item.Applicable then "true" else "false") & LF &
      "summary=" & Escape (To_String (Item.Summary)) & LF &
      "evidence=" & Escape (To_String (Item.Evidence)));

   function Finding_Payload (Item : Ada_Quality.Types.Finding) return String is
     ("indicator=" & Ada_Quality.Types.Image (Item.Indicator) & LF &
      "rule=" & Escape (To_String (Item.Rule)) & LF &
      "message=" & Escape (To_String (Item.Message)) & LF &
      "path=" & Escape (To_String (Item.Relative_Path)) & LF &
      "line=" & Ada.Strings.Fixed.Trim (Natural'Image (Item.Line), Ada.Strings.Both));

   function Parse_Value_Kind
     (Text : String; Value : out Ada_Quality.Types.Value_Kind) return Boolean;

   function Required_Unescaped_Field
     (Payload, Name : String; Value : out Unbounded_String) return Boolean
   is
      Valid : Boolean;
   begin
      Value := Null_Unbounded_String;
      if not Has_Field (Payload, Name) then
         return False;
      end if;
      Value := To_Unbounded_String (Unescape (Field (Payload, Name), Valid));
      return Valid;
   end Required_Unescaped_Field;

   function Decode_Result_Payload
     (Payload : String; Item : out Ada_Quality.Types.Indicator_Result) return Boolean
   is
      Applicable : constant String := Field (Payload, "applicable");
   begin
      Item := (others => <>);
      if not Has_Field (Payload, "applicable") or else Applicable not in "true" | "false" or else
        not Required_Unescaped_Field (Payload, "summary", Item.Summary) or else
        not Required_Unescaped_Field (Payload, "evidence", Item.Evidence)
      then
         return False;
      end if;
      Item.Applicable := Applicable = "true";
      return Result_Payload (Item) = Payload;
   exception
      when Constraint_Error =>
         return False;
   end Decode_Result_Payload;

   function Measurement_Semantic_Identity (State : String) return String is
      Indicator_Tag : constant String := ";indicator_version=";
      Method_Tag    : constant String := ";method_version=";
      Separator     : constant Natural := Ada.Strings.Fixed.Index (State, ";");
      Indicator_At  : constant Natural := Ada.Strings.Fixed.Index (State, Indicator_Tag);
      Method_At     : constant Natural := Ada.Strings.Fixed.Index (State, Method_Tag);
      Kind_Text     : constant String :=
        (if Separator = 0 then State else State (State'First .. Separator - 1));
      Kind : Ada_Quality.Types.Value_Kind;

      function Trimmed (Value : Positive) return String is
        (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));
   begin
      if not Parse_Value_Kind (Kind_Text, Kind) then
         return "";
      elsif Separator = 0 then
         return Kind_Text & Indicator_Tag & "1" & Method_Tag & "1";
      elsif Indicator_At /= Separator or else
        Method_At <= Indicator_At + Indicator_Tag'Length
      then
         return "";
      end if;
      declare
         Indicator_Version : constant Positive :=
           Positive'Value (State (Indicator_At + Indicator_Tag'Length .. Method_At - 1));
         Method_Version : constant Positive :=
           Positive'Value (State (Method_At + Method_Tag'Length .. State'Last));
         Canonical : constant String :=
           Kind_Text & Indicator_Tag & Trimmed (Indicator_Version) &
           Method_Tag & Trimmed (Method_Version);
      begin
         return (if Canonical = State then Canonical else "");
      end;
   exception
      when Constraint_Error =>
         return "";
   end Measurement_Semantic_Identity;

   function Decode_Measurement
     (State, Payload    : String;
      Item              : out Ada_Quality.Types.Measurement_Value;
      Require_Versioned : Boolean := False) return Boolean
   is
      Separator : constant Natural := Ada.Strings.Fixed.Index (State, ";");
      Kind_Text : constant String :=
        (if Separator = 0 then State else State (State'First .. Separator - 1));
      Kind : Ada_Quality.Types.Value_Kind;
   begin
      Item := (Kind => Ada_Quality.Types.Unavailable_Value, Reason => Null_Unbounded_String);
      if (Require_Versioned and then Separator = 0) or else
        Measurement_Semantic_Identity (State)'Length = 0 or else
        not Parse_Value_Kind (Kind_Text, Kind)
      then
         return False;
      end if;
      case Kind is
         when Ada_Quality.Types.Unavailable_Value =>
            Item :=
              (Kind => Ada_Quality.Types.Unavailable_Value,
               Reason => To_Unbounded_String (Payload));
         when Ada_Quality.Types.Boolean_Value =>
            if Payload not in "TRUE" | "FALSE" then
               return False;
            end if;
            Item :=
              (Kind => Ada_Quality.Types.Boolean_Value,
               Boolean_Data => Payload = "TRUE");
         when Ada_Quality.Types.Integer_Value =>
            Item :=
              (Kind => Ada_Quality.Types.Integer_Value,
               Integer_Data => Long_Long_Integer'Value (Payload));
         when Ada_Quality.Types.Decimal_Value =>
            Item :=
              (Kind => Ada_Quality.Types.Decimal_Value,
               Basis_Points => Long_Long_Integer'Value (Payload));
         when Ada_Quality.Types.Text_Value | Ada_Quality.Types.Enum_Value =>
            if Kind = Ada_Quality.Types.Text_Value then
               Item :=
                 (Kind => Ada_Quality.Types.Text_Value,
                  Text_Data => To_Unbounded_String (Payload));
            else
               Item :=
                 (Kind => Ada_Quality.Types.Enum_Value,
                  Text_Data => To_Unbounded_String (Payload));
            end if;
      end case;
      return Ada_Quality.Types.Image (Item) = Payload;
   exception
      when Constraint_Error =>
         return False;
   end Decode_Measurement;

   function Decode_Finding_Payload
     (Payload : String; Item : out Ada_Quality.Types.Finding) return Boolean
   is
      Parsed_Line : Long_Long_Integer;
   begin
      Item := (others => <>);
      if not Has_Field (Payload, "indicator") or else
        not Ada_Quality.Indicators.Parse_Canonical (Field (Payload, "indicator"), Item.Indicator) or else
        not Required_Unescaped_Field (Payload, "rule", Item.Rule) or else
        not Required_Unescaped_Field (Payload, "message", Item.Message) or else
        not Required_Unescaped_Field (Payload, "path", Item.Relative_Path) or else
        not Has_Field (Payload, "line")
      then
         return False;
      end if;
      Parsed_Line := Long_Long_Integer'Value (Field (Payload, "line"));
      if Parsed_Line < 0 or else Parsed_Line > Long_Long_Integer (Natural'Last) then
         return False;
      end if;
      Item.Line := Natural (Parsed_Line);
      return Finding_Payload (Item) = Payload;
   exception
      when Constraint_Error =>
         return False;
   end Decode_Finding_Payload;

   function Execution_Payload (Item : Ada_Quality.Types.Tool_Execution) return String is
     ("command=" & To_String (Item.Command) & LF &
      "exit_code=" & Integer'Image (Item.Exit_Code) & LF &
      "output_digest=" & To_String (Item.Output_Digest) & LF &
      "output_bytes=" & Long_Long_Integer'Image (Item.Output_Bytes) & LF &
      "truncated=" & Boolean'Image (Item.Truncated));

   function Decode_Execution_Payload
     (Payload : String; Item : out Ada_Quality.Types.Tool_Execution) return Boolean
   is
      Command : constant String := Field (Payload, "command");
      Digest  : constant String := Field (Payload, "output_digest");
      Exit_Code : Integer;
      Output_Bytes : Long_Long_Integer;
      Truncated : Boolean;
   begin
      Item := (others => <>);
      if not Has_Field (Payload, "command") or else
        not Has_Field (Payload, "exit_code") or else
        not Has_Field (Payload, "output_digest") or else
        not Has_Field (Payload, "output_bytes") or else
        not Has_Field (Payload, "truncated") or else
        not Ada_Quality.Types.Fingerprint_Is_Valid (Command) or else
        not Ada_Quality.Types.Output_Digest_Is_Valid (Digest)
      then
         return False;
      end if;
      Exit_Code := Integer'Value (Field (Payload, "exit_code"));
      Output_Bytes := Long_Long_Integer'Value (Field (Payload, "output_bytes"));
      if Output_Bytes < 0 then
         return False;
      end if;
      if Field (Payload, "truncated") = "TRUE" then
         Truncated := True;
      elsif Field (Payload, "truncated") = "FALSE" then
         Truncated := False;
      else
         return False;
      end if;
      Item.Command := To_Unbounded_String (Command);
      Item.Exit_Code := Exit_Code;
      Item.Output_Digest := To_Unbounded_String (Digest);
      Item.Output_Bytes := Output_Bytes;
      Item.Truncated := Truncated;
      return Payload = Execution_Payload (Item) and then
        (not Item.Truncated or else Item.Output_Bytes > 0);
   exception
      when Constraint_Error =>
         Item := (others => <>);
         return False;
   end Decode_Execution_Payload;

   function Decode_Execution_Row
     (State, Payload : String;
      Active : Boolean;
      Item : out Ada_Quality.Types.Tool_Execution) return Boolean
   is
   begin
      if State not in "tool-completed" | "tool-timed-out" | "tool-spawn-error" or else
        Active /= (State = "tool-completed") or else not Decode_Execution_Payload (Payload, Item)
      then
         Item := (others => <>);
         return False;
      end if;
      Item.Status :=
        (if State = "tool-completed" then Ada_Quality.Types.Tool_Completed
         elsif State = "tool-timed-out" then Ada_Quality.Types.Tool_Timed_Out
         else Ada_Quality.Types.Tool_Spawn_Error);
      return Ada_Quality.Types.Execution_Evidence_Is_Valid
        (Item.Status, Item.Exit_Code, To_String (Item.Output_Digest),
         Item.Output_Bytes, Item.Truncated);
   end Decode_Execution_Row;

   function Execution_Row_Is_Valid (State, Payload : String; Active : Boolean) return Boolean is
      Decoded : Ada_Quality.Types.Tool_Execution;
   begin
      return Decode_Execution_Row (State, Payload, Active, Decoded);
   end Execution_Row_Is_Valid;

   function Parse_Execution
     (Text : String; Value : out Ada_Quality.Types.Execution_Status) return Boolean
   is
   begin
      Value := Ada_Quality.Types.Not_Run;
      for Candidate in Ada_Quality.Types.Execution_Status loop
         if Ada_Quality.Types.Image (Candidate) = Text then
            Value := Candidate;
            return True;
         end if;
      end loop;
      return False;
   end Parse_Execution;

   function Parse_Compliance
     (Text : String; Value : out Ada_Quality.Types.Compliance_Status) return Boolean
   is
   begin
      Value := Ada_Quality.Types.Unknown;
      for Candidate in Ada_Quality.Types.Compliance_Status loop
         if Ada_Quality.Types.Image (Candidate) = Text then
            Value := Candidate;
            return True;
         end if;
      end loop;
      return False;
   end Parse_Compliance;

   function Decode_Result_State
     (State      : String;
      Execution  : out Ada_Quality.Types.Execution_Status;
      Compliance : out Ada_Quality.Types.Compliance_Status) return Boolean
   is
      Slash : constant Natural := Ada.Strings.Fixed.Index (State, "/");
   begin
      Execution := Ada_Quality.Types.Not_Run;
      Compliance := Ada_Quality.Types.Unknown;
      if Slash = 0 or else Slash = State'First or else Slash = State'Last or else
        not Parse_Execution (State (State'First .. Slash - 1), Execution) or else
        not Parse_Compliance (State (Slash + 1 .. State'Last), Compliance)
      then
         return False;
      end if;
      return State = Ada_Quality.Types.Image (Execution) & "/" &
        Ada_Quality.Types.Image (Compliance);
   exception
      when Constraint_Error =>
         Execution := Ada_Quality.Types.Not_Run;
         Compliance := Ada_Quality.Types.Unknown;
         return False;
   end Decode_Result_State;

   function Decode_Severity
     (Text : String; Item : out Ada_Quality.Types.Severity) return Boolean
   is
   begin
      Item := Ada_Quality.Types.Info;
      for Candidate in Ada_Quality.Types.Severity loop
         if Ada_Quality.Types.Severity'Image (Candidate) = Text then
            Item := Candidate;
            return True;
         end if;
      end loop;
      return False;
   end Decode_Severity;

   function Parse_Value_Kind
     (Text : String; Value : out Ada_Quality.Types.Value_Kind) return Boolean
   is
   begin
      Value := Ada_Quality.Types.Unavailable_Value;
      for Candidate in Ada_Quality.Types.Value_Kind loop
         if Ada_Quality.Types.Value_Kind'Image (Candidate) = Text then
            Value := Candidate;
            return True;
         end if;
      end loop;
      return False;
   end Parse_Value_Kind;

   function Decode_Lossless_Result_Flags
     (Payload : String; Applicable, Evidence_Present : out Boolean) return Boolean
   is
      Item : Ada_Quality.Types.Indicator_Result;
   begin
      Applicable := True;
      Evidence_Present := False;
      if not Decode_Result_Payload (Payload, Item) then
         return False;
      end if;
      Applicable := Item.Applicable;
      Evidence_Present := Length (Item.Evidence) > 0;
      return True;
   end Decode_Lossless_Result_Flags;

   function Decode_Legacy_Result_Flags
     (Payload : String;
      Execution : Ada_Quality.Types.Execution_Status;
      Applicable, Evidence_Present : out Boolean) return Boolean
   is
      Split : constant Natural := Ada.Strings.Fixed.Index (Payload, [LF]);
   begin
      Applicable := Execution /= Ada_Quality.Types.Not_Applicable;
      Evidence_Present := Split /= 0 and then Split < Payload'Last;
      return Split /= 0;
   end Decode_Legacy_Result_Flags;

   function Result_Measurement_Are_Consistent
     (Result_State, Result_Payload, Measurement_State : String;
      Lossless : Boolean) return Boolean
   is
      Separator : constant Natural := Ada.Strings.Fixed.Index (Measurement_State, ";");
      Kind_Text : constant String :=
        (if Separator = 0 then Measurement_State
         else Measurement_State (Measurement_State'First .. Separator - 1));
      Execution  : Ada_Quality.Types.Execution_Status;
      Compliance : Ada_Quality.Types.Compliance_Status;
      Kind       : Ada_Quality.Types.Value_Kind;
      Applicable : Boolean;
      Evidence_Present : Boolean;
   begin
      if not Decode_Result_State (Result_State, Execution, Compliance) or else
        not Parse_Value_Kind (Kind_Text, Kind) or else
        (if Lossless
         then not Decode_Lossless_Result_Flags (Result_Payload, Applicable, Evidence_Present)
         else not Decode_Legacy_Result_Flags
           (Result_Payload, Execution, Applicable, Evidence_Present))
      then
         return False;
      end if;
      return Ada_Quality.Types.Execution_Is_Terminal (Execution) and then
        Ada_Quality.Types.Is_Valid
          (Execution, Compliance, Applicable, Kind, Evidence_Present);
   exception
      when Constraint_Error =>
         return False;
   end Result_Measurement_Are_Consistent;
end Ada_Quality.Persistence;
