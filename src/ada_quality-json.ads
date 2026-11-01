with Ada_Quality.Types;
with Ada_Quality.Storage;

--  Deterministic JSON serialization for assessments and persistent archives.
package Ada_Quality.JSON is
   --  Deterministic JSON serialization for assessments and persistent archives.
   function Render (Item : Ada_Quality.Types.Assessment; Pretty : Boolean := False) return String;
   --  Serialize one assessment using the versioned deterministic JSON contract.
   --  @param Item Assessment to serialize.
   --  @param Pretty Whether to indent the resulting document.
   --  @return Complete JSON document.

   function Render_Archive
     (Store : in out Ada_Quality.Storage.Store; Pretty : Boolean := False) return String;
   --  Serialize every persisted project, assessment, detail, and regression.
   --  @param Store Open persistent store to read.
   --  @param Pretty Whether to indent the resulting document.
   --  @return Complete archive JSON document.
end Ada_Quality.JSON;
