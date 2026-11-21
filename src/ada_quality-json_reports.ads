with Ada_Quality.Checks;
with Ada_Quality.Command_Models;
with Ada_Quality.History;
with Ada_Quality.Indicators;
with Ada_Quality.Reporting;
with Ada_Quality.Resource_Limits;
with Ada_Quality.Types;

--  Read-model and reporting JSON contracts.
package Ada_Quality.JSON_Reports is
   function Render_Archive
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean := False;
      Max_Output_Bytes : Positive :=
        Ada_Quality.Resource_Limits.Maximum_Archive_Output_Bytes;
      Project_Id       : Natural := 0;
      Project_Tag      : String := "";
      Since_Time       : Ada_Quality.Reporting.Optional_Timestamp :=
        (Present => False);
      Until_Time       : Ada_Quality.Reporting.Optional_Timestamp :=
        (Present => False)) return String;

   function Render_Trend
     (Project_Id : Positive;
      Indicator  : Ada_Quality.Types.Indicator_Id;
      Unit_Name  : String;
      Points     : Ada_Quality.History.Trend_Vectors.Vector;
      Pretty     : Boolean := False) return String;

   function Render_Trends
     (Project_Id : Positive;
      Series     : Ada_Quality.Command_Models.Metric_Series_Vectors.Vector;
      Pretty     : Boolean := False) return String;

   function Render_History
     (Items : Ada_Quality.Reporting.Run_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;

   function Render_Status
     (Item : Ada_Quality.Reporting.Session;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;

   function Render_Status
     (Item     : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page     : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty   : Boolean := False) return String;

   function Render_Scan
     (Project_Id : Positive;
      Metrics    : Ada_Quality.Checks.Source_Analysis;
      Pretty     : Boolean := False) return String;

   function Render_Findings
     (Items : Ada_Quality.Types.Finding_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;

   function Render_Projects
     (Items : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page : Ada_Quality.Command_Models.Page_Info := (others => <>);
      Pretty : Boolean := False) return String;

   function Render_Discovery
     (Items : Ada_Quality.Command_Models.Discovery_Vectors.Vector;
      Pretty : Boolean := False) return String;

   function Render_Statistics
     (Item : Ada_Quality.Reporting.Snapshot_Statistics;
      Pretty : Boolean := False) return String;

   function Render_Indicators
     (Filter_Category : Boolean := False;
      Category : Ada_Quality.Indicators.Indicator_Category :=
        Ada_Quality.Indicators.Structure;
      Pretty : Boolean := False) return String;

   function Render_Comparisons
     (Items : Ada_Quality.Command_Models.Comparison_Vectors.Vector;
      Pretty : Boolean := False) return String;
end Ada_Quality.JSON_Reports;
