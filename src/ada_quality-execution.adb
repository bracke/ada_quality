with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Finalization;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with GNAT.Expect;
with GNAT.OS_Lib;
with Interfaces;
with Interfaces.C;
with System;
with Ada.Unchecked_Conversion;

package body Ada_Quality.Execution is
   use Ada.Strings.Unbounded;
   use Project_Tools.Processes;
   use type GNAT.Expect.Expect_Match;
   use type GNAT.Expect.Process_Id;
   use type Interfaces.C.int;
   use type Interfaces.Unsigned_64;
   use type Ada.Real_Time.Time;
   use type Ada.Real_Time.Time_Span;

   function C_Kill
     (Pid : Interfaces.C.int; Signal : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "kill";

   protected Run_Gate is
      entry Acquire;
      procedure Release;
   private
      Busy : Boolean := False;
   end Run_Gate;

   protected body Run_Gate is
      entry Acquire when not Busy is
      begin
         Busy := True;
      end Acquire;

      procedure Release is
      begin
         Busy := False;
      end Release;
   end Run_Gate;

   type Gate_Guard is new Ada.Finalization.Limited_Controlled with record
      Active : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Gate_Guard) is
   begin
      if Item.Active then
         Run_Gate.Release;
         Item.Active := False;
      end if;
   end Finalize;

   procedure Lock (Item : in out Gate_Guard) is
   begin
      Run_Gate.Acquire;
      Item.Active := True;
   end Lock;

   type Capture_State is record
      Data      : Unbounded_String;
      Limit     : Natural := 0;
      Digest    : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Bytes     : Long_Long_Integer := 0;
      Truncated : Boolean := False;
   end record;

   type Capture_State_Access is access all Capture_State;
   function To_Capture_State is new Ada.Unchecked_Conversion
     (System.Address, Capture_State_Access);

   procedure Capture_Filter
     (Descriptor : GNAT.Expect.Process_Descriptor'Class;
      Str        : String;
      User_Data  : System.Address := System.Null_Address)
   is
      pragma Unreferenced (Descriptor);
      State : constant Capture_State_Access := To_Capture_State (User_Data);
      Remaining : constant Natural := State.Limit - Length (State.Data);
   begin
      if Long_Long_Integer (Str'Length) > Long_Long_Integer'Last - State.Bytes then
         raise Constraint_Error with "process output byte count exceeds Long_Long_Integer";
      end if;
      State.Bytes := State.Bytes + Long_Long_Integer (Str'Length);
      for Value of Str loop
         State.Digest :=
           (State.Digest xor Interfaces.Unsigned_64 (Character'Pos (Value))) * 16#100000001B3#;
      end loop;
      if Str'Length <= Remaining then
         Append (State.Data, Str);
      else
         if Remaining > 0 then
            Append (State.Data, Str (Str'First .. Str'First + Remaining - 1));
         end if;
         State.Truncated := True;
      end if;
   end Capture_Filter;

   function Hash_Image (Value : Interfaces.Unsigned_64) return String is
      Hex    : constant String := "0123456789abcdef";
      Work   : Interfaces.Unsigned_64 := Value;
      Result : String (1 .. 16);
   begin
      for Index in reverse Result'Range loop
         Result (Index) := Hex (Natural (Work and 15) + 1);
         Work := Interfaces.Shift_Right (Work, 4);
      end loop;
      return Result;
   end Hash_Image;

   function Command_Image
     (Program : String; Arguments : Argument_Vector) return String
   is
      Result : Unbounded_String;

      procedure Append_Quoted (Value : String) is
      begin
         Append (Result, "'");
         for C of Value loop
            case C is
               when ''' => Append (Result, "\'");
               when '\' => Append (Result, "\\");
               when ASCII.LF => Append (Result, "\n");
               when ASCII.CR => Append (Result, "\r");
               when ASCII.HT => Append (Result, "\t");
               when others => Append (Result, C);
            end case;
         end loop;
         Append (Result, "'");
      end Append_Quoted;

      function Audit_Argument (Value : String) return String is
         Equal : constant Natural := Ada.Strings.Fixed.Index (Value, "=");
      begin
         if Value'Length >= 2 and then Value (Value'First .. Value'First + 1) = "--" then
            return
              (if Equal > Value'First + 2 then Value (Value'First .. Equal - 1)
               elsif Equal = 0 then Value else "--<option>");
         elsif Value'Length = 2 and then Value (Value'First) = '-' then
            return Value;
         elsif Value'Length > 2 and then Value (Value'First) = '-' then
            return Value (Value'First .. Value'First + 1) & "<value>";
         else
            return "<arg>";
         end if;
      end Audit_Argument;
   begin
      Append_Quoted (Program);
      for Item of Arguments loop
         Append (Result, " ");
         Append_Quoted (Audit_Argument (To_String (Item)));
      end loop;
      return To_String (Result);
   end Command_Image;

   function Run
     (Directory       : String;
      Program         : String;
      Arguments       : Argument_Vector;
      Timeout_Seconds : Positive;
      Maximum_Bytes   : Positive) return Run_Result
   is
      Env_Path     : constant String := Locate_Command ("env");
      SetSid_Path  : constant String := Locate_Command ("setsid");
      Program_Path : constant String :=
        (if Ada.Strings.Fixed.Index (Program, "/") > 0 and then Ada.Directories.Exists (Program)
         then Program else Locate_Command (Program));
      Args         : Argument_Vector;
      Descriptor   : GNAT.Expect.Process_Descriptor;
      Capture      : aliased Capture_State :=
        (Data => Null_Unbounded_String, Limit => Maximum_Bytes,
         Digest => 16#CBF29CE484222325#, Bytes => 0, Truncated => False);
      Guard        : Gate_Guard;
      Spawned      : Boolean := False;
      Result       : Run_Result;
      Child_Status : Integer := -1;
      Match         : GNAT.Expect.Expect_Match;
      Process_Deadline : Ada.Real_Time.Time := Ada.Real_Time.Time_First;

      procedure Signal_Process_Group
        (Signal : Positive; Fallback_To_Child : Boolean := False)
      is
         Pid    : constant GNAT.Expect.Process_Id := GNAT.Expect.Get_Pid (Descriptor);
         Status : Interfaces.C.int;
      begin
         if Pid <= GNAT.Expect.Null_Pid then
            raise GNAT.Expect.Invalid_Process;
         end if;
         Status := C_Kill (-Interfaces.C.int (Pid), Interfaces.C.int (Signal));
         if Status /= 0 and then Fallback_To_Child then
            GNAT.Expect.Send_Signal (Descriptor, Signal);
         end if;
      end Signal_Process_Group;

      function Milliseconds_Until (Target : Ada.Real_Time.Time) return Integer is
         Remaining : constant Ada.Real_Time.Time_Span := Target - Ada.Real_Time.Clock;
      begin
         if Remaining <= Ada.Real_Time.Time_Span_Zero then
            return 0;
         end if;
         declare
            Milliseconds : constant Duration := Ada.Real_Time.To_Duration (Remaining) * 1_000.0;
         begin
            return
              (if Milliseconds >= Duration (Integer'Last) then Integer'Last
               else Integer'Max (1, Integer (Milliseconds)));
         end;
      end Milliseconds_Until;

      procedure Close_Child is
      begin
         if Spawned then
            GNAT.Expect.Close (Descriptor, Child_Status);
            Spawned := False;
         end if;
      exception
         when GNAT.Expect.Invalid_Process => Spawned := False;
      end Close_Child;

      procedure Abort_Process_Group is
      begin
         if Spawned then
            begin
               Signal_Process_Group (9, Fallback_To_Child => True);
            exception
               when others =>  --  Preserve the original monitoring failure.
                  null;
            end;
         end if;
         begin
            Close_Child;
         exception
            when others =>  --  Preserve the original monitoring failure.
               Spawned := False;
         end;
      end Abort_Process_Group;

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
         Args.Append (Argument ("-i"));
         Args.Append (Argument ("--chdir=" & Directory));
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
         Args.Append (Argument (SetSid_Path));
         Args.Append (Argument (Program_Path));
         for Item of Arguments loop
            Args.Append (Item);
         end loop;
      end Prepare_Arguments;

      procedure Spawn is
         Raw   : GNAT.OS_Lib.Argument_List (1 .. Natural (Args.Length));
         Index : Positive := Raw'First;
      begin
         begin
            for Item of Args loop
               Raw (Index) := new String'(To_String (Item));
               Index := Index + 1;
            end loop;
            GNAT.Expect.Non_Blocking_Spawn
              (Descriptor, Env_Path, Raw, Buffer_Size => 4_096, Err_To_Out => True);
            Spawned := True;
            Process_Deadline := Ada.Real_Time.Clock + Ada.Real_Time.Seconds (Timeout_Seconds);
         exception
            when others =>  --  AQ: audited exception boundary
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
         procedure Drain_After_Timeout is
            Kill_Deadline : constant Ada.Real_Time.Time :=
              Ada.Real_Time.Clock + Ada.Real_Time.Seconds (5);
         begin
            Signal_Process_Group (15, Fallback_To_Child => True);
            begin
               loop
                  declare
                     Remaining : constant Integer := Milliseconds_Until (Kill_Deadline);
                  begin
                     if Remaining = 0 then
                        Signal_Process_Group (9);
                        exit;
                     end if;
                     GNAT.Expect.Expect
                       (Descriptor, Match, "", Timeout => Remaining, Full_Buffer => True);
                     if Match = GNAT.Expect.Expect_Timeout then
                        Signal_Process_Group (9);
                        exit;
                     elsif Match = GNAT.Expect.Expect_Full_Buffer then
                        GNAT.Expect.Flush (Descriptor);
                     end if;
                  end;
               end loop;
            exception
               when GNAT.Expect.Process_Died =>
                  --  The session leader may exit on TERM while a descendant ignores it.
                  --  Kill the remaining process group before releasing the workspace.
                  Signal_Process_Group (9);
            end;
         end Drain_After_Timeout;
      begin
         GNAT.Expect.Add_Filter
           (Descriptor, Capture_Filter'Access, Filter_On => GNAT.Expect.Output,
            User_Data => Capture'Address);
         loop
            begin
               declare
                  Remaining : constant Integer := Milliseconds_Until (Process_Deadline);
               begin
                  if Remaining = 0 then
                     Result.Status := Timed_Out;
                     Drain_After_Timeout;
                     exit;
                  end if;
                  GNAT.Expect.Expect
                    (Descriptor, Match, "", Timeout => Remaining, Full_Buffer => True);
               end;
               if Match = GNAT.Expect.Expect_Timeout then
                  Result.Status := Timed_Out;
                  Drain_After_Timeout;
                  exit;
               elsif Match = GNAT.Expect.Expect_Full_Buffer then
                  GNAT.Expect.Flush (Descriptor);
               end if;
            exception
               when GNAT.Expect.Process_Died => exit;
            end;
         end loop;
      end Capture_Output;

      procedure Set_Output_Evidence is
      begin
         Result.Output := Capture.Data;
         Result.Output_Digest := To_Unbounded_String (Hash_Image (Capture.Digest));
         Result.Output_Bytes := Capture.Bytes;
         Result.Truncated := Capture.Truncated;
      end Set_Output_Evidence;
   begin
      Lock (Guard);
      Result.Command := To_Unbounded_String
        (Command_Image ((if Program_Path'Length = 0 then Program else Program_Path), Arguments));
      if Env_Path'Length = 0 or else SetSid_Path'Length = 0 or else Program_Path'Length = 0 then
         Result.Output := To_Unbounded_String
           ("required executable not found: " &
            (if Program_Path'Length = 0 then Program
             elsif Env_Path'Length = 0 then "env"
             else "setsid"));
         Result.Output_Digest := To_Unbounded_String (Hash_Image (Capture.Digest));
         return Result;
      end if;

      Prepare_Arguments;
      Spawn;
      Capture_Output;
      Close_Child;

      Result.Exit_Code := Child_Status;
      if Result.Status /= Timed_Out then
         Result.Status := Completed;
      end if;
      Set_Output_Evidence;
      return Result;
   exception
      when E : others =>  --  AQ: audited exception boundary
         --  Unexpected failures after spawn must not leave descendants running
         --  in the isolated process group.
         Abort_Process_Group;
         Result.Status := Spawn_Error;
         Result.Output := To_Unbounded_String (Ada.Exceptions.Exception_Message (E));
         Result.Output_Digest := To_Unbounded_String (Hash_Image (Capture.Digest));
         Result.Output_Bytes := Capture.Bytes;
         Result.Truncated := Capture.Truncated;
         return Result;
   end Run;
end Ada_Quality.Execution;
