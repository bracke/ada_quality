with Ada.Containers.Vectors;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Types;
with Database.Rows;
with Database.Schema;
with Database.Tables;
with Database.Values;

--  Private persisted entity layout and payload codecs shared by storage and read-only reporting.
private package Ada_Quality.Persistence is
   --  Private persisted entity layout and payload codecs shared by storage and read-only reporting.
   use Ada.Strings.Wide_Wide_Unbounded;

   Logical_Table_Count     : constant := 8;
   --  Number of logical tables in every supported schema.
   Projects_Table          : constant Positive := 1;
   --  Project registry table index.
   Assessments_Table       : constant Positive := 2;
   --  Assessment run table index.
   Indicator_Results_Table : constant Positive := 3;
   --  Indicator result table index.
   Measurements_Table      : constant Positive := 4;
   --  Typed measurement table index.
   Findings_Table          : constant Positive := 5;
   --  Finding table index.
   Executions_Table        : constant Positive := 6;
   --  External tool execution table index.
   Events_Table            : constant Positive := 7;
   --  Assessment lifecycle event table index.
   Metadata_Table          : constant Positive := 8;
   --  Schema metadata table index.

   Current_Schema_Version : constant Positive := 3;
   --  Logical schema version written by this implementation.

   Lossless_Evidence_Format : constant String := "3";
   --  Run payload marker for escaped key-value result and finding payloads.

   function Table_Name (Table : Positive) return Wide_Wide_String
     with Pre => Table <= Logical_Table_Count;
   --  Return the persisted name of one logical table.
   --  @param Table Logical table index.
   --  @return Stable catalog table name.

   type Entity is record
      Id        : Positive;
      Parent_Id : Natural := 0;
      Kind      : Unbounded_Wide_Wide_String;
      State     : Unbounded_Wide_Wide_String;
      Payload   : Unbounded_Wide_Wide_String;
      Active    : Boolean := True;
   end record;
   --  Generic six-field row shared by every logical table.
   --  @field Id Positive row identity.
   --  @field Parent_Id Owning project or run identity, or zero.
   --  @field Kind Stable key or category.
   --  @field State Persisted state.
   --  @field Payload Persisted payload text.
   --  @field Active Table-specific flag.

   package Entity_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Entity);
   --  Ordered entity collection.

   function To_Row (Item : Entity) return Database.Rows.Row;
   --  Convert an entity into its database row.
   --  @param Item Entity to convert.
   --  @return Database row.

   function From_Row (Row : Database.Rows.Row) return Entity;
   --  Convert a database row into an entity.
   --  @param Row Database row.
   --  @return Entity value.

   function Key_Of (Item : Entity) return Positive is (Item.Id);
   --  Return the primary key of an entity.
   --  @param Item Entity.
   --  @return Row identity.

   function Key_Value (Key : Positive) return Database.Values.Value is
     (Database.Values.From_Integer (Integer (Key)));
   --  Convert a primary key into a database value.
   --  @param Key Row identity.
   --  @return Database integer value.

   package Entity_Tables is new Database.Tables.Typed
     (Row_Type => Entity, Key_Type => Positive, To_Row => To_Row, From_Row => From_Row,
      Key_Of => Key_Of, Key_Value => Key_Value);
   --  Typed table access for entities.

   function New_Schema (Name : Wide_Wide_String) return Database.Schema.Table_Schema;
   --  Build the six-column schema of one logical table.
   --  @param Name Table name.
   --  @return Table schema.

   function Encode (Text : String) return Wide_Wide_String;
   --  Decode UTF-8 application text into database text.
   --  @param Text UTF-8 text.
   --  @return Wide wide text.

   function Decode (Text : Wide_Wide_String) return String;
   --  Encode database text as UTF-8 application text.
   --  @param Text Wide wide text.
   --  @return UTF-8 text.

   function WW (Text : String) return Unbounded_Wide_Wide_String;
   --  Convert UTF-8 text into unbounded database text.
   --  @param Text UTF-8 text.
   --  @return Unbounded database text.

   function S (Text : Unbounded_Wide_Wide_String) return String;
   --  Convert unbounded database text into UTF-8 text.
   --  @param Text Unbounded database text.
   --  @return UTF-8 text.

   function Has_Field (Payload, Name : String) return Boolean;
   --  Test whether a line-oriented payload contains a named field.
   --  @param Payload Line-feed separated `name=value` payload.
   --  @param Name Field name.
   --  @return True when a line starts with `Name=`.

   function Field (Payload, Name : String) return String;
   --  Return the raw value of the first named field.
   --  @param Payload Line-feed separated `name=value` payload.
   --  @param Name Field name.
   --  @return Raw field value, or an empty string when absent.

   function With_Field (Payload, Name, Value : String) return String;
   --  Replace the first named field or append it.
   --  @param Payload Line-feed separated `name=value` payload.
   --  @param Name Field name.
   --  @param Value Raw value without line feeds.
   --  @return Updated payload.

   function Escape (Text : String) return String;
   --  Escape backslash, carriage return, and line feed for one payload field.
   --  @param Text Raw text.
   --  @return Escaped single-line text.

   function Unescape (Text : String; Valid : out Boolean) return String;
   --  Reverse Escape and reject malformed escape sequences.
   --  @param Text Escaped single-line text.
   --  @param Valid True when Text is a well-formed escaped value.
   --  @return Raw text, or an empty string when invalid.

   function UTC_Now return String;
   --  Return the current UTC time in the persisted timestamp format.
   --  @return Text of the form `YYYY-MM-DDTHH:MM:SSZ`.

   function Assessment_Payload
     (Source_Fingerprint, Policy_Fingerprint, Toolchain_Fingerprint : String;
      Started_At  : String := "";
      Finished_At : String := "";
      Lossless    : Boolean := False) return String;
   --  Build a run payload with fingerprints, optional timestamps, and an optional evidence-format marker.
   --  @param Source_Fingerprint Assessed source identity.
   --  @param Policy_Fingerprint Applied policy identity.
   --  @param Toolchain_Fingerprint Selected toolchain identity.
   --  @param Started_At Persisted UTC start timestamp, or empty when unknown.
   --  @param Finished_At Persisted UTC terminal timestamp, or empty when unknown.
   --  @param Lossless Whether child result and finding rows use the lossless format.
   --  @return Line-feed separated run payload.

   function Result_Payload (Item : Ada_Quality.Types.Indicator_Result) return String;
   --  Encode applicability, summary, and evidence losslessly.
   --  @param Item Indicator result.
   --  @return Escaped key-value payload.

   function Finding_Payload (Item : Ada_Quality.Types.Finding) return String;
   --  Encode indicator, rule, message, path, and line losslessly.
   --  @param Item Finding.
   --  @return Escaped key-value payload.
end Ada_Quality.Persistence;
