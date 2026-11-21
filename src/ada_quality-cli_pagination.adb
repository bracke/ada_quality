with Ada.Strings.Unbounded;
with Ada_Quality.CLI_Cursors;
with Interfaces;

package body Ada_Quality.CLI_Pagination is
   use Ada.Strings.Unbounded;
   use type Interfaces.Unsigned_32;

   function Assessment_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural
   is
      Result : Natural := 0;

      procedure Include (Run : Ada_Quality.Reporting.Run_Record) is
      begin
         Result := Natural'Max (Result, Run.Id);
      end Include;
   begin
      Ada_Quality.Reporting.Visit_Runs
        (Session, Process => Include'Access);
      return Result;
   end Assessment_Snapshot;

   function Alias_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural
   is
      Result : Natural := 0;

      procedure Include (Item : Ada_Quality.Reporting.Assessment_Alias) is
      begin
         Result := Natural'Max (Result, Item.Event_Id);
      end Include;
   begin
      Ada_Quality.Reporting.Visit_Aliases
        (Session, Process => Include'Access);
      return Result;
   end Alias_Snapshot;

   function Project_Snapshot
     (Session : Ada_Quality.Reporting.Session) return Natural
   is
      Result : Natural := 0;

      procedure Include (Project : Ada_Quality.Reporting.Project_Record) is
      begin
         Result := Natural'Max (Result, Project.Id);
      end Include;
   begin
      Ada_Quality.Reporting.Visit_Projects
        (Session, Include_Removed => True, Process => Include'Access);
      return Result;
   end Project_Snapshot;

   function Project_Revision
     (Session : Ada_Quality.Reporting.Session; Boundary : Natural)
      return Natural
   is
      Hash : Interfaces.Unsigned_32 := 16#811C9DC5#;

      procedure Mix (Text : String) is
      begin
         for Character_Item of Text loop
            Hash :=
              (Hash xor
                 Interfaces.Unsigned_32 (Character'Pos (Character_Item))) *
              16#01000193#;
         end loop;
         Hash := (Hash xor 255) * 16#01000193#;
      end Mix;

      procedure Include (Project : Ada_Quality.Reporting.Project_Record) is
      begin
         if Project.Id <= Boundary then
            Mix (Positive'Image (Project.Id));
            Mix (To_String (Project.Path));
            Mix (To_String (Project.Tags));
            Mix (Boolean'Image (Project.Enabled));
            Mix (Boolean'Image (Project.Removed));
         end if;
      end Include;
   begin
      Ada_Quality.Reporting.Visit_Projects
        (Session, Include_Removed => True, Process => Include'Access);
      declare
         Value : constant Natural := Natural (Hash and 16#7FFF_FFFF#);
      begin
         return (if Value = 0 then 1 else Value);
      end;
   end Project_Revision;

   function Page_Metadata
     (Total, Offset, Returned, Requested_Limit : Natural;
      Snapshot : Natural := 0;
      Secondary_Snapshot : Natural := 0;
      Tertiary_Snapshot : Natural := 0;
      Binding : Natural := 0) return Ada_Quality.Command_Models.Page_Info
   is
      Limit : constant Natural :=
        (if Requested_Limit = 0 then Returned else Requested_Limit);
      Next : Unbounded_String;
   begin
      if Offset + Returned < Total then
         Next := To_Unbounded_String
           (Ada_Quality.CLI_Cursors.Encode
              ((Version   => (if Binding > 0 then 5
                              elsif Tertiary_Snapshot > 0 then 4
                              elsif Secondary_Snapshot > 0 then 3
                              elsif Snapshot > 0 then 2 else 1),
                Binding   => Binding,
                Primary   => Snapshot,
                Secondary => Secondary_Snapshot,
                Tertiary  => Tertiary_Snapshot,
                Offset    => Offset),
               Offset + Returned));
      end if;
      return
        (Present => True, Total => Total, Offset => Offset, Limit => Limit,
         Next_Cursor => Next, Snapshot => Snapshot);
   end Page_Metadata;
end Ada_Quality.CLI_Pagination;
