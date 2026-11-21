--  Schema and integrity inspection capability for an open storage handle.
package Ada_Quality.Storage.Integrity is
   function Schema_Version (Item : in out Store) return Positive;
   --  Return the persisted logical schema version.

   procedure Check
     (Item : in out Store; Limits : Integrity_Limits := (others => <>));
   --  Validate schema, ownership, lifecycle, cardinality, and evidence invariants.
end Ada_Quality.Storage.Integrity;
