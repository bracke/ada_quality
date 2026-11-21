with Ada.Containers;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada_Quality.Persistence;
with Ada_Quality.Reporting;
with Ada_Quality.Storage.Assessments;
with Ada_Quality.Storage.Integrity;
with Ada_Quality.Storage.Registry;
with Ada_Quality.Storage.Retention;
with Ada_Quality.Temporary_Directories;
with Database.Backup;
with Database.Export;
with Database.Import;
with Database.Predicates;
with Database.Restore;
with Database.Status;
with Database.Transactions;
with Database.Vacuum;
with Project_Tools.Files;

package body Ada_Quality.Storage.Transfer is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Persistence;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;
   use type Ada_Quality.Types.Result_Vectors.Vector;
   use type Ada_Quality.Types.Tool_Execution_Vectors.Vector;

   procedure Backup (Item : in out Store; Destination : String) is
   begin
      if Ada.Directories.Exists (Destination) then
         raise Storage_Error with
           "backup destination already exists: " & Destination;
      end if;
      Require_OK
        (Database.Backup.Create_Physical_Backup
           (Item.DB, Encode (Destination)),
         "create database backup");
   end Backup;

   procedure Export (Item : in out Store; Destination : String) is
      Tx     : Database.Transactions.Transaction;
      Status : Database.Status.Result;
   begin
      if Ada.Directories.Exists (Destination) then
         raise Storage_Error with
           "export destination already exists: " & Destination;
      end if;
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Database.Export.Export_Database
        (Tx, Encode (Destination));
      Require_OK (Status, "export database");
      Require_OK
        (Database.Transactions.Commit (Tx),
         "complete database export");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Export;

   procedure Restore (Source, Destination : String) is
   begin
      Require_OK
        (Database.Restore.Restore_Physical_Backup
           (Encode (Source), Encode (Destination)),
         "restore database backup");
   end Restore;

   procedure Import (Source, Destination : String) is
      DB : Database.Handle;
      Tx : Database.Transactions.Transaction;

      procedure Remove_If_Present (Path : String) is
      begin
         Project_Tools.Files.Delete_File_If_Present (Path);
      exception
         when others =>
            null;
      end Remove_If_Present;
   begin
      if Ada.Directories.Exists (Destination) then
         raise Storage_Error with
           "import destination already exists: " & Destination;
      elsif not Ada.Directories.Exists (Source) then
         raise Storage_Error with "logical export not found: " & Source;
      end if;
      Database.Create (DB, Encode (Destination));
      Require_OK
        (Database.Last_Result (DB), "create import destination");
      Database.Transactions.Begin_Write (DB, Tx);
      Require_OK
        (Database.Import.Import_Database (Tx, Encode (Source)),
         "import database");
      Require_OK
        (Database.Transactions.Commit (Tx), "commit database import");
      Database.Close (DB);
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         if Database.Is_Open (DB) then
            Database.Close (DB);
         end if;
         Remove_If_Present (Destination);
         Remove_If_Present (Destination & ".wal");
         Remove_If_Present (Destination & ".lock");
         raise;
   end Import;

   procedure Merge
     (Item : in out Store; Sources : Source_Vectors.Vector; Dry_Run : Boolean;
      Report : out Merge_Report)
   is separate;

   procedure Merge
     (Item : in out Store; Source : String;
      Added_Projects, Added_Assessments : out Natural)
   is
      Report  : Merge_Report;
      Sources : Source_Vectors.Vector;
   begin
      Sources.Append (To_Unbounded_String (Source));
      Merge (Item, Sources, Dry_Run => False, Report => Report);
      if not Report.Conflicts.Is_Empty then
         raise Storage_Error with "merge has alias conflicts";
      end if;
      Added_Projects := Report.Added_Projects;
      Added_Assessments := Report.Added_Assessments;
   end Merge;

   procedure Archive_And_Prune
     (Item        : in out Store;
      Destination : String;
      Before      : Ada.Calendar.Time;
      Keep        : Natural;
      Removed     : out Natural)
   is separate;

   function Retention_Candidates
     (Item : in out Store; Before : Ada.Calendar.Time; Keep : Natural)
      return History_Vectors.Vector is
     (Ada_Quality.Storage.Retention.Candidates (Item, Before, Keep));

   procedure Compact (Item : in out Store) is
      Tx : Database.Transactions.Transaction;
   begin
      if not Item.Opened then
         raise Storage_Error with "database is not open";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Require_OK (Database.Vacuum.Vacuum (Tx), "compact database");
      Require_OK
        (Database.Transactions.Commit (Tx), "commit database compaction");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Compact;
end Ada_Quality.Storage.Transfer;
