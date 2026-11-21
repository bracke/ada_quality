separate (Ada_Quality.JSON_Assessments)
function Render (Item : Assessment; Pretty : Boolean := False) return String is
      Doc  : Document;
      Root : constant Node := Doc.New_Object;
   begin
      Populate_Assessment (Doc, Root, Item);
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render;
