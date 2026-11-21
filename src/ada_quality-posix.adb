package body Ada_Quality.POSIX is
   function Close_Succeeded
     (Descriptor : in out File_Descriptor) return Boolean
   is
      Result : Interfaces.C.int;
   begin
      if Descriptor < 0 then
         return True;
      end if;
      Result := Close_Raw (Descriptor);
      Descriptor := Invalid_Descriptor;
      return Result = 0;
   end Close_Succeeded;

   procedure Close (Descriptor : in out File_Descriptor) is
   begin
      if Descriptor >= 0 then
         declare
            Ignored : constant Boolean := Close_Succeeded (Descriptor);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end if;
   end Close;

end Ada_Quality.POSIX;
