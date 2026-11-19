separate (Ada_Quality_Test_Suite)
--  AQ-WAIVER: SRC-03 target=run_execution_test owner=core expires=2099-12-31 justification=one-component-fixture-matrix
procedure Run_Execution_Test is
begin
declare
   Hostile_Root : constant String := Fixture_Root & "/ada quality ; hostile";
   Signal_Path  : constant String := Hostile_Root & "/signal fixture.sh";
   Exit_124_Path : constant String := Hostile_Root & "/exit 124 fixture.sh";
   Process_Tree_Path : constant String := Hostile_Root & "/process tree fixture.sh";
   Descendant_Path : constant String := Hostile_Root & "/descendant.pid";
   Loud_Text : constant String := "0123456789warning: late diagnostic";
   Slow : constant Ada_Quality.Execution.Run_Result :=
     Ada_Quality.Execution.Run
       (Directory => Ada.Directories.Current_Directory,
        Program => "sleep",
        Arguments => Project_Tools.Processes.Arguments
          ([Project_Tools.Processes.Argument ("2")]),
        Timeout_Seconds => 1,
        Maximum_Bytes => 128);
   Loud : constant Ada_Quality.Execution.Run_Result :=
     Ada_Quality.Execution.Run
       (Directory => Ada.Directories.Current_Directory,
        Program => "printf",
        Arguments => Project_Tools.Processes.Arguments
          ([Project_Tools.Processes.Argument (Loud_Text)]),
        Timeout_Seconds => 2,
        Maximum_Bytes => 5);
   Flood : constant Ada_Quality.Execution.Run_Result :=
     Ada_Quality.Execution.Run
       (Directory => Ada.Directories.Current_Directory,
        Program => "seq",
        Arguments => Project_Tools.Processes.Arguments
          ([Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("5000")]),
        Timeout_Seconds => 2,
        Maximum_Bytes => 5);
   Missing : constant Ada_Quality.Execution.Run_Result :=
     Ada_Quality.Execution.Run
       (Directory => Ada.Directories.Current_Directory,
        Program => "ada-quality-command-that-does-not-exist",
        Arguments => Project_Tools.Processes.No_Arguments,
        Timeout_Seconds => 1,
        Maximum_Bytes => 32);
   Tail_A : constant Ada_Quality.Execution.Run_Result :=
     Ada_Quality.Execution.Run
       (Directory => Ada.Directories.Current_Directory, Program => "printf",
        Arguments => Project_Tools.Processes.Arguments
          ([Project_Tools.Processes.Argument ("same-prefix-A")]),
        Timeout_Seconds => 2, Maximum_Bytes => 5);
   Tail_B : constant Ada_Quality.Execution.Run_Result :=
     Ada_Quality.Execution.Run
       (Directory => Ada.Directories.Current_Directory, Program => "printf",
        Arguments => Project_Tools.Processes.Arguments
          ([Project_Tools.Processes.Argument ("same-prefix-B")]),
        Timeout_Seconds => 2, Maximum_Bytes => 5);
begin
   Project_Tools.Files.Delete_Tree (Hostile_Root);
   Ada.Directories.Create_Path (Hostile_Root);
   Project_Tools.Files.Write_Text_File
     (Signal_Path,
      "#!/bin/sh" & ASCII.LF & "printf 'stderr-evidence\n' >&2" & ASCII.LF &
      "kill -TERM $$" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Exit_124_Path, "#!/bin/sh" & ASCII.LF & "exit 124" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Process_Tree_Path,
      "#!/bin/sh" & ASCII.LF &
      "(trap '' TERM; exec sleep 30) &" & ASCII.LF &
      "child=$!" & ASCII.LF &
      "printf '%s\n' ""$child"" > descendant.pid" & ASCII.LF &
      "wait ""$child""" & ASCII.LF);
   declare
      Chmod : constant Ada_Quality.Execution.Run_Result :=
        Ada_Quality.Execution.Run
          (Hostile_Root, "chmod",
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("+x"),
               Project_Tools.Processes.Argument (Signal_Path),
               Project_Tools.Processes.Argument (Exit_124_Path),
               Project_Tools.Processes.Argument (Process_Tree_Path)]), 2, 128);
      Hostile_Argument : constant String := "$(touch " & Fixture_Root & "/injected) ; literal";
      Literal : constant Ada_Quality.Execution.Run_Result :=
        Ada_Quality.Execution.Run
          (Hostile_Root, "printf",
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument (Hostile_Argument)]), 2, 256);
      Signalled : constant Ada_Quality.Execution.Run_Result :=
        Ada_Quality.Execution.Run
          (Hostile_Root, Signal_Path, Project_Tools.Processes.No_Arguments, 2, 256);
      Exit_124 : constant Ada_Quality.Execution.Run_Result :=
        Ada_Quality.Execution.Run
          (Hostile_Root, Exit_124_Path, Project_Tools.Processes.No_Arguments, 2, 256);
      Process_Tree : constant Ada_Quality.Execution.Run_Result :=
        Ada_Quality.Execution.Run
          (Hostile_Root, Process_Tree_Path, Project_Tools.Processes.No_Arguments, 1, 256);
   begin
      Assert (Chmod.Status = Ada_Quality.Execution.Completed and then Chmod.Exit_Code = 0,
        "hostile-path signal fixture is executable");
      Assert (Literal.Status = Ada_Quality.Execution.Completed and then
        To_String (Literal.Output) = Hostile_Argument and then
        not Project_Tools.Files.Exists (Fixture_Root & "/injected"),
        "arguments and hostile working-directory characters are never shell-interpolated");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Literal.Command), Hostile_Argument) = 0 and then
         Ada.Strings.Fixed.Index (To_String (Literal.Command), "<arg>") > 0 and then
         Ada.Strings.Fixed.Index (To_String (Literal.Command), [ASCII.LF]) = 0,
         "auditable command evidence preserves argument shape without sensitive values");
      Assert (Ada.Directories.Current_Directory /= Hostile_Root,
        "child working directories never change the parent process directory");
      Assert (Signalled.Status = Ada_Quality.Execution.Completed and then
        Signalled.Exit_Code /= 0 and then
        Ada.Strings.Fixed.Index (To_String (Signalled.Output), "stderr-evidence") > 0,
        "signal termination is non-passing and stderr is captured as bounded evidence");
      Assert (Exit_124.Status = Ada_Quality.Execution.Completed and then Exit_124.Exit_Code = 124,
        "a child exit code of 124 is not mistaken for a monitor timeout");
      Assert (Process_Tree.Status = Ada_Quality.Execution.Timed_Out,
        "a process-tree deadline is reported as a timeout");
      declare
         Descendant : constant String := Ada.Strings.Fixed.Trim
           (Project_Tools.Files.Read_Raw_File (Descendant_Path), Ada.Strings.Both);
         Probe : Ada_Quality.Execution.Run_Result;
      begin
         delay 0.2;
         Probe := Ada_Quality.Execution.Run
           (Hostile_Root, "kill",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("-0"),
                Project_Tools.Processes.Argument (Descendant)]), 2, 256);
         Assert (Probe.Status = Ada_Quality.Execution.Completed and then Probe.Exit_Code /= 0,
           "timeout cleanup terminates TERM-resistant descendants");
      end;
   end;
   Assert (Slow.Status = Ada_Quality.Execution.Timed_Out, "process timeout is enforced");
   Assert (Loud.Status = Ada_Quality.Execution.Completed and then Loud.Truncated,
     "captured process output is bounded");
   Assert (Length (Loud.Output) = 5, "bounded output has the configured maximum length");
   Assert
     (Loud.Output_Bytes = Long_Long_Integer (Loud_Text'Length) and then
      Long_Long_Integer (Length (Loud.Output)) < Loud.Output_Bytes,
      "complete output byte counts survive retained-text truncation");
   Assert
     (Tail_A.Truncated and then Tail_B.Truncated and then Tail_A.Output = Tail_B.Output and then
      Tail_A.Output_Digest /= Tail_B.Output_Digest and then
      Tail_A.Output_Bytes = 13 and then Tail_B.Output_Bytes = 13,
      "complete-output digests distinguish equal retained prefixes with different tails");
   declare
      Incomplete_Diagnostics : constant Indicator_Result :=
        Ada_Quality.Checks.Inspected_Output_Result
          (DOC_02, Loud,
           Ada.Strings.Fixed.Index
             (Ada.Characters.Handling.To_Lower (To_String (Loud.Output)), "warning:") = 0,
           "documentation has no warnings", "documentation contains warnings");
   begin
      Assert
        (Incomplete_Diagnostics.Execution = Blocked and then
         Incomplete_Diagnostics.Compliance = Unknown,
         "a diagnostic warning beyond the capture limit cannot produce a passing DOC-02 result");
      Assert
        (Ada_Quality.Checks.Documentation_Warning_Count
           ("warning: output directory already exists") = 0 and then
         Ada_Quality.Checks.Documentation_Warning_Count
           ("sample.ads:2:14: warning: entity Undocumented is not documented") = 1,
         "DOC-01 classifies undocumented-entity diagnostics independently of other GNATdoc warnings");
      Assert
        (Ada_Quality.Checks.Documentation_Warning_Count
           ("sample.ads:2:14: warning: entity Undocumented is not documented" & ASCII.LF &
            "sample.ads:2:14: warning: entity Undocumented is not documented") = 1,
         "DOC-01 counts repeated GNATdoc diagnostics once");
   end;
   Assert (Flood.Status = Ada_Quality.Execution.Completed and then Flood.Truncated,
     "output larger than the internal process buffer completes with bounded capture");
   Assert (Length (Flood.Output) = 5, "large streamed output retains only the configured byte limit");
   Assert (Missing.Status = Ada_Quality.Execution.Spawn_Error, "missing executable is a spawn error");
   declare
      type Concurrent_Results is array (Positive range 1 .. 2) of Ada_Quality.Execution.Run_Result;
      Results : Concurrent_Results;
   begin
      declare
         task type Runner (Index : Positive);
         task body Runner is
            Text : constant String := (if Index = 1 then "first-output" else "second-output");
         begin
            Results (Index) := Ada_Quality.Execution.Run
              (Directory => Ada.Directories.Current_Directory,
               Program => "printf",
               Arguments => Project_Tools.Processes.Arguments
                 ([Project_Tools.Processes.Argument (Text)]),
               Timeout_Seconds => 2,
               Maximum_Bytes => 128);
         end Runner;
         First  : Runner (1);
         Second : Runner (2);
      begin
         null;
      end;
      Assert
        (To_String (Results (1).Output) = "first-output" and then
         To_String (Results (2).Output) = "second-output",
         "concurrent callers are serialized and retain independent capture state");
   end;
   Ada.Environment_Variables.Set ("ADA_QUALITY_TEST_SECRET", "must-not-reach-child");
   declare
      Child_Environment : constant Ada_Quality.Execution.Run_Result :=
        Ada_Quality.Execution.Run
          (Directory => Ada.Directories.Current_Directory, Program => "env",
           Arguments => Project_Tools.Processes.No_Arguments,
           Timeout_Seconds => 2, Maximum_Bytes => 4_096);
   begin
      Ada.Environment_Variables.Clear ("ADA_QUALITY_TEST_SECRET");
      Assert (Child_Environment.Status = Ada_Quality.Execution.Completed,
        "allowlisted child environment can execute");
      Assert
        (Ada.Strings.Fixed.Index (To_String (Child_Environment.Output), "ADA_QUALITY_TEST_SECRET") = 0,
         "non-allowlisted environment variables do not reach child tools");
   exception
      when others =>  --  AQ: audited exception boundary
         Ada.Environment_Variables.Clear ("ADA_QUALITY_TEST_SECRET");
         raise;
   end;
   declare
      Home_Root          : constant String := Hostile_Root & "/home";
      Settings_Directory : constant String := Home_Root & "/.config/alire";
      Data_Directory     : constant String := Home_Root & "/.local/share/alire";
      Had_Home           : constant Boolean := Ada.Environment_Variables.Exists ("HOME");
      Saved_Home         : constant String :=
        (if Had_Home then Ada.Environment_Variables.Value ("HOME") else "");
      Had_Settings       : constant Boolean :=
        Ada.Environment_Variables.Exists ("ALIRE_SETTINGS_DIR");
      Saved_Settings     : constant String :=
        (if Had_Settings then Ada.Environment_Variables.Value ("ALIRE_SETTINGS_DIR") else "");
      Had_Config         : constant Boolean :=
        Ada.Environment_Variables.Exists ("XDG_CONFIG_HOME");
      Saved_Config       : constant String :=
        (if Had_Config then Ada.Environment_Variables.Value ("XDG_CONFIG_HOME") else "");
      Had_Data           : constant Boolean :=
        Ada.Environment_Variables.Exists ("XDG_DATA_HOME");
      Saved_Data         : constant String :=
        (if Had_Data then Ada.Environment_Variables.Value ("XDG_DATA_HOME") else "");

      procedure Restore_Environment is
      begin
         if Had_Home then
            Ada.Environment_Variables.Set ("HOME", Saved_Home);
         else
            Ada.Environment_Variables.Clear ("HOME");
         end if;
         if Had_Settings then
            Ada.Environment_Variables.Set ("ALIRE_SETTINGS_DIR", Saved_Settings);
         else
            Ada.Environment_Variables.Clear ("ALIRE_SETTINGS_DIR");
         end if;
         if Had_Config then
            Ada.Environment_Variables.Set ("XDG_CONFIG_HOME", Saved_Config);
         else
            Ada.Environment_Variables.Clear ("XDG_CONFIG_HOME");
         end if;
         if Had_Data then
            Ada.Environment_Variables.Set ("XDG_DATA_HOME", Saved_Data);
         else
            Ada.Environment_Variables.Clear ("XDG_DATA_HOME");
         end if;
      end Restore_Environment;
   begin
      Ada.Directories.Create_Path (Settings_Directory);
      Ada.Directories.Create_Path (Data_Directory);
      Ada.Environment_Variables.Set ("HOME", Home_Root);
      Ada.Environment_Variables.Clear ("ALIRE_SETTINGS_DIR");
      Ada.Environment_Variables.Clear ("XDG_CONFIG_HOME");
      Ada.Environment_Variables.Clear ("XDG_DATA_HOME");
      declare
         Child_Environment : constant Ada_Quality.Execution.Run_Result :=
           Ada_Quality.Execution.Run
             (Directory => Ada.Directories.Current_Directory, Program => "env",
              Arguments => Project_Tools.Processes.No_Arguments,
              Timeout_Seconds => 2, Maximum_Bytes => 4_096);
      begin
         Restore_Environment;
         Assert
           (Ada.Strings.Fixed.Index
              (To_String (Child_Environment.Output),
               "XDG_CONFIG_HOME=" & Home_Root & "/.config") > 0 and then
            Ada.Strings.Fixed.Index
              (To_String (Child_Environment.Output),
               "XDG_DATA_HOME=" & Home_Root & "/.local/share") > 0,
            "conventional user config and data directories reach the clean environment");
      end;
   exception
      when others =>  --  AQ: audited exception boundary
         Restore_Environment;
         raise;
   end;
   Project_Tools.Files.Write_Text_File
     (Hostile_Root & "/warning_fixture.adb",
      "with Ada.Text_IO;" & ASCII.LF &
      "procedure Warning_Fixture is" & ASCII.LF &
      "begin" & ASCII.LF & "   null;" & ASCII.LF &
      "end Warning_Fixture;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Hostile_Root & "/warning_fixture.gpr",
      "project Warning_Fixture is" & ASCII.LF &
      "   for Source_Dirs use (""."");" & ASCII.LF &
      "   for Object_Dir use ""warning-obj"";" & ASCII.LF &
      "   for Main use (""warning_fixture.adb"");" & ASCII.LF &
      "   package Compiler is" & ASCII.LF &
      "      for Default_Switches (""Ada"") use " &
      "(""-gnat2022"", ""-gnatwa"", ""-gnatVa"");" & ASCII.LF &
      "   end Compiler;" & ASCII.LF &
      "end Warning_Fixture;" & ASCII.LF);
   Project_Tools.Files.Write_Text_File
     (Hostile_Root & "/warning_gate.gpr",
      "project Warning_Gate extends ""warning_fixture.gpr"" is" & ASCII.LF &
      "   package Compiler is" & ASCII.LF &
      "      for Default_Switches (""Ada"") use " &
      "Warning_Fixture.Compiler'Default_Switches (""Ada"") & " &
      "(""-gnatwa"", ""-gnatwe"");" & ASCII.LF &
      "   end Compiler;" & ASCII.LF &
      "end Warning_Gate;" & ASCII.LF);
   declare
      Warning_Build : constant Ada_Quality.Execution.Run_Result :=
        Ada_Quality.Execution.Run
          (Hostile_Root, "gprbuild",
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("-P"),
               Project_Tools.Processes.Argument ("warning_gate.gpr"),
               Project_Tools.Processes.Argument ("-f"),
               Project_Tools.Processes.Argument ("-p"),
               Project_Tools.Processes.Argument ("-v")]),
           Timeout_Seconds => 20, Maximum_Bytes => 4_096);
      Warning_Output : constant String :=
        Ada.Characters.Handling.To_Lower (To_String (Warning_Build.Output));
   begin
      Assert (Warning_Build.Status = Ada_Quality.Execution.Completed and then
        Warning_Build.Exit_Code /= 0 and then
        Ada.Strings.Fixed.Index (Warning_Output, "ada.text_io") > 0 and then
        Ada.Strings.Fixed.Index (Warning_Output, "not referenced") > 0,
        "BLD-03 wrapper rejects the target warning while extending inherited switches" &
        ASCII.LF & To_String (Warning_Build.Output));
   end;
   Project_Tools.Files.Delete_Tree (Hostile_Root);
end;
end Run_Execution_Test;
