separate (Ada_Quality.Artifact_Signing)
procedure Remove_Trusted_Key (Store, Id : String) is
   Path : constant String := Project_Tools.Files.Join (Store, Id & ".pub");
   Directory_FD : Interfaces.C.int := -1;
begin
   if not Valid_Key_Id (Id) then raise Signing_Error with "invalid trusted key identity"; end if;
   Require_Trust_Store (Store);
   if Project_Tools.Links.Is_Link (Path) then
      raise Signing_Error with "trusted key must not be a symbolic link: " & Path;
   end if;
   if not Project_Tools.Files.File_Exists (Path) then
      raise Signing_Error with "trusted key not found: " & Id;
   end if;
   Directory_FD := Open_Directory_Nofollow (Interfaces.C.To_C (Store));
   if Directory_FD < 0 then
      raise Signing_Error with "cannot open trust store securely: " & Store;
   end if;
   if Unlink_At (Directory_FD, Interfaces.C.To_C (Id & ".pub"), 0) /= 0 then
      raise Signing_Error with "cannot remove trusted key: " & Id;
   end if;
   if not Close_Succeeded (Directory_FD) then
      raise Signing_Error with "cannot close trust store securely: " & Store;
   end if;
exception
   when others =>
      Close (Directory_FD);
      raise;
end Remove_Trusted_Key;
