separate (Ada_Quality.JSON_Administration)
function Render_Command_Result
     (Command, Detail : String; Success : Boolean; Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("command-result"));
      Doc.Insert (Root, "command", Doc.New_String (Command));
      Doc.Insert (Root, "success", Doc.New_Boolean (Success));
      Doc.Insert (Root, "detail", Doc.New_String (Detail));
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Command_Result;
