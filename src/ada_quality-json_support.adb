with Ada.Strings.Unbounded;
with Jsonlib.Serializers;

package body Ada_Quality.JSON_Support is
   use Ada.Strings.Unbounded;
   use Jsonlib.Documents;

   function Serialize
     (Doc : Document; Pretty : Boolean) return String is
     (Jsonlib.Serializers.To_String
        (Doc,
         (Form =>
            (if Pretty
             then Jsonlib.Serializers.Pretty
             else Jsonlib.Serializers.Compact),
          Indent => 2, Escape_Non_Ascii => False, Sort_Members => True)));

   procedure Populate_Page
     (Doc : in out Document; Root : Node;
      Page : Ada_Quality.Command_Models.Page_Info)
   is
      Object : constant Node := Doc.New_Object;
   begin
      if not Page.Present then
         return;
      end if;
      Doc.Insert
        (Object, "total", Doc.New_Integer (Long_Long_Integer (Page.Total)));
      Doc.Insert
        (Object, "offset", Doc.New_Integer (Long_Long_Integer (Page.Offset)));
      Doc.Insert
        (Object, "limit", Doc.New_Integer (Long_Long_Integer (Page.Limit)));
      Doc.Insert
        (Object, "snapshot",
         Doc.New_Integer (Long_Long_Integer (Page.Snapshot)));
      if Length (Page.Next_Cursor) > 0 then
         Doc.Insert
           (Object, "next_cursor", Doc.New_String (To_String (Page.Next_Cursor)));
      end if;
      Doc.Insert (Root, "page", Object);
   end Populate_Page;
end Ada_Quality.JSON_Support;
