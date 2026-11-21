with Ada.Strings.Unbounded;
with Ada_Quality.Persistence;
with Ada_Quality.Storage.Registry;
with Database.Predicates;
with Database.Status;
with Database.Transactions;

package body Ada_Quality.Storage.Assessments is
   use Ada.Strings.Unbounded;
   use Ada_Quality.Persistence;
   use Ada_Quality.Types;

   function Start
     (Item               : in out Store;
      Project_Id         : Positive;
      Source_Fingerprint : String;
      Policy_Fingerprint : String) return Positive
   is
      Registered : constant Project_Info :=
        Ada_Quality.Storage.Registry.Project (Item, Project_Id);
      Run_Id   : Positive := 1;
      Event_Id : Positive := 1;
      Tx       : Database.Transactions.Transaction;
      Status   : Database.Status.Result;
   begin
      if not Ada_Quality.Types.Fingerprint_Is_Valid (Source_Fingerprint) or else
        not Ada_Quality.Types.Fingerprint_Is_Valid (Policy_Fingerprint)
      then
         raise Storage_Error with
           "assessment fingerprints must be nonempty single-line identities";
      elsif Registered.Removed or else not Registered.Enabled then
         raise Storage_Error with
           "assessment project must be active and enabled";
      end if;
      Run_Id := Next_Id (Item, Assessments_Table);
      Event_Id := Next_Id (Item, Events_Table);
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Assessments_Table),
         (Id => Run_Id, Parent_Id => Project_Id,
          Kind => WW ("assessment"), State => WW ("running"),
          Payload => WW
            (Assessment_Payload
               (Source_Fingerprint, Policy_Fingerprint, "",
                Started_At => UTC_Now)),
          Active => False));
      Require_OK (Status, "start assessment");
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Events_Table),
         (Id => Event_Id, Parent_Id => Run_Id,
          Kind => WW ("started"), State => WW ("running"),
          Payload => WW ("assessment created before external tools"),
          Active => True));
      Require_OK (Status, "record assessment start");
      Trigger_Testing_Fault (Item, Assessment_Start_Commit);
      Require_OK
        (Database.Transactions.Commit (Tx), "commit assessment start");
      return Run_Id;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Start;

   function Publish
     (Item : in out Store; Value : Ada_Quality.Types.Assessment) return Positive
   is separate;

   procedure Add_Alias
     (Item : in out Store; Run_Id : Positive; Name : String)
   is
      Event_Id : Positive := 1;
      Tx       : Database.Transactions.Transaction;
      Cursor   : Entity_Tables.Cursor;
      Run_Row  : Entity;
      Status   : Database.Status.Result;
   begin
      if not Assessment_Alias_Is_Valid (Name) then
         raise Storage_Error with
           "assessment alias must begin with a lowercase letter and contain only lowercase letters," &
           " digits, dots, underscores, or hyphens (maximum 64 characters)";
      end if;
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Id, Run_Row);
      Require_OK (Status, "load assessment for alias");
      if S (Run_Row.State) /= "completed" then
         raise Storage_Error with "only completed assessments may be aliased";
      end if;
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Events_Table),
         Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan assessment aliases");
      while Entity_Tables.Has_Element (Cursor) loop
         declare
            Row : constant Entity := Entity_Tables.Element (Cursor);
         begin
            if S (Row.Kind) = "alias" and then S (Row.Payload) = Name then
               raise Storage_Error with "assessment alias already exists: " & Name;
            end if;
         end;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Events_Table),
            Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance assessment alias scan");
      end loop;
      Event_Id := Next_Id (Item, Events_Table);
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Events_Table),
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("alias"),
          State => WW ("alias"), Payload => WW (Name), Active => True));
      Require_OK (Status, "record assessment alias");
      Require_OK
        (Database.Transactions.Commit (Tx), "commit assessment alias");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Add_Alias;

   procedure Interrupt
     (Item : in out Store; Run_Id : Positive; Reason : String)
   is
      Event_Id : constant Positive := Next_Id (Item, Events_Table);
      Tx       : Database.Transactions.Transaction;
      Row      : Entity;
      Status   : Database.Status.Result;
   begin
      Database.Transactions.Begin_Write (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Assessments_Table), Run_Id, Row);
      Require_OK (Status, "load assessment to interrupt");
      if S (Row.State) /= "running" then
         Database.Transactions.Rollback (Tx);
         return;
      end if;
      Row.State := WW ("interrupted");
      Row.Active := False;
      Row.Payload := WW (With_Field (S (Row.Payload), "finished_at", UTC_Now));
      Status := Entity_Tables.Update
        (Tx, Item.DB, Item.Schemas (Assessments_Table), Row);
      Require_OK (Status, "mark assessment interrupted");
      Status := Entity_Tables.Insert
        (Tx, Item.DB, Item.Schemas (Events_Table),
         (Id => Event_Id, Parent_Id => Run_Id, Kind => WW ("interrupted"),
          State => WW ("interrupted"), Payload => WW (Reason), Active => True));
      Require_OK (Status, "record assessment interruption");
      Trigger_Testing_Fault (Item, Assessment_Interruption_Commit);
      Require_OK
        (Database.Transactions.Commit (Tx), "commit assessment interruption");
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Interrupt;

   procedure Recover (Item : in out Store; Count : out Natural) is
      Runs   : constant History_Vectors.Vector := History (Item);
      Tx     : Database.Transactions.Transaction;
      Row    : Entity;
      Status : Database.Status.Result;
   begin
      Count := 0;
      for Run of Runs loop
         if To_String (Run.Status) = "running" then
            declare
               Event_Id : constant Positive := Next_Id (Item, Events_Table);
            begin
               Database.Transactions.Begin_Write (Item.DB, Tx);
               Status := Entity_Tables.Find
                 (Tx, Item.DB, Item.Schemas (Assessments_Table), Run.Id, Row);
               Require_OK (Status, "load abandoned assessment");
               Row.State := WW ("interrupted");
               Row.Active := False;
               Row.Payload :=
                 WW (With_Field (S (Row.Payload), "finished_at", UTC_Now));
               Status := Entity_Tables.Update
                 (Tx, Item.DB, Item.Schemas (Assessments_Table), Row);
               Require_OK (Status, "mark assessment interrupted");
               Status := Entity_Tables.Insert
                 (Tx, Item.DB, Item.Schemas (Events_Table),
                  (Id => Event_Id, Parent_Id => Run.Id, Kind => WW ("recovered"),
                   State => WW ("interrupted"),
                   Payload => WW ("abandoned running assessment"),
                   Active => True));
               Require_OK (Status, "record assessment recovery");
               Trigger_Testing_Fault (Item, Assessment_Recovery_Commit);
               Require_OK
                 (Database.Transactions.Commit (Tx), "commit recovery");
               Count := Count + 1;
            exception
               when others =>
                  if Database.Transactions.Is_Active (Tx) then
                     Database.Transactions.Rollback (Tx);
                  end if;
                  raise;
            end;
         end if;
      end loop;
   end Recover;

   function History
     (Item : in out Store; Project_Id : Natural := 0)
      return History_Vectors.Vector
   is separate;

   function Details
     (Item : in out Store; Table : Positive; Run_Id : Natural)
      return Detail_Vectors.Vector
   is
      function Less (Left, Right : Detail_Info) return Boolean is
        (Left.Id < Right.Id);
      package Sorting is new Detail_Vectors.Generic_Sorting ("<" => Less);
      Tx     : Database.Transactions.Transaction;
      Cursor : Entity_Tables.Cursor;
      Status : Database.Status.Result;
      Result : Detail_Vectors.Vector;
      Row    : Entity;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Scan
        (Tx, Item.DB, Item.Schemas (Table),
         Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "scan details");
      while Entity_Tables.Has_Element (Cursor) loop
         Row := Entity_Tables.Element (Cursor);
         if Run_Id = 0 or else Row.Parent_Id = Run_Id then
            Result.Append
              (Detail_Info'
                 (Id => Row.Id, Run_Id => Positive (Row.Parent_Id),
                  Kind => To_Unbounded_String (S (Row.Kind)),
                  State => To_Unbounded_String (S (Row.State)),
                  Summary => To_Unbounded_String (S (Row.Payload))));
         end if;
         Status := Entity_Tables.Next
           (Tx, Item.DB, Item.Schemas (Table),
            Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "advance details");
      end loop;
      Require_OK
        (Database.Transactions.Commit (Tx), "complete details query");
      Sorting.Sort (Result);
      return Result;
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Details;

   function Results
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector is
     (Details (Item, Indicator_Results_Table, Run_Id));

   function Measurements
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector is
     (Details (Item, Measurements_Table, Run_Id));

   function Findings
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector is
     (Details (Item, Findings_Table, Run_Id));

   function Executions
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector is
     (Details (Item, Executions_Table, Run_Id));

   function Events
     (Item : in out Store; Run_Id : Natural := 0)
      return Detail_Vectors.Vector is
     (Details (Item, Events_Table, Run_Id));
end Ada_Quality.Storage.Assessments;
