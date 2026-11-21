with Ada.Directories;
with Ada.Exceptions;
with Interfaces.C;
with System;
with Ada_Quality.Artifact_Signing;
with Ada_Quality.POSIX;
with Ada_Quality.Resource_Limits;
with Project_Tools.Files;

package body Ada_Quality.Artifact_Staging is
   use type Interfaces.C.int;
   use type Interfaces.C.long;
   use type System.Address;
   use Ada_Quality.POSIX;

   procedure Copy (Source, Destination : String) is
      Entries     : Natural := 0;
      Total_Bytes : Long_Long_Integer := 0;

      procedure Count_Entry is
      begin
         Entries := Entries + 1;
         if Entries > Ada_Quality.Resource_Limits.Maximum_Project_Files then
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "artifact exceeds secure staging entry limit: " & Source;
         end if;
      end Count_Entry;

      procedure Copy_File
        (Source_FD : Interfaces.C.int; Into, Display_Path : String;
         Maximum_Bytes : Positive :=
           Ada_Quality.Resource_Limits.Maximum_Staging_File_Bytes)
      is
         Destination_FD : Interfaces.C.int := -1;
         Buffer : String (1 .. 65_536);
         File_Bytes : Long_Long_Integer := 0;
         Created : Boolean := False;
      begin
         Destination_FD := Create_Private (Interfaces.C.To_C (Into));
         if Destination_FD < 0 then
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "cannot create staged artifact file: " & Into;
         end if;
         Created := True;
         loop
            declare
               Count : constant Interfaces.C.long := Read
                 (Source_FD, Buffer (Buffer'First)'Address,
                  Interfaces.C.size_t (Buffer'Length));
            begin
               if Count < 0 then
                  raise Ada_Quality.Artifact_Signing.Signing_Error with
                    "cannot read artifact file while staging: " & Display_Path;
               elsif Count = 0 then
                  exit;
               end if;
               File_Bytes := File_Bytes + Long_Long_Integer (Count);
               Total_Bytes := Total_Bytes + Long_Long_Integer (Count);
               if File_Bytes > Long_Long_Integer (Maximum_Bytes) or else
                 Total_Bytes > Ada_Quality.Resource_Limits.Maximum_Staging_Aggregate_Bytes
               then
                  raise Ada_Quality.Artifact_Signing.Signing_Error with
                    "artifact exceeds secure staging byte limits: " & Source;
               end if;
               declare
                  Written : Natural := 0;
                  Length  : constant Natural := Natural (Count);
               begin
                  while Written < Length loop
                     declare
                        Amount : constant Interfaces.C.long := Write
                          (Destination_FD, Buffer (Buffer'First + Written)'Address,
                           Interfaces.C.size_t (Length - Written));
                     begin
                        if Amount <= 0 then
                           raise Ada_Quality.Artifact_Signing.Signing_Error with
                             "cannot write staged artifact file: " & Into;
                        end if;
                        Written := Written + Natural (Amount);
                     end;
                  end loop;
               end;
            end;
         end loop;
         if Close_Raw (Destination_FD) /= 0 then
            Destination_FD := -1;
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "cannot complete staged artifact file: " & Into;
         end if;
         Destination_FD := -1;
      exception
         when others =>
            Close (Destination_FD);
            if Created then
               Project_Tools.Files.Delete_File_If_Present (Into);
            end if;
            raise;
      end Copy_File;

      procedure Copy_Directory
        (Source_FD : Interfaces.C.int; Into, Display_Path : String;
         Depth : Positive)
      is
         Directory   : System.Address := System.Null_Address;
         Name_Buffer : aliased Interfaces.C.char_array (0 .. 4_095);
      begin
         if Depth > Ada_Quality.Resource_Limits.Maximum_Tree_Depth then
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "artifact exceeds secure staging depth: " & Display_Path;
         end if;
         Ada.Directories.Create_Directory (Into);
         Directory := Directory_Open (Source_FD);
         if Directory = System.Null_Address then
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "cannot enumerate staged artifact directory: " & Display_Path;
         end if;
         loop
            declare
               Status : constant Interfaces.C.int := Directory_Next
                 (Directory, Name_Buffer'Address,
                  Interfaces.C.size_t (Name_Buffer'Length));
            begin
               if Status = 0 then
                  exit;
               elsif Status < 0 then
                  raise Ada_Quality.Artifact_Signing.Signing_Error with
                    "cannot enumerate staged artifact directory: " & Display_Path;
               end if;
               declare
                  Name : constant String := Interfaces.C.To_Ada (Name_Buffer);
               begin
                  if Name not in "." | ".." then
                     Count_Entry;
                     declare
                        Child_FD : Interfaces.C.int := Open_Child_Nofollow
                          (Source_FD, Interfaces.C.To_C (Name));
                        Child_Path : constant String :=
                          Project_Tools.Files.Join (Display_Path, Name);
                        Target_Path : constant String :=
                          Project_Tools.Files.Join (Into, Name);
                     begin
                        if Child_FD < 0 then
                           raise Ada_Quality.Artifact_Signing.Signing_Error with
                             "artifact entry changed or is unsafe: " & Child_Path;
                        end if;
                        declare
                           Kind : constant Interfaces.C.int := Descriptor_Kind (Child_FD);
                        begin
                           if Kind = 2 then
                              Copy_Directory
                                (Child_FD, Target_Path, Child_Path, Depth + 1);
                           elsif Kind = 1 then
                              Copy_File (Child_FD, Target_Path, Child_Path);
                           else
                              raise Ada_Quality.Artifact_Signing.Signing_Error with
                                "artifact staging refuses special files: " & Child_Path;
                           end if;
                        end;
                        Close (Child_FD);
                     exception
                        when others =>
                           Close (Child_FD);
                           raise;
                     end;
                  end if;
               end;
            end;
         end loop;
         if Directory_Close (Directory) /= 0 then
            Directory := System.Null_Address;
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "cannot complete staged artifact directory: " & Display_Path;
         end if;
         Directory := System.Null_Address;
      exception
         when others =>
            if Directory /= System.Null_Address then
               declare
                  Ignored : constant Interfaces.C.int := Directory_Close (Directory);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            end if;
            raise;
      end Copy_Directory;

      procedure Copy_Path (From, Into : String) is
         Descriptor : Interfaces.C.int := Open_Read_Nofollow (Interfaces.C.To_C (From));
      begin
         if Descriptor < 0 then
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "artifact path is missing, linked, or unsafe: " & From;
         end if;
         declare
            Kind : constant Interfaces.C.int := Descriptor_Kind (Descriptor);
         begin
            Count_Entry;
            if Kind = 1 then
               Copy_File
                 (Descriptor, Into, From,
                  Ada_Quality.Resource_Limits.Maximum_Security_Metadata_Bytes);
            else
               raise Ada_Quality.Artifact_Signing.Signing_Error with
                 "artifact staging accepts only ordinary files and directories: " & From;
            end if;
         end;
         Close (Descriptor);
      exception
         when others =>
            Close (Descriptor);
            raise;
      end Copy_Path;

      procedure Remove_Partial_Destination is
      begin
         if Project_Tools.Files.Directory_Exists (Destination) then
            Project_Tools.Files.Delete_Tree (Destination);
         else
            Project_Tools.Files.Delete_File_If_Present (Destination);
         end if;
      end Remove_Partial_Destination;
   begin
      if Project_Tools.Files.Exists (Destination) then
         raise Ada_Quality.Artifact_Signing.Signing_Error with
           "artifact staging destination already exists: " & Destination;
      end if;
      declare
         Source_FD : Interfaces.C.int := Open_Read_Nofollow (Interfaces.C.To_C (Source));
      begin
         if Source_FD < 0 then
            raise Ada_Quality.Artifact_Signing.Signing_Error with
              "artifact not found or unsafe: " & Source;
         end if;
         declare
            Kind : constant Interfaces.C.int := Descriptor_Kind (Source_FD);
         begin
            Count_Entry;
            if Kind = 2 then
               Copy_Directory (Source_FD, Destination, Source, 1);
            elsif Kind = 1 then
               if Project_Tools.Files.Exists (Destination & ".sig") then
                  raise Ada_Quality.Artifact_Signing.Signing_Error with
                    "artifact staging destination already exists: " & Destination & ".sig";
               end if;
               Copy_File (Source_FD, Destination, Source);
               Copy_Path
                 (Source & ".sig", Destination & ".sig");
            else
               raise Ada_Quality.Artifact_Signing.Signing_Error with
                 "artifact staging refuses special files: " & Source;
            end if;
         end;
         Close (Source_FD);
      exception
         when Original : others =>
            Close (Source_FD);
            begin
               Remove_Partial_Destination;
            exception
               when Cleanup : others =>
                  raise Ada_Quality.Artifact_Signing.Signing_Error with
                    "artifact staging failed: " & Ada.Exceptions.Exception_Message (Original) &
                    "; partial destination cleanup failed: " &
                    Ada.Exceptions.Exception_Message (Cleanup);
            end;
            raise;
      end;
   end Copy;
end Ada_Quality.Artifact_Staging;
