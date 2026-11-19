with Ada_Quality.Reporting;

private package Ada_Quality.Archive_JSON is
   function Render
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean;
      Max_Output_Bytes : Positive;
      Project_Id       : Natural;
      Since_Time       : Ada_Quality.Reporting.Optional_Timestamp;
      Until_Time       : Ada_Quality.Reporting.Optional_Timestamp) return String;
end Ada_Quality.Archive_JSON;
