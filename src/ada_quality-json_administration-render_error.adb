separate (Ada_Quality.JSON_Administration)
function Render_Error
     (Code, Message, Command : String; Exit_Status : Natural;
      Pretty : Boolean := False) return String
   is
      Doc : Document; Root : constant Node := Doc.New_Object;
   begin
      Doc.Insert (Root, "schema_version", Doc.New_Integer (1));
      Doc.Insert (Root, "kind", Doc.New_String ("error"));
      Doc.Insert (Root, "code", Doc.New_String (Code));
      Doc.Insert (Root, "message", Doc.New_String (Message));
      Doc.Insert (Root, "command", Doc.New_String (Command));
      Doc.Insert (Root, "exit_status", Doc.New_Integer (Long_Long_Integer (Exit_Status)));
      Doc.Set_Root (Root);
      return Serialize (Doc, Pretty);
   end Render_Error;
