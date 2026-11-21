with Ada.Calendar;

--  Backup, import, merge, retention, and compaction capability.
package Ada_Quality.Storage.Transfer is
   procedure Backup (Item : in out Store; Destination : String);
   --  Create and verify a new physical backup directory.

   procedure Export (Item : in out Store; Destination : String);
   --  Create and verify a new database-native logical export.

   procedure Restore (Source, Destination : String);
   --  Restore a physical backup into a new database file.

   procedure Import (Source, Destination : String);
   --  Import a logical export into a new database file.

   procedure Merge
     (Item : in out Store; Sources : Source_Vectors.Vector; Dry_Run : Boolean;
      Report : out Merge_Report);
   --  Preflight all Sources together and optionally commit the combined plan.

   procedure Merge
     (Item : in out Store; Source : String;
      Added_Projects, Added_Assessments : out Natural);
   --  Merge one source and return its added project and assessment counts.

   procedure Archive_And_Prune
     (Item        : in out Store;
      Destination : String;
      Before      : Ada.Calendar.Time;
      Keep        : Natural;
      Removed     : out Natural);
   --  Verify a full archive before transactionally pruning old terminal runs.

   function Retention_Candidates
     (Item : in out Store; Before : Ada.Calendar.Time; Keep : Natural)
      return History_Vectors.Vector;
   --  Return the exact terminal assessments selected by the retention policy.

   procedure Compact (Item : in out Store);
   --  Reclaim unused pages inside one exclusive transaction.
end Ada_Quality.Storage.Transfer;
