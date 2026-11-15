separate (Ada_Quality.Checks)
   function Tree_Fingerprint
     (Root             : String;
      Files            : Text_Vectors.Vector;
      Ignore_Generated : Boolean) return String
   is
      Hash  : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Total_Bytes : Natural := 0;

      procedure Add_To_Hash (Text : String) is
      begin
         for C of Text loop
            Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
         end loop;
      end Add_To_Hash;

      procedure Add_Field (Text : String) is
         Length_Image : constant String :=
           Ada.Strings.Fixed.Trim (Natural'Image (Text'Length), Ada.Strings.Both);
      begin
         Add_To_Hash (Length_Image & ":" & Text);
      end Add_Field;

      procedure Add_Record (Kind, Name, Content : String) is
      begin
         Add_Field (Kind);
         Add_Field (Name);
         Add_Field (Content);
      end Add_Record;
   begin
      Add_Field ("ada-quality-tree-fingerprint-v2");
      for Path of Files loop
         if not Ignore_Generated or else not Is_Generated_Fingerprint_File (Root, To_String (Path)) then
            declare
               Name : constant String := Relative (Root, To_String (Path));
            begin
               if Project_Tools.Links.Is_Link (To_String (Path)) then
                  Add_Record ("symbolic-link", Name, "");
               else
                  declare
                     Size : constant Ada.Directories.File_Size := Ada.Directories.Size (To_String (Path));
                  begin
                     --  Source files are read whole; artifact files are hashed as a stream, so only the aggregate
                     --  limit bounds them.
                     if Ignore_Generated and then Size > Ada.Directories.File_Size (Maximum_File_Bytes) then
                        raise Constraint_Error with "project file exceeds fingerprint size limit: " & Name;
                     elsif Natural (Size) > Maximum_Fingerprint_Bytes - Total_Bytes then
                        raise Constraint_Error with "project exceeds aggregate fingerprint size limit";
                     end if;
                     Total_Bytes := Total_Bytes + Natural (Size);
                     if Ignore_Generated then
                        declare
                           Data : constant String := Project_Tools.Files.Read_Raw_File (To_String (Path));
                        begin
                           Add_Record ("source-file", Name, Data);
                        end;
                     else
                        Add_Record
                          ("artifact-file", Name,
                           Ada.Directories.File_Size'Image (Size) & ":" &
                             Project_Tools.Release_Checks.FNV1A64 (To_String (Path)));
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
      return Hash_Image (Hash);
   end Tree_Fingerprint;
