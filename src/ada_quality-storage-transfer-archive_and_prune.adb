separate (Ada_Quality.Storage.Transfer)
procedure Archive_And_Prune
  (Item        : in out Store;
   Destination : String;
   Before      : Ada.Calendar.Time;
   Keep        : Natural;
   Removed     : out Natural)
is
   package Id_Sets is new Ada.Containers.Ordered_Sets (Positive);
   Tx         : Database.Transactions.Transaction;
   Cursor     : Entity_Tables.Cursor;
   Status     : Database.Status.Result;
   Deleted    : Id_Sets.Set;
   Candidates : constant History_Vectors.Vector := Retention_Candidates (Item, Before, Keep);
begin
   if not Item.Opened then raise Storage_Error with "database is not open"; end if;
   Export (Item, Destination);
   Database.Transactions.Begin_Write (Item.DB, Tx);
   for Run of Candidates loop Deleted.Include (Run.Id); end loop;

   for Table in Indicator_Results_Table .. Events_Table loop
      declare
         Children : Entity_Vectors.Vector;
      begin
         Status := Entity_Tables.Scan
           (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
         Require_OK (Status, "scan archived assessment details");
         while Entity_Tables.Has_Element (Cursor) loop
            declare Row : constant Entity := Entity_Tables.Element (Cursor); begin
               if Row.Parent_Id > 0 and then Deleted.Contains (Positive (Row.Parent_Id)) then
                  Children.Append (Row);
               end if;
            end;
            Status := Entity_Tables.Next
              (Tx, Item.DB, Item.Schemas (Table), Database.Predicates.True_Predicate, Cursor);
            Require_OK (Status, "advance archived detail scan");
         end loop;
         for Row of Children loop
            Require_OK
              (Entity_Tables.Delete (Tx, Item.DB, Item.Schemas (Table), Row.Id),
               "delete archived assessment detail");
         end loop;
      end;
   end loop;
   for Id of Deleted loop
      Require_OK
        (Entity_Tables.Delete (Tx, Item.DB, Item.Schemas (Assessments_Table), Id),
         "delete archived assessment");
   end loop;
   Require_OK (Database.Transactions.Commit (Tx), "commit assessment retention");
   Removed := Natural (Deleted.Length);
exception
   when others =>
      if Database.Transactions.Is_Active (Tx) then Database.Transactions.Rollback (Tx); end if;
      raise;
end Archive_And_Prune;
