separate (Ada_Quality.Artifact_Signing)
procedure Verify_Trusted (Artifact, Store : String) is
   Info : constant Signature_Info := Inspect (Artifact);
   Id   : constant String := To_String (Info.Key);
   Directory_FD : Interfaces.C.int := -1;
   Key_FD : Interfaces.C.int := -1;
begin
   if not Valid_Key_Id (Id) then
      raise Signing_Error with "artifact signature has no valid trusted key identity";
   end if;
   Require_Trust_Store (Store);
   Directory_FD := Open_Directory_Nofollow (Interfaces.C.To_C (Store));
   if Directory_FD < 0 then
      raise Signing_Error with "cannot open trust store securely: " & Store;
   end if;
   Key_FD := Open_Child_Nofollow
     (Directory_FD, Interfaces.C.To_C (Id & ".pub"));
   if Key_FD < 0 then
      raise Signing_Error with "trusted public key not found: " & Id;
   end if;
   declare
      Public_Content : constant String := Read_Descriptor (Key_FD, "trusted public key");
   begin
      if Content_Value (Public_Content, "format") /= Public_Format then
         raise Signing_Error with "unsupported trusted public key format: " & Id;
      end if;
      if not Close_Succeeded (Key_FD) then
         raise Signing_Error with "cannot close trusted public key: " & Id;
      end if;
      Verify_Content (Artifact, Public_Content);
   end;
   if not Close_Succeeded (Directory_FD) then
      raise Signing_Error with "cannot close trust store securely: " & Store;
   end if;
exception
   when others =>
      Close (Key_FD);
      Close (Directory_FD);
      raise;
end Verify_Trusted;
