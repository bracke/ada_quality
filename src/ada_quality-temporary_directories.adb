with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with Interfaces.C;
with Project_Tools.Files;

package body Ada_Quality.Temporary_Directories is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;

   Next_Suffix : Natural := 0;

   function C_Chmod
     (Name : Interfaces.C.char_array;
      Mode : Interfaces.C.unsigned) return Interfaces.C.int
   with Import, Convention => C, External_Name => "chmod";

   function Trimmed (Value : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (Value), Ada.Strings.Both));

   function Safe_Prefix (Value : String) return String is
      Result : String := Value;
   begin
      for C of Result loop
         if not Ada.Characters.Handling.Is_Alphanumeric (C) and then C not in '-' | '_' then
            C := '-';
         end if;
      end loop;
      return (if Result'Length = 0 then "ada-quality" else Result);
   end Safe_Prefix;

   procedure Cleanup (Item : in out Temporary_Directory) is
   begin
      if Item.Active and then Project_Tools.Files.Exists (To_String (Item.Directory)) then
         Project_Tools.Files.Delete_Tree (To_String (Item.Directory));
      end if;
      Item.Directory := Null_Unbounded_String;
      Item.Active := False;
   end Cleanup;

   procedure Create (Item : in out Temporary_Directory; Prefix : String) is
      Process : constant Integer := GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id);
      Created : Boolean := False;
   begin
      Cleanup (Item);
      for Attempt in 1 .. 10_000 loop
         Next_Suffix := Next_Suffix + 1;
         declare
            Candidate : constant String := Project_Tools.Files.Join
              (Project_Tools.Files.Temp_Dir,
               Safe_Prefix (Prefix) & "-" & Trimmed (Process) & "-" & Trimmed (Integer (Next_Suffix)));
         begin
            Ada.Directories.Create_Directory (Candidate);
            Created := True;
            if C_Chmod (Interfaces.C.To_C (Candidate), Interfaces.C.unsigned (8#700#)) /= 0 then
               raise Temporary_Directory_Error with "could not secure temporary directory: " & Candidate;
            end if;
            Item.Directory := To_Unbounded_String (Candidate);
            Item.Active := True;
            return;
         exception
            when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
               null;
            when others =>  --  AQ: audited exception boundary
               if Created and then Project_Tools.Files.Exists (Candidate) then
                  Project_Tools.Files.Delete_Tree (Candidate);
               end if;
               raise;
         end;
      end loop;
      raise Temporary_Directory_Error with "could not allocate a unique temporary directory";
   end Create;

   function Path (Item : Temporary_Directory) return String is (To_String (Item.Directory));

   function Child (Item : Temporary_Directory; Name : String) return String is
     (Project_Tools.Files.Join (Path (Item), Name));

   function Is_Active (Item : Temporary_Directory) return Boolean is (Item.Active);

   overriding procedure Finalize (Item : in out Temporary_Directory) is
   begin
      Cleanup (Item);
   end Finalize;
end Ada_Quality.Temporary_Directories;
