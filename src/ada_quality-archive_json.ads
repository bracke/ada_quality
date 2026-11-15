with Ada_Quality.Reporting;

private package Ada_Quality.Archive_JSON is
   function Render
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean;
      Max_Output_Bytes : Positive) return String;
end Ada_Quality.Archive_JSON;
