with Ada_Quality.Reporting;
with Ada_Quality.Types;

--  Self-contained human-readable HTML reporting.
package Ada_Quality.HTML is
   function Render_Assessment (Item : Ada_Quality.Types.Assessment) return String;
   function Render_Portfolio
     (Item : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector) return String;
end Ada_Quality.HTML;
