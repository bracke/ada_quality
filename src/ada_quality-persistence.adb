with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Database.Types;

package body Ada_Quality.Persistence is
   use Ada.Strings.Unbounded;

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
end Ada_Quality.Persistence;
