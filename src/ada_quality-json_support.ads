with Ada_Quality.Command_Models;
with Jsonlib.Documents;

--  Shared deterministic JSON document mechanics for domain renderers.
package Ada_Quality.JSON_Support is
   function Serialize
     (Doc : Jsonlib.Documents.Document; Pretty : Boolean) return String;

   procedure Populate_Page
     (Doc  : in out Jsonlib.Documents.Document;
      Root : Jsonlib.Documents.Node;
      Page : Ada_Quality.Command_Models.Page_Info);
end Ada_Quality.JSON_Support;
