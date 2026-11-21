with Ada.Containers;
with Ada.Containers.Ordered_Maps;
with Ada.Containers.Ordered_Sets;
with Ada.Containers.Vectors;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.Wide_Wide_Unbounded;
with Ada_Quality.Finding_Identity;
with Ada_Quality.Indicators;
with Ada_Quality.Persistence;
with Database.Catalog;
with Database.Predicates;
with Database.Status;
with Database.Transactions;

package body Ada_Quality.Storage.Integrity is
   use Ada.Strings.Unbounded;
   use Ada.Strings.Wide_Wide_Unbounded;
   use Ada_Quality.Persistence;
   use Ada_Quality.Types;
   use type Ada.Containers.Count_Type;

   Current_Schema_Version : constant String :=
     Ada.Strings.Fixed.Trim
       (Positive'Image (Ada_Quality.Persistence.Current_Schema_Version),
        Ada.Strings.Both);

   function Schema_Version (Item : in out Store) return Positive is
      Row    : Entity;
      Tx     : Database.Transactions.Transaction;
      Status : Database.Status.Result;
   begin
      Database.Transactions.Begin_Read (Item.DB, Tx);
      Status := Entity_Tables.Find
        (Tx, Item.DB, Item.Schemas (Metadata_Table), 1, Row);
      Require_OK (Status, "read schema version");
      Require_OK
        (Database.Transactions.Commit (Tx),
         "complete schema version read");
      return Positive'Value (S (Row.Payload));
   exception
      when others =>
         if Database.Transactions.Is_Active (Tx) then
            Database.Transactions.Rollback (Tx);
         end if;
         raise;
   end Schema_Version;

   procedure Check
     (Item : in out Store; Limits : Integrity_Limits := (others => <>))
   is separate;
end Ada_Quality.Storage.Integrity;
