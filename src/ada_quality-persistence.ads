with Ada.Calendar;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
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

   Current_Schema_Version : constant Positive := 5;
   --  Logical schema version written by this implementation. Version 5 adds canonical project tags.

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

   function Metadata_Row_Is_Valid (Row : Entity) return Boolean;
   --  Validate the invariant fields of the single schema metadata row.

   function Project_Row_Is_Valid (Row : Entity) return Boolean;
   --  Validate a project registry row independently of cross-row ownership.

   function Project_Tag_Is_Valid (Name : String) return Boolean;
   --  Validate one canonical project tag.

   function Project_Tags_Contain (Tags, Name : String) return Boolean;
   --  Test membership in a canonical sorted tag list.

   function Update_Project_Tags
     (Tags, Name : String; Add : Boolean) return String;
   --  Add or remove one name while retaining canonical ordering.

   function Merge_Project_Tags (Left, Right : String) return String;
   --  Return the canonical union of two canonical tag lists.

   function Project_Payload (Path, Tags : String) return String;
   --  Encode a project path and sorted comma-separated tags.

   function Decode_Project_Payload
     (Payload : String; Path, Tags : out Ada.Strings.Unbounded.Unbounded_String) return Boolean;
   --  Decode and validate a canonical version-5 project payload.

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

   type Persisted_Timestamp (Present : Boolean := False) is record
      case Present is
         when True =>
            Value : Ada.Calendar.Time;
         when False =>
            null;
      end case;
   end record;
   --  Canonically decoded optional persisted timestamp.

   type Assessment_Payload_Data is record
      Source_Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Policy_Fingerprint    : Ada.Strings.Unbounded.Unbounded_String;
      Toolchain_Fingerprint : Ada.Strings.Unbounded.Unbounded_String;
      Started_At            : Persisted_Timestamp;
      Finished_At           : Persisted_Timestamp;
      Lossless              : Boolean := False;
   end record;
   --  Canonically decoded assessment-run payload.

   function Decode_Assessment_Payload
     (Payload : String; Item : out Assessment_Payload_Data) return Boolean;
   --  Decode one canonical assessment-run payload.
   --  @param Payload Persisted assessment payload.
   --  @param Item Decoded fingerprints, timestamps, and child-evidence format.
   --  @return True only when Payload has supported, canonical fields and valid UTC timestamps.

   function Decode_Assessment_State
     (State : String; Item : out Ada_Quality.Types.Assessment_Status) return Boolean;
   --  Decode one canonical persisted assessment lifecycle state.

   function Assessment_Payload_Matches_State
     (Item : Assessment_Payload_Data;
      State : Ada_Quality.Types.Assessment_Status) return Boolean;
   --  Validate evidence format and timestamp presence against a lifecycle state.

   function Decode_Assessment_Row
     (Row     : Entity;
      Payload : out Assessment_Payload_Data;
      State   : out Ada_Quality.Types.Assessment_Status) return Boolean;
   --  Decode and validate one assessment row independently of project ownership and child cardinality.

   type Lifecycle_Event_Class is
     (Invalid_Lifecycle_Event, Started_Lifecycle_Event, Terminal_Lifecycle_Event, Alias_Event);
   --  Meaning of one event relative to its owning assessment state.

   function Classify_Lifecycle_Event
     (State       : Ada_Quality.Types.Assessment_Status;
      Event_Kind  : String;
      Event_State : String) return Lifecycle_Event_Class;
   --  Classify one canonical lifecycle event for its owning assessment.

   function Lifecycle_Counts_Are_Valid
     (State          : Ada_Quality.Types.Assessment_Status;
      Started_Count  : Natural;
      Terminal_Count : Natural;
      Alias_Count    : Natural;
      Event_Count    : Natural) return Boolean;
   --  Validate lifecycle-event cardinality for one assessment state.

   function Event_Row_Is_Valid (Row : Entity) return Boolean;
   --  Validate the invariant fields of one lifecycle-event row.

   function Assessment_Alias_Is_Valid (Name : String) return Boolean;
   --  Validate a canonical, nonnumeric assessment alias.
   --  @param Name Candidate alias.
   --  @return True for 1..64 lowercase ASCII letters, digits, dots, underscores, or hyphens,
   --  beginning with a letter.

   function Result_Payload (Item : Ada_Quality.Types.Indicator_Result) return String;
   --  Encode applicability, summary, and evidence losslessly.
   --  @param Item Indicator result.
   --  @return Escaped key-value payload.

   function Finding_Payload (Item : Ada_Quality.Types.Finding) return String;
   --  Encode indicator, rule, message, path, and line losslessly.
   --  @param Item Finding.
   --  @return Escaped key-value payload.

   function Decode_Result_Payload
     (Payload : String; Item : out Ada_Quality.Types.Indicator_Result) return Boolean;
   --  Decode one canonical lossless result payload.
   --  @param Payload Persisted result payload.
   --  @param Item Decoded applicability, summary, and evidence.
   --  @return True only when Payload is exactly the canonical encoding of Item.

   function Decode_Result_State
     (State      : String;
      Execution  : out Ada_Quality.Types.Execution_Status;
      Compliance : out Ada_Quality.Types.Compliance_Status) return Boolean;
   --  Decode one canonical execution/compliance state pair.

   function Decode_Severity
     (Text : String; Item : out Ada_Quality.Types.Severity) return Boolean;
   --  Decode one canonical persisted finding severity.

   function Measurement_Semantic_Identity (State : String) return String;
   --  Return the canonical versioned identity of one measurement state.
   --  @param State Bare legacy kind or versioned measurement state.
   --  @return Canonical versioned state, or an empty string when malformed or noncanonical.

   function Decode_Measurement
     (State, Payload    : String;
      Item              : out Ada_Quality.Types.Measurement_Value;
      Require_Versioned : Boolean := False) return Boolean;
   --  Decode one canonical typed measurement payload.
   --  @param State Persisted measurement kind and semantics.
   --  @param Payload Persisted measurement value.
   --  @param Item Decoded typed measurement.
   --  @param Require_Versioned Whether a bare legacy kind must be rejected.
   --  @return True only when State names a kind and Payload uses its canonical encoding.

   function Decode_Finding_Payload
     (Payload : String; Item : out Ada_Quality.Types.Finding) return Boolean;
   --  Decode one canonical lossless finding payload.
   --  @param Payload Persisted finding payload.
   --  @param Item Decoded indicator, rule, message, path, and line.
   --  @return True only when Payload is exactly the canonical encoding of Item.

   function Execution_Payload (Item : Ada_Quality.Types.Tool_Execution) return String;
   --  Encode one canonical tool-execution payload.

   function Decode_Execution_Payload
     (Payload : String; Item : out Ada_Quality.Types.Tool_Execution) return Boolean;
   --  Decode canonical command, exit, digest, byte-count, and truncation evidence.

   function Decode_Execution_Row
     (State, Payload : String;
      Active : Boolean;
      Item : out Ada_Quality.Types.Tool_Execution) return Boolean;
   --  Decode one complete execution row, including its terminal state and active invariant.

   function Execution_Row_Is_Valid (State, Payload : String; Active : Boolean) return Boolean;
   --  Validate canonical execution state, payload, and active relationship.

   function Result_Measurement_Are_Consistent
     (Result_State, Result_Payload, Measurement_State : String;
      Lossless : Boolean) return Boolean;
   --  Validate the cross-row execution, compliance, applicability, and measurement invariant.
end Ada_Quality.Persistence;
