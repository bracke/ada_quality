with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada_Quality.Archive_JSON;
with Ada_Quality.JSON_Support;
with Jsonlib.Documents;

package body Ada_Quality.JSON_Reports is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Command_Models;
   use Ada_Quality.Types;
   use type Ada_Quality.Indicators.Indicator_Category;
   use Jsonlib.Documents;

   function Serialize
     (Doc : Document; Pretty : Boolean) return String
      renames Ada_Quality.JSON_Support.Serialize;

   procedure Populate_Page
     (Doc : in out Document; Root : Node; Page : Page_Info)
      renames Ada_Quality.JSON_Support.Populate_Page;

   procedure Populate_Trend_Points
     (Doc : in out Document;
      Parent : Node;
      Points : Ada_Quality.History.Trend_Vectors.Vector)
   is
      Items : constant Node := Doc.New_Array;
   begin
      for Point of Points loop
         declare
            Item : constant Node := Doc.New_Object;
         begin
            Doc.Insert
              (Item, "run_id",
               Doc.New_Integer (Long_Long_Integer (Point.Run_Id)));
            Doc.Insert (Item, "value", Doc.New_Integer (Point.Value));
            Doc.Append (Items, Item);
         end;
      end loop;
      Doc.Insert (Parent, "points", Items);
   end Populate_Trend_Points;

   function Status_Image (Value : Assessment_Status) return String is
     (case Value is
         when Assessment_Running     => "running",
         when Assessment_Completed   => "completed",
         when Assessment_Invalid     => "invalid",
         when Assessment_Interrupted => "interrupted");

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
        (Present => False)) return String is separate;
   function Render_Trend
     (Project_Id : Positive;
      Indicator  : Indicator_Id;
      Unit_Name  : String;
      Points     : Ada_Quality.History.Trend_Vectors.Vector;
      Pretty     : Boolean := False) return String is separate;
   function Render_Trends
     (Project_Id : Positive;
      Series     : Metric_Series_Vectors.Vector;
      Pretty     : Boolean := False) return String is separate;
   function Render_History
     (Items : Ada_Quality.Reporting.Run_Vectors.Vector;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String is separate;

   function Render_Status
     (Item     : Ada_Quality.Reporting.Session;
      Projects : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page     : Page_Info := (others => <>);
      Pretty   : Boolean := False) return String
   is
      Doc   : Document;
      Root  : constant Node := Doc.New_Object;
      Nodes : constant Node := Doc.New_Array;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("portfolio-status"));
      for Project of Projects loop
         declare
            Object : constant Node := Doc.New_Object;
            Runs   : Ada_Quality.Reporting.Run_Vectors.Vector :=
              Ada_Quality.Reporting.Runs (Item, Project.Id);
         begin
            if Page.Present then
               while not Runs.Is_Empty
                 and then Runs.Last_Element.Id > Page.Snapshot
               loop
                  Runs.Delete_Last;
               end loop;
            end if;
            declare
               Comparison : constant Ada_Quality.Reporting.Project_Comparison :=
                 (if Runs.Is_Empty then
                     (Project_Id => Project.Id,
                      Selection  => (others => <>),
                      Changes    => <>)
                  else Ada_Quality.Reporting.Compare_Project
                    (Item, Project.Id, Runs.Last_Element.Id));
            begin
               Doc.Insert
                 (Object, "project_id",
                  Doc.New_Integer (Long_Long_Integer (Project.Id)));
               Doc.Insert
                 (Object, "path", Doc.New_String (To_String (Project.Path)));
               Doc.Insert
                 (Object, "enabled", Doc.New_Boolean (Project.Enabled));
               if Runs.Is_Empty then
                  Doc.Insert
                    (Object, "latest_assessment_id", Doc.New_Integer (0));
                  Doc.Insert
                    (Object, "latest_status", Doc.New_String ("never"));
                  Doc.Insert (Object, "started_at", Doc.New_String (""));
               else
                  declare
                     Run : constant Ada_Quality.Reporting.Run_Record :=
                       Runs.Last_Element;
                  begin
                     Doc.Insert
                       (Object, "latest_assessment_id",
                        Doc.New_Integer (Long_Long_Integer (Run.Id)));
                     Doc.Insert
                       (Object, "latest_status",
                        Doc.New_String (Status_Image (Run.State)));
                     Doc.Insert
                       (Object, "started_at",
                        Doc.New_String
                          (Ada_Quality.Reporting.Image (Run.Started_At)));
                  end;
               end if;
               Doc.Insert
                 (Object, "comparison_status",
                  Doc.New_String
                    (Ada_Quality.History.Image (Comparison.Selection.Status)));
               Doc.Insert
                 (Object, "regression_count",
                  Doc.New_Integer
                    (Long_Long_Integer (Comparison.Changes.Length)));
               Doc.Append (Nodes, Object);
            end;
         end;
      end loop;
      Doc.Insert (Root, "projects", Nodes);
      Populate_Page (Doc, Root, Page);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Status;

   function Render_Status
     (Item : Ada_Quality.Reporting.Session;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String is
   begin
      return Render_Status
        (Item, Ada_Quality.Reporting.Projects (Item), Page, Pretty);
   end Render_Status;

   function Render_Scan
     (Project_Id : Positive;
      Metrics : Ada_Quality.Checks.Source_Analysis;
      Pretty : Boolean := False) return String is separate;
   function Render_Findings
     (Items : Finding_Vectors.Vector;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String is separate;
   function Render_Projects
     (Items : Ada_Quality.Reporting.Project_Vectors.Vector;
      Page : Page_Info := (others => <>);
      Pretty : Boolean := False) return String is separate;
   function Render_Discovery
     (Items : Discovery_Vectors.Vector;
      Pretty : Boolean := False) return String is separate;
   function Render_Statistics
     (Item : Ada_Quality.Reporting.Snapshot_Statistics;
      Pretty : Boolean := False) return String is separate;
   function Render_Indicators
     (Filter_Category : Boolean := False;
      Category : Ada_Quality.Indicators.Indicator_Category :=
        Ada_Quality.Indicators.Structure;
      Pretty : Boolean := False) return String is separate;
   function Render_Comparisons
     (Items : Comparison_Vectors.Vector;
      Pretty : Boolean := False) return String is separate;
end Ada_Quality.JSON_Reports;
