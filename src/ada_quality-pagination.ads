with Ada.Containers.Vectors;

--  Shared, presentation-neutral pagination primitives.
package Ada_Quality.Pagination is
   type Page_Request is record
      Offset : Natural := 0;
      Limit  : Natural := 0;
   end record;

   type Page_Direction is (Forward, Backward);

   generic
      with package Item_Vectors is new Ada.Containers.Vectors (<>);
   package Vector_Pages is
      procedure Apply
        (Items     : in out Item_Vectors.Vector;
         Request   : Page_Request;
         Direction : Page_Direction := Forward);
      --  Retain the requested page without changing the relative order of its items.
   end Vector_Pages;

   generic
      with package Item_Vectors is new Ada.Containers.Vectors (<>);
   package Stream_Pages is
      procedure Consider
        (Items     : in out Item_Vectors.Vector;
         Item      : Item_Vectors.Element_Type;
         Total     : in out Natural;
         Request   : Page_Request);
      --  Count Item and retain it only when it belongs to the requested page.
      --  Backward callers supply newest items first and call Complete afterward.

      procedure Complete
        (Items     : in out Item_Vectors.Vector;
         Direction : Page_Direction := Forward);
      --  Restore display order after the page has been collected.
   end Stream_Pages;
end Ada_Quality.Pagination;
