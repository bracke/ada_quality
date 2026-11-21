separate (Ada_Quality.JSON_Reports)
function Render_Archive
     (Item             : Ada_Quality.Reporting.Session;
      Pretty           : Boolean := False;
      Max_Output_Bytes : Positive :=
        Ada_Quality.Resource_Limits.Maximum_Archive_Output_Bytes;
      Project_Id       : Natural := 0;
      Project_Tag      : String := "";
      Since_Time       : Ada_Quality.Reporting.Optional_Timestamp := (Present => False);
      Until_Time       : Ada_Quality.Reporting.Optional_Timestamp := (Present => False)) return String
   is
   begin
      return Ada_Quality.Archive_JSON.Render
        (Item, Pretty, Max_Output_Bytes, Project_Id, Project_Tag, Since_Time, Until_Time);
   end Render_Archive;
