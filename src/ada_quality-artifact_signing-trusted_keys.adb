separate (Ada_Quality.Artifact_Signing)
function Trusted_Keys (Store : String) return Trusted_Key_Vectors.Vector is
   Result : Trusted_Key_Vectors.Vector;
   Search : Ada.Directories.Search_Type;
   Search_Open : Boolean := False;
   Dir_Entry : Ada.Directories.Directory_Entry_Type;
   function Less (Left, Right : Trusted_Key) return Boolean is (Left.Id < Right.Id);
   package Sorting is new Trusted_Key_Vectors.Generic_Sorting ("<" => Less);

   procedure End_Search_Preserving_Failure is
   begin
      if Search_Open then
         Ada.Directories.End_Search (Search);
         Search_Open := False;
      end if;
   exception
      when others =>
         null;
   end End_Search_Preserving_Failure;
begin
   if not Project_Tools.Files.Directory_Exists (Store) then return Result; end if;
   Require_Trust_Store (Store);
   Ada.Directories.Start_Search
     (Search, Store, "*.pub", [Ada.Directories.Ordinary_File => True, others => False]);
   Search_Open := True;
   while Ada.Directories.More_Entries (Search) loop
      Ada.Directories.Get_Next_Entry (Search, Dir_Entry);
      declare
         Path : constant String := Ada.Directories.Full_Name (Dir_Entry);
         Id   : constant String := Key_Id (Path);
      begin
         if Ada.Directories.Simple_Name (Dir_Entry) /= Id & ".pub" then
            raise Signing_Error with "trusted key filename does not match its identity: " & Path;
         end if;
         Result.Append
           (Trusted_Key'(To_Unbounded_String (Id), To_Unbounded_String (Path)));
      end;
   end loop;
   Ada.Directories.End_Search (Search);
   Search_Open := False;
   Sorting.Sort (Result);
   return Result;
exception
   when others =>
      End_Search_Preserving_Failure;
      raise;
end Trusted_Keys;
