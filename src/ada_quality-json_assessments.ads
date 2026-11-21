with Ada_Quality.Command_Models;
with Ada_Quality.Reporting;
with Ada_Quality.Types;

--  Assessment-oriented JSON contracts.  Ada_Quality.JSON remains the
--  compatibility facade for existing callers.
package Ada_Quality.JSON_Assessments is
   function Render
     (Item : Ada_Quality.Types.Assessment;
      Pretty : Boolean := False) return String;

   function Render_Batch
     (Items : Ada_Quality.Command_Models.Batch_Outcome_Vectors.Vector;
      Pretty : Boolean := False) return String;

   function Render_Reuse
     (Project_Id, Assessment_Id : Positive;
      Pretty : Boolean := False) return String;

   function Render_Check_Plan
     (Items : Ada_Quality.Command_Models.Check_Plan_Vectors.Vector;
      Pretty : Boolean := False) return String;

   function Render_Comparison
     (Item : Ada_Quality.Reporting.Project_Comparison;
      Pretty : Boolean := False) return String;

   function Render_Aliases
     (Items : Ada_Quality.Reporting.Alias_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;
end Ada_Quality.JSON_Assessments;
