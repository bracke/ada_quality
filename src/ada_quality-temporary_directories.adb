with Ada.Characters.Handling;
with Ada.Strings.Fixed;
with GNAT.OS_Lib;
with Interfaces.C;
with Project_Tools.Files;
with Ada_Quality.POSIX;

package body Ada_Quality.Temporary_Directories is
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;

   Maximum_Prefix_Length : constant Positive := 48;
   Already_Exists        : constant Integer := 17;

   protected Suffixes is
      procedure Next (Value : out Natural);
   private
      Current : Natural := 0;
   end Suffixes;

   protected body Suffixes is
      procedure Next (Value : out Natural) is
      begin
         Current := (if Current = Natural'Last then 1 else Current + 1);
         Value := Current;
      end Next;
   end Suffixes;

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
      if Result'Length = 0 then
         return "ada-quality";
      elsif Result'Length <= Maximum_Prefix_Length then
         return Result;
      else
         return Result (Result'First .. Result'First + Maximum_Prefix_Length - 1);
      end if;
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
      Suffix  : Natural;
   begin
      Cleanup (Item);
      for Attempt in 1 .. 10_000 loop
         Suffixes.Next (Suffix);
         declare
            Candidate : constant String := Project_Tools.Files.Join
              (Project_Tools.Files.Temp_Dir,
               Safe_Prefix (Prefix) & "-" & Trimmed (Process) & "-" & Trimmed (Integer (Suffix)));
            Status : Interfaces.C.int;
            Error  : Integer;
         begin
            --  mkdir applies the private mode as part of the atomic creation operation;
            --  there is no interval in which another user can enter the directory.
            Status := Ada_Quality.POSIX.Make_Directory
              (Interfaces.C.To_C (Candidate), Interfaces.C.unsigned (8#700#));
            if Status = 0 then
               Item.Directory := To_Unbounded_String (Candidate);
               Item.Active := True;
               return;
            else
               Error := GNAT.OS_Lib.Errno;
               if Error /= Already_Exists then
                  raise Temporary_Directory_Error with
                    "could not create private temporary directory: " &
                    GNAT.OS_Lib.Errno_Message
                      (Err => Error, Default => "filesystem error");
               end if;
            end if;
         end;
      end loop;
      raise Temporary_Directory_Error with "could not allocate a unique temporary directory";
   end Create;

   function Path (Item : Temporary_Directory) return String is (To_String (Item.Directory));

   function Child (Item : Temporary_Directory; Name : String) return String is
      Component_First : Positive := Name'First;
   begin
      if not Item.Active or else Name'Length = 0 or else Name (Name'First) = '/' then
         raise Temporary_Directory_Error with "temporary child requires an active owner and a relative path";
      end if;
      for J in Name'Range loop
         if Character'Pos (Name (J)) = 0 then
            raise Temporary_Directory_Error with "temporary child path contains a null character";
         elsif Name (J) = '/' then
            if J = Component_First or else Name (Component_First .. J - 1) = ".." then
               raise Temporary_Directory_Error with "temporary child path escapes its owner";
            end if;
            Component_First := J + 1;
         end if;
      end loop;
      if Component_First > Name'Last or else Name (Component_First .. Name'Last) = ".." then
         raise Temporary_Directory_Error with "temporary child path escapes its owner";
      end if;
      return Project_Tools.Files.Join (Path (Item), Name);
   end Child;

   function Is_Active (Item : Temporary_Directory) return Boolean is (Item.Active);

   overriding procedure Finalize (Item : in out Temporary_Directory) is
   begin
      Cleanup (Item);
   end Finalize;
end Ada_Quality.Temporary_Directories;
