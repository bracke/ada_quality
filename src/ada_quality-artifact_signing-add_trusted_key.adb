separate (Ada_Quality.Artifact_Signing)
function Add_Trusted_Key (Store, Public_Key_Path : String) return String is
   Content : constant String := Formatted_Content (Public_Key_Path, Public_Format);
   Public : Key_Array;

   function Existing_Content_Matches (Name : String) return Boolean is
      Directory_FD : Interfaces.C.int := -1;
      Key_FD       : Interfaces.C.int := -1;
   begin
      Directory_FD := Open_Directory_Nofollow (Interfaces.C.To_C (Store));
      if Directory_FD < 0 then
         raise Signing_Error with "cannot open trust store securely: " & Store;
      end if;
      Key_FD := Open_Child_Nofollow
        (Directory_FD, Interfaces.C.To_C (Name));
      if Key_FD < 0 then
         if not Close_Succeeded (Directory_FD) then
            raise Signing_Error with "cannot close trust store securely: " & Store;
         end if;
         return False;
      elsif Descriptor_Kind (Key_FD) /= 1 then
         raise Signing_Error with "trusted key destination is not an ordinary file: " & Name;
      end if;
      declare
         Existing : constant String := Read_Descriptor (Key_FD, "trusted public key");
      begin
         if not Close_Succeeded (Key_FD) then
            raise Signing_Error with "cannot close trusted public key: " & Name;
         end if;
         if not Close_Succeeded (Directory_FD) then
            raise Signing_Error with "cannot close trust store securely: " & Store;
         end if;
         return Existing = Content;
      end;
   exception
      when others =>
         Close (Key_FD);
         Close (Directory_FD);
         raise;
   end Existing_Content_Matches;
begin
   Decode_Hex (Content_Value (Content, "public"), Public, "public key");
   declare
      Id : constant String := Public_Id (Public);
      Name : constant String := Id & ".pub";
   begin
      Require_Trust_Store (Store, Create => True);
      if Project_Tools.Files.File_Exists (Project_Tools.Files.Join (Store, Name)) then
         if not Existing_Content_Matches (Name) then
            raise Signing_Error with "trusted key identity collision: " & Id;
         end if;
      else
         Create_Trusted_Key (Store, Name, Content);
      end if;
      return Id;
   end;
end Add_Trusted_Key;
