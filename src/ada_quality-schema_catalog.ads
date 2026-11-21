--  Canonical inventory of the public JSON schemas shipped with Ada Quality.
package Ada_Quality.Schema_Catalog is
   Schema_Count : constant Positive := 29;
   subtype Schema_Index is Positive range 1 .. Schema_Count;

   function Name (Index : Schema_Index) return String;
end Ada_Quality.Schema_Catalog;
