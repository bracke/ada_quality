with Ada_Quality.Command_Models;
with Ada_Quality.Reporting;

--  Snapshot identities and cursor page metadata shared by CLI read commands.
package Ada_Quality.CLI_Pagination is
   function Assessment_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural;
   function Alias_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural;
   function Project_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural;
   function Project_Revision
     (Session : Ada_Quality.Reporting.Session; Boundary : Natural)
      return Natural;

   function Page_Metadata
     (Total, Offset, Returned, Requested_Limit : Natural;
      Snapshot : Natural := 0;
      Secondary_Snapshot : Natural := 0;
      Tertiary_Snapshot : Natural := 0;
      Binding : Natural := 0) return Ada_Quality.Command_Models.Page_Info;
end Ada_Quality.CLI_Pagination;
