with Ada_Quality.History_Data;
with Ada_Quality.JSON_Reports;
with Ada_Quality.Storage.Registry;

separate (Ada_Quality.CLI)
function Run_Trend (DB_Path : String) return Natural is
   Session      : Ada_Quality.Reporting.Session;
   Project_Id   : constant Positive := Positive_Option ("--project", "project");
   All_Metrics  : constant Boolean := Has_Flag ("--all");
   Format       : constant String :=
     Selected_Output_Format
       ("text", "text|json|csv", "trend format requires text, json, or csv");
   From_Run     : Natural := 0;
   To_Run       : Natural := 0;
   Since_Time   : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--since");
   Until_Time   : constant Ada_Quality.Reporting.Optional_Timestamp := Timestamp_Option ("--until");
   Series       : Ada_Quality.Command_Models.Metric_Series_Vectors.Vector;
   Runs         : Ada_Quality.Reporting.Run_Vectors.Vector;
   Measurements : Ada_Quality.History_Data.Detail_Vectors.Vector;
   type Measurement_Bucket_Array is
     array (Indicator_Id) of Ada_Quality.History_Data.Detail_Vectors.Vector;
   Measurement_Buckets : Measurement_Bucket_Array;
   use type Ada.Calendar.Time;

   function Filter_Points
     (Points : Ada_Quality.History.Trend_Vectors.Vector)
      return Ada_Quality.History.Trend_Vectors.Vector
   is
      Result    : Ada_Quality.History.Trend_Vectors.Vector;
      Run_Index : Natural := (if Runs.Is_Empty then 0 else Runs.First_Index);
   begin
      for Point of Points loop
         while Run_Index /= 0 and then Runs (Run_Index).Id < Point.Run_Id loop
            Run_Index := (if Run_Index = Runs.Last_Index then 0 else Run_Index + 1);
         end loop;
         if Run_Index /= 0 and then Runs (Run_Index).Id = Point.Run_Id and then
           (From_Run = 0 or else Point.Run_Id >= From_Run) and then
           (To_Run = 0 or else Point.Run_Id <= To_Run) and then
           In_Time_Range (Runs (Run_Index).Finished_At, Since_Time, Until_Time)
         then
            Result.Append (Point);
         end if;
      end loop;
      return Result;
   end Filter_Points;

   procedure Add_Series (Indicator : Indicator_Id) is
      All_Points : constant Ada_Quality.History.Trend_Vectors.Vector :=
        Ada_Quality.History.Metric_Trend
          (Ada_Quality.Reporting.History_Items (Session, Project_Id),
           Measurement_Buckets (Indicator), Indicator);
      Points : constant Ada_Quality.History.Trend_Vectors.Vector :=
        Filter_Points (All_Points);
   begin
      Series.Append
        (Ada_Quality.Command_Models.Metric_Series'
           (Indicator => Indicator,
            Unit_Name => To_Unbounded_String (Ada_Quality.Indicators.Measurement_Unit (Indicator)),
            Points => Points));
   end Add_Series;

   procedure Validate_Request is
   begin
      if All_Metrics = (Option ("--indicator", "") /= "") then
         raise Usage_Error with
           "trend requires exactly one of --indicator ID or --all";
      elsif Since_Time.Present and then Until_Time.Present and then
        Since_Time.Value > Until_Time.Value
      then
         raise Usage_Error with "--since must not be later than --until";
      end if;
   end Validate_Request;

   procedure Resolve_Bounds is
   begin
      Ada_Quality.Reporting.Open (Session, DB_Path);
      if Option ("--from-run", "") /= "" then
         From_Run := Ada_Quality.Reporting.Resolve_Assessment
           (Session, Option ("--from-run", ""));
      end if;
      if Option ("--to-run", "") /= "" then
         To_Run := Ada_Quality.Reporting.Resolve_Assessment
           (Session, Option ("--to-run", ""));
      end if;
      if From_Run > 0 and then To_Run > 0 and then From_Run > To_Run then
         raise Usage_Error with "--from-run must not exceed --to-run";
      end if;
   end Resolve_Bounds;

   procedure Validate_Project is
   begin
      declare
         P : constant Ada_Quality.Reporting.Project_Record :=
           Ada_Quality.Reporting.Project (Session, Project_Id);
      begin
         if Option ("--tag", "") /= "" and then
           not Ada_Quality.Storage.Registry.Is_Tag_Name (Option ("--tag", ""))
         then
            raise Usage_Error with
              "--tag requires lowercase letters, digits, hyphens, or underscores";
         elsif Option ("--tag", "") /= "" and then
           not Has_Tag (To_String (P.Tags), Option ("--tag", ""))
         then
            raise Usage_Error with
              "trend project does not have the requested tag";
         end if;
      end;
   end Validate_Project;

   procedure Build_Series is
   begin
      Runs := Ada_Quality.Reporting.Runs (Session, Project_Id);
      Measurements := Ada_Quality.Reporting.All_Measurements (Session, Project_Id);
      for Measurement of Measurements loop
         declare
            Indicator : Indicator_Id;
         begin
            if Ada_Quality.Indicators.Parse_Canonical
              (To_String (Measurement.Kind), Indicator)
            then
               Measurement_Buckets (Indicator).Append (Measurement);
            end if;
         end;
      end loop;
      Measurements.Clear;
      if All_Metrics then
         for Indicator in Indicator_Id loop
            if Ada_Quality.Indicators.Direction_Of (Indicator) /= Ada_Quality.Indicators.No_Trend then
               Add_Series (Indicator);
            end if;
         end loop;
      else
         declare
            Indicator : Indicator_Id;
         begin
            if not Ada_Quality.Indicators.Parse_Canonical (Option ("--indicator", ""), Indicator) then
               raise Usage_Error with "--indicator requires a canonical indicator ID";
            end if;
            Add_Series (Indicator);
         end;
      end if;
   end Build_Series;

   procedure Emit_JSON is
   begin
      Terminal_Styles.Set_Color_Policy (Terminal_Styles.Color_Never);
      if All_Metrics then
         Emit_Document
           (Ada_Quality.JSON_Reports.Render_Trends
              (Project_Id, Series, Pretty => True));
      else
         declare
            Series_Item : constant Ada_Quality.Command_Models.Metric_Series := Series.First_Element;
         begin
            Emit_Document
              (Ada_Quality.JSON_Reports.Render_Trend
                 (Project_Id, Series_Item.Indicator, To_String (Series_Item.Unit_Name),
                  Series_Item.Points, Pretty => True));
         end;
      end if;
   end Emit_JSON;

   procedure Emit_CSV is
   begin
      declare
         Output : Ada.Strings.Unbounded.Unbounded_String := To_Unbounded_String
           ("project_id,indicator,unit,run_id,value" & ASCII.LF);
      begin
      for Series_Item of Series loop
         for Point of Series_Item.Points loop
            Append
              (Output,
              (Ada.Strings.Fixed.Trim (Positive'Image (Project_Id), Ada.Strings.Both) & "," &
               Image (Series_Item.Indicator) & "," & To_String (Series_Item.Unit_Name) & "," &
               Ada.Strings.Fixed.Trim (Positive'Image (Point.Run_Id), Ada.Strings.Both) & "," &
               Ada.Strings.Fixed.Trim (Long_Long_Integer'Image (Point.Value), Ada.Strings.Both) & ASCII.LF));
         end loop;
      end loop;
      Emit_Document (To_String (Output));
      end;
   end Emit_CSV;

   procedure Emit_Text is
   begin
      declare Output : Ada.Strings.Unbounded.Unbounded_String; begin
      for Series_Item of Series loop
         if Series_Item.Points.Is_Empty then
            Append
              (Output,
              ("project" & Positive'Image (Project_Id) & " " & Image (Series_Item.Indicator) &
               ": no compatible numeric trend" & ASCII.LF));
         else
            for Point of Series_Item.Points loop
               Append
                 (Output,
                 ("run" & Positive'Image (Point.Run_Id) & " " & Image (Series_Item.Indicator) & "=" &
                  Long_Long_Integer'Image (Point.Value) & " " & To_String (Series_Item.Unit_Name) & ASCII.LF));
            end loop;
         end if;
      end loop;
      Emit_Document (To_String (Output));
      end;
   end Emit_Text;

   procedure Emit_Result is
   begin
      if Format = "json" then
         Emit_JSON;
      elsif Format = "csv" then
         Emit_CSV;
      else
         Emit_Text;
      end if;
   end Emit_Result;
begin
   Validate_Request;
   Resolve_Bounds;
   Validate_Project;
   Build_Series;
   Emit_Result;
   return 0;
end Run_Trend;
