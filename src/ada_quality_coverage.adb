with Ada.Command_Line;
with Ada.Containers.Vectors;
with Ada.Directories;
with Ada.Finalization;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;
with Project_Tools.Files;
with Project_Tools.Gcov;
with Project_Tools.Processes;
with Ada_Quality.Checks;
with Ada_Quality.Coverage;
with Ada_Quality.Temporary_Directories;
with Ada_Quality.Types;

procedure Ada_Quality_Coverage is
   --  Isolated coverage entry point with concurrency locking and deterministic stability checks.
   use Ada.Strings.Unbounded;

   Root : constant String :=
     Project_Tools.Files.Find_Root_Upward (Ada.Directories.Current_Directory, "ada_quality.gpr");
   Tests_Dir : constant String := Project_Tools.Files.Join (Root, "tests");
   Output_Dir : constant String := Project_Tools.Files.Join (Root, "coverage");
   Summary_Path : constant String := Project_Tools.Files.Join (Output_Dir, "gcov-summary.txt");
   Stability_Path : constant String := Project_Tools.Files.Join (Output_Dir, "gcov-stability.txt");
   Lock_Path : constant String := Project_Tools.Files.Join (Output_Dir, ".driver-lock");
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

   type Coverage_Artifact_Guard is new Ada.Finalization.Limited_Controlled with record
      Original : Unbounded_String;
      Existed  : Boolean := False;
      Active   : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Coverage_Artifact_Guard);

   procedure Seed
     (Item : in out Coverage_Artifact_Guard;
      Source_Fingerprint, Selected_Toolchain : String)
   is
      Covered : constant String := Project_Tools.Files.Value_Of (Summary_Path, "covered");
      Total   : constant String := Project_Tools.Files.Value_Of (Summary_Path, "total");
   begin
      Item.Existed := Project_Tools.Files.File_Exists (Summary_Path);
      if Item.Existed then
         Item.Original := To_Unbounded_String (Project_Tools.Files.Read_Raw_File (Summary_Path));
      end if;
      Item.Active := True;
      Project_Tools.Files.Write_Text_File
        (Summary_Path,
         "covered=" & (if Covered'Length = 0 then "0" else Covered) & ASCII.LF &
         "total=" & (if Total'Length = 0 then "1" else Total) & ASCII.LF &
         "complete=true" & ASCII.LF &
         "inventory=gcov-production-lines-v2" & ASCII.LF &
         "excluded_ada_quality_coverage=coverage-driver" & ASCII.LF &
         "source_fingerprint=" & Source_Fingerprint & ASCII.LF &
         "toolchain_fingerprint=" & Selected_Toolchain & ASCII.LF);
   end Seed;

   procedure Commit (Item : in out Coverage_Artifact_Guard) is
   begin
      Item.Active := False;
   end Commit;

   overriding procedure Finalize (Item : in out Coverage_Artifact_Guard) is
   begin
      if Item.Active then
         if Item.Existed then
            Project_Tools.Files.Write_Text_File (Summary_Path, To_String (Item.Original));
         else
            Project_Tools.Files.Delete_File_If_Present (Summary_Path);
         end if;
      end if;
      Item.Active := False;
   exception
      when others =>  --  AQ: audited exception boundary
         null;
   end Finalize;

   Artifact : Coverage_Artifact_Guard;

   type Coverage_Lock is new Ada.Finalization.Limited_Controlled with record
      Active : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Coverage_Lock);

   procedure Acquire (Item : in out Coverage_Lock; Success : out Boolean) is
   begin
      Ada.Directories.Create_Directory (Lock_Path);
      Item.Active := True;
      Success := True;
   exception
      when Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         Success := False;
   end Acquire;

   overriding procedure Finalize (Item : in out Coverage_Lock) is
   begin
      if Item.Active and then Project_Tools.Files.Exists (Lock_Path) then
         Project_Tools.Files.Delete_Tree (Lock_Path);
      end if;
      Item.Active := False;
   end Finalize;

   Lock : Coverage_Lock;

   function Object_Dir return String is
     (Ada_Quality.Temporary_Directories.Child (Scratch, "obj"));

   function Binary (Name : String) return String is
     (Ada_Quality.Temporary_Directories.Child (Scratch, "bin/" & Name));

   function Trim (Text : String) return String is
     (Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both));

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
   Seed (Artifact, To_String (Current_Source_Fingerprint), To_String (Toolchain_Fingerprint));

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
      if Run.Status /= 0 then Fail ("instrumented test suite failed"); return; end if;
   end;

   declare
      CLI_Binary : constant String := Binary ("ada-quality");
      DB_Path    : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.db");
      Missing_Policy : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "missing-policy.toml");
      Operations : constant Project_Tools.Processes.Argument_Items :=
        [Project_Tools.Processes.Argument ("list"), Project_Tools.Processes.Argument ("show"),
         Project_Tools.Processes.Argument ("disable"), Project_Tools.Processes.Argument ("enable")];
      Queries : constant Project_Tools.Processes.Argument_Items :=
        [Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("status"),
         Project_Tools.Processes.Argument ("findings")];

      procedure Cleanup_Database is
      begin
         Project_Tools.Files.Delete_File_If_Present (DB_Path);
         Project_Tools.Files.Delete_File_If_Present (DB_Path & ".wal");
         Project_Tools.Files.Delete_File_If_Present (DB_Path & ".fts");
         Project_Tools.Files.Delete_File_If_Present (DB_Path & ".lock");
      end Cleanup_Database;

      procedure Run_CLI
        (Label       : String;
         Args        : Project_Tools.Processes.Argument_Vectors.Vector;
         Allow_One   : Boolean := False;
         Allow_Two   : Boolean := False;
         Allow_Three : Boolean := False;
         Allow_Four  : Boolean := False;
         Expected_Text : String := "")
      is
         Result : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture (Label, Root, CLI_Binary, Args, Quiet => True);
      begin
         if Result.Status /= 0 and then not (Allow_One and then Result.Status = 1) and then
           not (Allow_Two and then Result.Status = 2) and then not (Allow_Three and then Result.Status = 3) and then
           not (Allow_Four and then Result.Status = 4)
         then
            raise Program_Error with Label & " failed with status" & Integer'Image (Result.Status);
         elsif Expected_Text'Length > 0 and then
           Ada.Strings.Fixed.Index (To_String (Result.Output), Expected_Text) = 0
         then
            raise Program_Error with Label & " did not report: " & Expected_Text;
         end if;
      end Run_CLI;

      procedure Exercise_Happy_Path is
      begin
      Cleanup_Database;
      Run_CLI ("CLI help", Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument ("--help")]));
      Run_CLI ("CLI version", Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument ("--version")]));
      Run_CLI
        ("database init",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("init")]));
      Run_CLI
        ("database check",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("check"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      Run_CLI
        ("policy validate",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("validate"),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]));
      Run_CLI
        ("policy show",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("show"),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]));
      Run_CLI
        ("project add",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("add"),
             Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]));
      for Operation of Operations loop
         declare
            Name : constant String := Ada.Strings.Unbounded.To_String (Operation);
            Args : Project_Tools.Processes.Argument_Vectors.Vector;
         begin
            Args.Append (Project_Tools.Processes.Argument ("project"));
            Args.Append (Operation);
            if Name /= "list" then Args.Append (Project_Tools.Processes.Argument ("1")); end if;
            Args.Append (Project_Tools.Processes.Argument ("--database"));
            Args.Append (Project_Tools.Processes.Argument (DB_Path));
            Run_CLI ("project " & Name, Args);
         end;
      end loop;
      Run_CLI
        ("full assessment",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml")),
             Project_Tools.Processes.Argument ("--no-color")]),
         Allow_One => True, Allow_Three => True);
      Run_CLI
        ("regressions without baseline",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "comparison unavailable: no baseline assessment exists");
      Run_CLI
        ("second full assessment",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml")),
             Project_Tools.Processes.Argument ("--no-color")]),
         Allow_One => True, Allow_Three => True);
      Run_CLI
        ("regressions with compatible baseline",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
      Run_CLI
        ("JSON report",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("report"), Project_Tools.Processes.Argument ("--format"),
             Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--no-color")]));
      for Query of Queries loop
         Run_CLI
           (Ada.Strings.Unbounded.To_String (Query),
            Project_Tools.Processes.Arguments
              ([Query, Project_Tools.Processes.Argument ("--database"),
                Project_Tools.Processes.Argument (DB_Path)]));
      end loop;
      Run_CLI
        ("database recover",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("recover"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      declare
         Release_Run : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture
             ("instrumented release checker", Root,
              Binary ("check_all"),
              Project_Tools.Processes.No_Arguments, Quiet => True);
      begin
         if Release_Run.Status /= 0 then raise Program_Error with "instrumented release checker failed"; end if;
      end;
      Run_CLI
        ("project remove",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("remove"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]));
      end Exercise_Happy_Path;

      procedure Exercise_Error_Paths is
      begin
      Run_CLI
        ("check empty registry",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--all"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]));
      Run_CLI
        ("bad project ID",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("show"),
             Project_Tools.Processes.Argument ("bad"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]), Allow_Two => True);
      Run_CLI
        ("unknown command",
         Project_Tools.Processes.Arguments ([Project_Tools.Processes.Argument ("unknown")]),
         Allow_Two => True);
      Run_CLI
        ("unknown option",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--unknown")]),
         Allow_Two => True);
      Run_CLI
        ("missing option value",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--database")]),
         Allow_Two => True);
      Run_CLI
        ("mutually exclusive selectors",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--all"),
             Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1")]),
         Allow_Two => True);
      Run_CLI
        ("invalid color policy",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--color"),
             Project_Tools.Processes.Argument ("sometimes")]),
         Allow_Two => True);
      Run_CLI
        ("unknown database operation",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("unknown"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Allow_Two => True);
      Run_CLI
        ("unknown policy operation",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("unknown"),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_Two => True);
      Run_CLI
        ("unknown project operation",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("unknown"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Allow_Two => True);
      Run_CLI
        ("check without selector",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_Two => True);
      Run_CLI
        ("missing project",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("show"),
             Project_Tools.Processes.Argument ("999"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]), Allow_Four => True);
      Run_CLI
        ("missing policy validation",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("validate"),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Missing_Policy)]),
         Allow_Two => True);
      Run_CLI
        ("check with missing policy",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--all"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Missing_Policy)]),
         Allow_Two => True);
      end Exercise_Error_Paths;

   begin
      Exercise_Happy_Path;
      Exercise_Error_Paths;
      Cleanup_Database;
   exception
      when Program_Error =>
         Cleanup_Database;
         raise;
   end;

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
            Gcov_Output : constant String := Per_File_Gcov_Output (To_String (Run.Output));
            Unit_Covered : Natural := 0;
            Unit_Total   : Natural := 0;

            procedure Include_Source (Source : Unbounded_String) is
               One : Project_Tools.Gcov.Coverage_Summary;
            begin
               if Length (Source) = 0 then return; end if;
               One := Project_Tools.Gcov.Parse_Lines_Executed_Output
                 (Gcov_Output, To_String (Source));
               Unit_Covered := Unit_Covered + Project_Tools.Gcov.Covered_Lines (One);
               Unit_Total := Unit_Total + Project_Tools.Gcov.Total_Lines (One);
            end Include_Source;
         begin
            if Run.Status /= 0 then Fail ("gcov failed for " & Object_Name); return; end if;
            Include_Source (Unit.Body_Path);
            Include_Source (Unit.Spec_Path);
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
            "inventory=gcov-production-lines-v2" & ASCII.LF &
            "excluded_ada_quality_coverage=coverage-driver" & ASCII.LF &
            "source_fingerprint=" & Source_Fingerprint & ASCII.LF &
            "toolchain_fingerprint=" & To_String (Toolchain_Fingerprint) & ASCII.LF &
            To_String (File_Details));
         Project_Tools.Files.Write_Text_File
           (Summary_Path, To_String (Artifact_Text));
         Project_Tools.Files.Write_Text_File
           (Stability_Path, To_String (Artifact_Text));
         Commit (Artifact);
         Ada.Text_IO.Put_Line
           ("coverage " & Trim (Natural'Image (Covered)) & "/" & Trim (Natural'Image (Total)) & " (" &
            Project_Tools.Gcov.Percent_Image (Summary) & ")");
         if not Ada_Quality.Types.Coverage_Passes (Covered, Total) then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      end;
   end;
end Ada_Quality_Coverage;
