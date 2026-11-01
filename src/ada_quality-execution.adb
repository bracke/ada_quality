with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with GNAT.Expect;
with GNAT.OS_Lib;
with System;

package body Ada_Quality.Execution is
   use Ada.Strings.Unbounded;
   use Project_Tools.Processes;
   use type GNAT.Expect.Expect_Match;

   Capture_Data      : Unbounded_String;
   Capture_Limit     : Natural := 0;
   Capture_Truncated : Boolean := False;

   procedure Capture_Filter
     (Descriptor : GNAT.Expect.Process_Descriptor'Class;
      Str        : String;
      User_Data  : System.Address := System.Null_Address)
   is
      pragma Unreferenced (Descriptor, User_Data);
      Remaining : constant Natural := Capture_Limit - Length (Capture_Data);
   begin
      if Str'Length <= Remaining then
         Append (Capture_Data, Str);
      else
         if Remaining > 0 then
            Append (Capture_Data, Str (Str'First .. Str'First + Remaining - 1));
         end if;
         Capture_Truncated := True;
      end if;
   end Capture_Filter;

   function Run
     (Directory       : String;
      Program         : String;
      Arguments       : Argument_Vector;
      Timeout_Seconds : Positive;
      Maximum_Bytes   : Positive) return Run_Result
   is
      Timeout_Path : constant String := Locate_Command ("timeout");
      Env_Path     : constant String := Locate_Command ("env");
      Program_Path : constant String :=
        (if Ada.Strings.Fixed.Index (Program, "/") > 0 and then Ada.Directories.Exists (Program)
         then Program else Locate_Command (Program));
      Args         : Argument_Vector;
      Descriptor   : GNAT.Expect.Process_Descriptor;
      Spawned      : Boolean := False;
      Result       : Run_Result;
      Previous     : constant String := Ada.Directories.Current_Directory;
      Child_Status : Integer := -1;
      Match         : GNAT.Expect.Expect_Match;
      Watchdog      : constant Integer :=
        (if Timeout_Seconds > (Integer'Last - 5_000) / 1_000 then Integer'Last
         else Timeout_Seconds * 1_000 + 5_000);

      procedure Close_Child is
      begin
         if Spawned then
            GNAT.Expect.Close (Descriptor, Child_Status);
            Spawned := False;
         end if;
      exception
         when GNAT.Expect.Invalid_Process => Spawned := False;
      end Close_Child;

      procedure Allow (Name : String) is
      begin
         if Ada.Environment_Variables.Exists (Name) then
            Args.Append
              (Argument (Name & "=" & Ada.Environment_Variables.Value (Name)));
         end if;
      end Allow;

      procedure Configure_User_Directories is
      begin
         if Ada.Environment_Variables.Exists ("HOME") then
            declare
               Home             : constant String := Ada.Environment_Variables.Value ("HOME");
               Config_Candidate : constant String := Home & "/.config";
               Data_Candidate   : constant String := Home & "/.local/share";
            begin
               if not Ada.Environment_Variables.Exists ("XDG_CONFIG_HOME") and then
                 Ada.Directories.Exists (Config_Candidate)
               then
                  Args.Append (Argument ("XDG_CONFIG_HOME=" & Config_Candidate));
               end if;
               if not Ada.Environment_Variables.Exists ("XDG_DATA_HOME") and then
                 Ada.Directories.Exists (Data_Candidate)
               then
                  Args.Append (Argument ("XDG_DATA_HOME=" & Data_Candidate));
               end if;
            end;
         end if;
         Allow ("ALIRE_SETTINGS_DIR");
      end Configure_User_Directories;

      procedure Prepare_Arguments is
      begin
         Args.Append (Argument ("--kill-after=5s"));
         Args.Append
           (Argument (Ada.Strings.Fixed.Trim (Positive'Image (Timeout_Seconds), Ada.Strings.Both) & "s"));
         Args.Append (Argument (Env_Path));
         Args.Append (Argument ("-i"));
         Allow ("PATH");
         Allow ("HOME");
         Allow ("TMPDIR");
         Allow ("LANG");
         Allow ("LC_ALL");
         Allow ("USER");
         Allow ("LOGNAME");
         Allow ("SHELL");
         Allow ("XDG_CACHE_HOME");
         Allow ("XDG_CONFIG_HOME");
         Allow ("XDG_DATA_HOME");
         Configure_User_Directories;
         Args.Append (Argument (Program_Path));
         for Item of Arguments loop
            Args.Append (Item);
         end loop;
      end Prepare_Arguments;

      procedure Spawn is
         Raw   : GNAT.OS_Lib.Argument_List (1 .. Natural (Args.Length));
         Index : Positive := Raw'First;
      begin
         for Item of Args loop
            Raw (Index) := new String'(To_String (Item));
            Index := Index + 1;
         end loop;
         Ada.Directories.Set_Directory (Directory);
         begin
            GNAT.Expect.Non_Blocking_Spawn
              (Descriptor, Timeout_Path, Raw, Buffer_Size => 4_096, Err_To_Out => True);
            Spawned := True;
            Ada.Directories.Set_Directory (Previous);
         exception
            when others =>  --  AQ: audited exception boundary
               Ada.Directories.Set_Directory (Previous);
               for Item of Raw loop
                  GNAT.OS_Lib.Free (Item);
               end loop;
               raise;
         end;
         for Item of Raw loop
            GNAT.OS_Lib.Free (Item);
         end loop;
      end Spawn;

      procedure Capture_Output is
      begin
         GNAT.Expect.Add_Filter
           (Descriptor, Capture_Filter'Access, Filter_On => GNAT.Expect.Output);
         loop
            begin
               GNAT.Expect.Expect (Descriptor, Match, "", Timeout => Watchdog, Full_Buffer => True);
               if Match = GNAT.Expect.Expect_Timeout then
                  Result.Status := Timed_Out;
                  exit;
               elsif Match = GNAT.Expect.Expect_Full_Buffer then
                  GNAT.Expect.Flush (Descriptor);
               end if;
            exception
               when GNAT.Expect.Process_Died => exit;
            end;
         end loop;
      end Capture_Output;
   begin
      if Timeout_Path'Length = 0 or else Env_Path'Length = 0 or else Program_Path'Length = 0 then
         Result.Output := To_Unbounded_String
           ("required executable not found: " &
            (if Program_Path'Length = 0 then Program elsif Env_Path'Length = 0 then "env" else "timeout"));
         return Result;
      end if;

      Prepare_Arguments;
      Capture_Data := Null_Unbounded_String;
      Capture_Limit := Maximum_Bytes;
      Capture_Truncated := False;
      Spawn;
      Capture_Output;
      Close_Child;

      Result.Command := To_Unbounded_String (Timeout_Path & " " & Program_Path);
      Result.Exit_Code := Child_Status;
      if Result.Status /= Timed_Out then
         Result.Status := (if Child_Status = 124 or else Child_Status = 137 then Timed_Out else Completed);
      end if;
      Result.Output := Capture_Data;
      Result.Truncated := Capture_Truncated;
      return Result;
   exception
      when E : others =>  --  AQ: audited exception boundary
         if Ada.Directories.Current_Directory /= Previous then
            Ada.Directories.Set_Directory (Previous);
         end if;
         Close_Child;
         Result.Status := Spawn_Error;
         Result.Output := To_Unbounded_String (Ada.Exceptions.Exception_Message (E));
         return Result;
   end Run;
end Ada_Quality.Execution;
