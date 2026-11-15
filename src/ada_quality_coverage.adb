with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Strings.Unbounded.Text_IO;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Interfaces;
with Interfaces.C;
with Project_Tools.Files;
with Project_Tools.Gcov;
with Project_Tools.Processes;
with Ada_Quality.Checks;
with Ada_Quality.Coverage;
with Ada_Quality.Temporary_Directories;
with Ada_Quality.Types;

--  AQ-WAIVER: SRC-03 target=include_source justification=coverage aggregation shares one completeness boundary
procedure Ada_Quality_Coverage is
   --  Isolated coverage entry point with concurrency locking and deterministic stability checks.
   use Ada.Strings.Unbounded;
   use type Interfaces.C.int;

   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Tests_Dir : constant String := Project_Tools.Files.Join (Root, "tests");
   Output_Dir : constant String := Project_Tools.Files.Join (Root, "coverage");
   Summary_Path : constant String := Project_Tools.Files.Join (Output_Dir, "gcov-summary.txt");
   Stability_Path : constant String := Project_Tools.Files.Join (Output_Dir, "gcov-stability.txt");
   Alr : constant String := Project_Tools.Processes.Locate_Command ("alr");
   Scratch : Ada_Quality.Temporary_Directories.Temporary_Directory;
   Toolchain_Fingerprint : Unbounded_String;
   Current_Source_Fingerprint : Unbounded_String;

   type File_Coverage is record
      Name    : Unbounded_String;
      Covered : Natural;
      Total   : Natural;
   end record;

   package File_Coverage_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => File_Coverage);

   function Lock_Path return String;

   function C_Open
     (Path : Interfaces.C.char_array; Flags : Interfaces.C.int;
      Mode : Interfaces.C.unsigned) return Interfaces.C.int
   with Import, Convention => C, External_Name => "open";

   function C_Flock (FD, Operation : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "flock";

   function C_Close (FD : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C, External_Name => "close";

   function C_Rename
     (Old_Path, New_Path : Interfaces.C.char_array) return Interfaces.C.int
   with Import, Convention => C, External_Name => "rename";

   type Coverage_Lock is new Ada.Finalization.Limited_Controlled with record
      Descriptor : Interfaces.C.int := -1;
   end record;

   overriding procedure Finalize (Item : in out Coverage_Lock);

   procedure Acquire (Item : in out Coverage_Lock; Success : out Boolean) is
      Descriptor : Interfaces.C.int;
   begin
      Descriptor := C_Open
        --  O_CLOEXEC prevents assessment subprocesses from retaining the
        --  advisory lock if the coverage driver is killed.
        (Interfaces.C.To_C (Lock_Path),
         --  O_RDWR + O_CREAT + O_NOFOLLOW + O_CLOEXEC.
         Interfaces.C.int (2 + 64 + 131_072 + 524_288),
         Interfaces.C.unsigned (8#600#));
      if Descriptor < 0 then
         Success := False;
      elsif C_Flock (Descriptor, Interfaces.C.int (2 + 4)) /= 0 then
         declare
            Ignored : constant Interfaces.C.int := C_Close (Descriptor);
            pragma Unreferenced (Ignored);
         begin
            Success := False;
         end;
      else
         Item.Descriptor := Descriptor;
         Success := True;
      end if;
   end Acquire;

   overriding procedure Finalize (Item : in out Coverage_Lock) is
   begin
      if Item.Descriptor >= 0 then
         declare
            Ignored : constant Interfaces.C.int := C_Close (Item.Descriptor);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      end if;
      Item.Descriptor := -1;
   end Finalize;

   Lock : Coverage_Lock;

   function Object_Dir return String is
     (Ada_Quality.Temporary_Directories.Child (Scratch, "obj"));

   function Binary (Name : String) return String is
     (Ada_Quality.Temporary_Directories.Child (Scratch, "bin/" & Name));

   function Trim (Text : String) return String is
     (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));

   procedure Publish_Artifacts (Content : String) is
      Process : constant String := Trim
        (Integer'Image (GNAT.OS_Lib.Pid_To_Integer (GNAT.OS_Lib.Current_Process_Id)));
      Summary_Temporary : constant String := Summary_Path & ".tmp-" & Process;
      Stability_Temporary : constant String := Stability_Path & ".tmp-" & Process;

      procedure Cleanup_Temporary is
      begin
         Project_Tools.Files.Delete_File_If_Present (Summary_Temporary);
         Project_Tools.Files.Delete_File_If_Present (Stability_Temporary);
      end Cleanup_Temporary;

      procedure Replace (Source, Target : String) is
      begin
         if C_Rename (Interfaces.C.To_C (Source), Interfaces.C.To_C (Target)) /= 0 then
            raise Program_Error with "could not atomically publish coverage artifact: " & Target;
         end if;
      end Replace;
   begin
      Cleanup_Temporary;
      Project_Tools.Files.Write_Text_File (Stability_Temporary, Content);
      Project_Tools.Files.Write_Text_File (Summary_Temporary, Content);
      --  The consumer-facing summary changes last, after its matching
      --  stability record is already visible.
      Replace (Stability_Temporary, Stability_Path);
      Replace (Summary_Temporary, Summary_Path);
   exception
      when others =>  --  AQ: audited exception boundary
         Cleanup_Temporary;
         raise;
   end Publish_Artifacts;

   function Per_File_Gcov_Output (Text : String) return String is
      Aggregate : constant Natural := Ada.Strings.Fixed.Index
        (Text, ASCII.LF & "Lines executed:", Going => Ada.Strings.Backward);
   begin
      if Aggregate = 0 then return Text; end if;
      return Text (Text'First .. Aggregate - 1);
   end Per_File_Gcov_Output;

   function Hash_Output (Text : String) return String is
      use type Interfaces.Unsigned_64;
      Hash   : Interfaces.Unsigned_64 := 16#CBF29CE484222325#;
      Hex    : constant String := "0123456789abcdef";
      Result : String (1 .. 16);
   begin
      for C of Text loop
         Hash := (Hash xor Interfaces.Unsigned_64 (Character'Pos (C))) * 16#100000001B3#;
      end loop;
      for J in reverse Result'Range loop
         Result (J) := Hex (Natural (Hash and 15) + 1);
         Hash := Interfaces.Shift_Right (Hash, 4);
      end loop;
      return Result;
   end Hash_Output;

   function Lock_Path return String is
     (Project_Tools.Files.Join
        (Project_Tools.Files.Temp_Dir,
         "ada-quality-coverage-" & Hash_Output (Root) & ".lock"));

   function Gcov_Notes (Object_Path, Object_Name : String)
     return Project_Tools.Processes.Captured_Process
   is
      Output_Path : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "gcov-dump-" & Object_Name & ".txt");
      Args : GNAT.OS_Lib.Argument_List :=
        [new String'("exec"), new String'("--"), new String'("gcov-dump"),
         new String'(Object_Path)];
      File    : Ada.Text_IO.File_Type;
      Output  : Unbounded_String;
      Status  : Integer := -1;
      Spawned : Boolean := False;
      First_Line : Boolean := True;

      procedure Cleanup is
      begin
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Project_Tools.Files.Delete_File_If_Present (Output_Path);
         for Index in Args'Range loop
            GNAT.OS_Lib.Free (Args (Index));
         end loop;
      end Cleanup;
   begin
      Project_Tools.Files.Delete_File_If_Present (Output_Path);
      GNAT.OS_Lib.Spawn
        (Program_Name => Alr, Args => Args, Output_File => Output_Path,
         Success => Spawned, Return_Code => Status, Err_To_Out => True);
      if Spawned and then Project_Tools.Files.File_Exists (Output_Path) then
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Output_Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            declare
               Line : constant String :=
                 To_String (Ada.Strings.Unbounded.Text_IO.Get_Line (File));
            begin
               if First_Line or else Ada.Strings.Fixed.Index (Line, "FUNCTION") > 0 then
                  Append (Output, Line & ASCII.LF);
               end if;
               First_Line := False;
            end;
         end loop;
      end if;
      Cleanup;
      return (Status => (if Spawned then Status else -1), Output => Output);
   exception
      when others =>  --  AQ: audited exception boundary
         Cleanup;
         raise;
   end Gcov_Notes;

   procedure Exercise_CLI is separate;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "coverage: " & Message);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end Fail;
begin
   if Root'Length = 0 or else Alr'Length = 0 then
      Fail ("project root or Alire executable not found");
      return;
   end if;
   if not Project_Tools.Files.Directory_Exists (Output_Dir) then
      Ada.Directories.Create_Path (Output_Dir);
   end if;
   declare
      Acquired : Boolean;
   begin
      Acquire (Lock, Acquired);
      if not Acquired then
         Fail ("another coverage run is active for this workspace: " & Lock_Path);
         return;
      end if;
   end;
   Ada_Quality.Temporary_Directories.Create (Scratch, "ada-quality-coverage");

   declare
      Run : constant Project_Tools.Processes.Captured_Process :=
        Project_Tools.Processes.Capture
          ("coverage toolchain", Root, Alr,
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
               Project_Tools.Processes.Argument ("gnatls"), Project_Tools.Processes.Argument ("--version")]),
           Quiet => True);
   begin
      if Run.Status /= 0 then Fail ("toolchain fingerprint query failed"); return; end if;
      Toolchain_Fingerprint := To_Unbounded_String (Hash_Output (To_String (Run.Output)));
   end;
   Current_Source_Fingerprint := To_Unbounded_String (Ada_Quality.Checks.Source_Fingerprint (Root));
   --  Instrumented self-assessments must take the same fail-closed TST-03 path
   --  before and after final artifact publication. This switch cannot inject
   --  evidence or turn a blocked result into a pass.
   Ada.Environment_Variables.Set ("ADA_QUALITY_INTERNAL_DISABLE_COVERAGE_EVIDENCE", "1");
   declare
      Build : constant Project_Tools.Processes.Captured_Process :=
        Project_Tools.Processes.Capture
          ("coverage build", Tests_Dir, Alr,
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
               Project_Tools.Processes.Argument ("gprbuild"), Project_Tools.Processes.Argument ("-P"),
               Project_Tools.Processes.Argument ("coverage.gpr"),
               Project_Tools.Processes.Argument
                 ("-XADA_QUALITY_COVERAGE_ROOT=" & Ada_Quality.Temporary_Directories.Path (Scratch)),
               Project_Tools.Processes.Argument
                 ("--relocate-build-tree=" &
                  Ada_Quality.Temporary_Directories.Child (Scratch, "relocated")),
               --  Relocate from the file-system root so that every project, including dependencies outside the
               --  workspace such as Alire's build cache, maps to its full path inside the scratch tree.
               Project_Tools.Processes.Argument ("--root-dir=/"),
               Project_Tools.Processes.Argument ("-j0")]),
           Quiet => True);
   begin
      if Build.Status /= 0 then Fail ("instrumented build failed"); return; end if;
   end;

   declare
      Run : constant Project_Tools.Processes.Captured_Process :=
        Project_Tools.Processes.Capture
          ("coverage suite", Tests_Dir, Binary ("ada_quality_tests"),
           Project_Tools.Processes.No_Arguments, Quiet => True);
   begin
      if Run.Status /= 0 then
         Fail ("instrumented test suite failed" & ASCII.LF & To_String (Run.Output));
         return;
      end if;
   end;

   Exercise_CLI;

   declare
      Units : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
        Ada_Quality.Coverage.Production_Units (Root);
      Missing : constant Ada_Quality.Coverage.Production_Unit_Vectors.Vector :=
        Ada_Quality.Coverage.Missing_Objects (Units, Object_Dir);
      Covered : Natural := 0;
      Total   : Natural := 0;
      Files   : File_Coverage_Vectors.Vector;
   begin
      if Units.Is_Empty then
         Fail ("production source inventory is empty");
         return;
      elsif not Missing.Is_Empty then
         Fail ("instrumented coverage data is missing for production unit " &
           To_String (Missing.First_Element.Stem));
         return;
      end if;
      for Unit of Units loop
         declare
            Stem : constant String := To_String (Unit.Stem);
            Object_Name : constant String := Stem & ".gcno";
            Args : constant Project_Tools.Processes.Argument_Vectors.Vector :=
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("exec"), Project_Tools.Processes.Argument ("--"),
                  Project_Tools.Processes.Argument ("gcov"), Project_Tools.Processes.Argument ("-n"),
                  Project_Tools.Processes.Argument ("-o"),
                  Project_Tools.Processes.Argument (Object_Dir),
                  Project_Tools.Processes.Argument (Project_Tools.Files.Join (Object_Dir, Object_Name))]);
            Run : constant Project_Tools.Processes.Captured_Process :=
              Project_Tools.Processes.Capture ("gcov", Tests_Dir, Alr, Args, Quiet => True);
            Notes_Run : constant Project_Tools.Processes.Captured_Process :=
              Gcov_Notes (Project_Tools.Files.Join (Object_Dir, Object_Name), Object_Name);
            Gcov_Output : constant String := Per_File_Gcov_Output (To_String (Run.Output));
            Unit_Covered : Natural := 0;
            Unit_Total   : Natural := 0;
            Runs_Succeeded : Boolean;

            procedure Check_Tool_Runs is
            begin
               Runs_Succeeded := False;
               if Run.Status /= 0 then
                  Fail ("gcov failed for " & Object_Name);
               elsif Notes_Run.Status /= 0 then
                  Fail ("gcov-dump failed for " & Object_Name);
               else
                  Runs_Succeeded := True;
               end if;
            end Check_Tool_Runs;

            procedure Include_Source (Source : Unbounded_String) is
               One : Project_Tools.Gcov.Coverage_Summary;
            begin
               if Length (Source) = 0 then return; end if;
               if not Ada_Quality.Coverage.Has_Source_Record (Gcov_Output, To_String (Source)) then return; end if;
               One := Project_Tools.Gcov.Parse_Lines_Executed_Output
                 (Gcov_Output, To_String (Source));
               Unit_Covered := Unit_Covered + Project_Tools.Gcov.Covered_Lines (One);
               Unit_Total := Unit_Total + Project_Tools.Gcov.Total_Lines (One);
            end Include_Source;
         begin
            Check_Tool_Runs;
            if not Runs_Succeeded then return; end if;
            if not Ada_Quality.Coverage.Has_Complete_Source_Records
              (Gcov_Output, To_String (Notes_Run.Output), Unit)
            then
               Fail ("gcov output is missing a production source in unit " & Stem);
               return;
            end if;
            Include_Source (Unit.Body_Path);
            Include_Source (Unit.Spec_Path);
            for Path of Unit.Subunit_Paths loop
               Include_Source (Path);
            end loop;
            Covered := Covered + Unit_Covered;
            Total := Total + Unit_Total;
            Files.Append
              (File_Coverage'(Name => To_Unbounded_String (Stem),
                Covered => Unit_Covered, Total => Unit_Total));
         end;
      end loop;
      declare
         Summary : constant Project_Tools.Gcov.Coverage_Summary := Project_Tools.Gcov.Summary (Covered, Total);
         Source_Fingerprint : constant String := To_String (Current_Source_Fingerprint);
         Previous_Source : constant String :=
           Project_Tools.Files.Value_Of (Stability_Path, "source_fingerprint");
         Previous_Toolchain : constant String :=
           Project_Tools.Files.Value_Of (Stability_Path, "toolchain_fingerprint");
         File_Details : Unbounded_String;
         Artifact_Text : Unbounded_String;
      begin
         if Total = 0 then Fail ("gcov found no production executable lines"); return; end if;
         if Previous_Source = Source_Fingerprint and then
           Previous_Toolchain = To_String (Toolchain_Fingerprint)
         then
            for Unit of Files loop
               declare
                  Name : constant String := To_String (Unit.Name);
                  Previous_Covered : constant String :=
                    Project_Tools.Files.Value_Of (Stability_Path, "file_" & Name & "_covered");
                  Previous_Total : constant String :=
                    Project_Tools.Files.Value_Of (Stability_Path, "file_" & Name & "_total");
               begin
                  if Previous_Covered /= Trim (Natural'Image (Unit.Covered)) or else
                    Previous_Total /= Trim (Natural'Image (Unit.Total))
                  then
                     Fail
                       ("coverage is unstable for " & Name & ": expected " & Previous_Covered & "/" &
                        Previous_Total & ", measured " & Trim (Natural'Image (Unit.Covered)) & "/" &
                        Trim (Natural'Image (Unit.Total)));
                     return;
                  end if;
               end;
            end loop;
            declare
               Previous_Covered : constant String :=
                 Project_Tools.Files.Value_Of (Stability_Path, "covered");
               Previous_Total : constant String := Project_Tools.Files.Value_Of (Stability_Path, "total");
            begin
               if Previous_Covered /= Trim (Natural'Image (Covered)) or else
                 Previous_Total /= Trim (Natural'Image (Total))
               then
                  Fail
                    ("coverage is unstable for the same source and toolchain fingerprint: expected " &
                     Previous_Covered & "/" & Previous_Total & ", measured " &
                     Trim (Natural'Image (Covered)) & "/" & Trim (Natural'Image (Total)));
                  return;
               end if;
            end;
         end if;
         for Unit of Files loop
            declare
               Name : constant String := To_String (Unit.Name);
            begin
               Append
                 (File_Details,
                  "file_" & Name & "_covered=" & Trim (Natural'Image (Unit.Covered)) & ASCII.LF &
                  "file_" & Name & "_total=" & Trim (Natural'Image (Unit.Total)) & ASCII.LF);
            end;
         end loop;
         Artifact_Text := To_Unbounded_String
           ("covered=" & Trim (Natural'Image (Covered)) & ASCII.LF &
            "total=" & Trim (Natural'Image (Total)) & ASCII.LF &
            "complete=true" & ASCII.LF &
            "inventory=gcov-production-lines-v3" & ASCII.LF &
            "excluded_ada_quality_coverage=coverage-driver" & ASCII.LF &
            "source_fingerprint=" & Source_Fingerprint & ASCII.LF &
            "toolchain_fingerprint=" & To_String (Toolchain_Fingerprint) & ASCII.LF &
            To_String (File_Details));
         Publish_Artifacts (To_String (Artifact_Text));
         Ada.Text_IO.Put_Line
           ("coverage " & Trim (Natural'Image (Covered)) & "/" & Trim (Natural'Image (Total)) & " (" &
            Project_Tools.Gcov.Percent_Image (Summary) & ")");
         if not Ada_Quality.Types.Coverage_Passes (Covered, Total) then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      end;
   end;
end Ada_Quality_Coverage;
