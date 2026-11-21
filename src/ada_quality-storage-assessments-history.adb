separate (Ada_Quality.Storage.Assessments)
function History (Item : in out Store; Project_Id : Natural := 0) return History_Vectors.Vector is
   function Less (Left, Right : History_Item) return Boolean is
     (Left.Id < Right.Id);
   package Sorting is new History_Vectors.Generic_Sorting ("<" => Less);
   Tx     : Database.Transactions.Transaction;
   Cursor : Entity_Tables.Cursor;
   Status : Database.Status.Result;
   Result : History_Vectors.Vector;
   Row    : Entity;
begin
   Database.Transactions.Begin_Read (Item.DB, Tx);
   Status := Entity_Tables.Scan
     (Tx, Item.DB, Item.Schemas (Assessments_Table), Database.Predicates.True_Predicate, Cursor);
   Require_OK (Status, "scan history");
   while Entity_Tables.Has_Element (Cursor) loop
      Row := Entity_Tables.Element (Cursor);
      if Project_Id = 0 or else Row.Parent_Id = Project_Id then
         Result.Append
           (History_Item'(Id => Row.Id, Project_Id => Positive (Row.Parent_Id),
            Status => To_Unbounded_String (S (Row.State)), Summary => To_Unbounded_String (S (Row.Payload)),
            Source_Fingerprint => To_Unbounded_String (Field (S (Row.Payload), "source")),
            Policy_Fingerprint => To_Unbounded_String (Field (S (Row.Payload), "policy")),
            Toolchain_Fingerprint => To_Unbounded_String (Field (S (Row.Payload), "toolchain"))));
      end if;
      Status := Entity_Tables.Next
        (Tx, Item.DB, Item.Schemas (Assessments_Table), Database.Predicates.True_Predicate, Cursor);
      Require_OK (Status, "advance history");
   end loop;
   Require_OK (Database.Transactions.Commit (Tx), "complete history query");
   Sorting.Sort (Result);
   return Result;
end History;
