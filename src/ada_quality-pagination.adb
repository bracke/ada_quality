with Ada.Containers;

package body Ada_Quality.Pagination is
   package body Vector_Pages is
      use type Ada.Containers.Count_Type;

      procedure Apply
        (Items     : in out Item_Vectors.Vector;
         Request   : Page_Request;
         Direction : Page_Direction := Forward)
      is
         Offset_Count : constant Ada.Containers.Count_Type :=
           Ada.Containers.Count_Type (Request.Offset);
         Limit_Count  : constant Ada.Containers.Count_Type :=
           Ada.Containers.Count_Type (Request.Limit);
      begin
         if Direction = Forward then
            if Request.Offset > 0 then
               Items.Delete_First
                 (Ada.Containers.Count_Type'Min (Items.Length, Offset_Count));
            end if;
            if Request.Limit > 0 and then Items.Length > Limit_Count then
               Items.Delete_Last (Items.Length - Limit_Count);
            end if;
         else
            if Request.Offset > 0 then
               Items.Delete_Last
                 (Ada.Containers.Count_Type'Min (Items.Length, Offset_Count));
            end if;
            if Request.Limit > 0 and then Items.Length > Limit_Count then
               Items.Delete_First (Items.Length - Limit_Count);
            end if;
         end if;
      end Apply;
   end Vector_Pages;

   package body Stream_Pages is
      use type Ada.Containers.Count_Type;

      procedure Consider
        (Items     : in out Item_Vectors.Vector;
         Item      : Item_Vectors.Element_Type;
         Total     : in out Natural;
         Request   : Page_Request)
      is
         Position : constant Natural := Total;
      begin
         Total := Total + 1;
         if Position < Request.Offset or else
           (Request.Limit > 0 and then
            Items.Length >= Ada.Containers.Count_Type (Request.Limit))
         then
            return;
         else
            Items.Append (Item);
         end if;
      end Consider;

      procedure Complete
        (Items     : in out Item_Vectors.Vector;
         Direction : Page_Direction := Forward) is
      begin
         if Direction = Backward and then Items.Length > 1 then
            Item_Vectors.Reverse_Elements (Items);
         end if;
      end Complete;
   end Stream_Pages;
end Ada_Quality.Pagination;
