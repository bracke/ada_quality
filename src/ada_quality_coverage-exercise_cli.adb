separate (Ada_Quality_Coverage)
procedure Exercise_CLI is
      CLI_Binary : constant String := Binary ("ada-quality");
      DB_Path    : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.db");
      Missing_Policy : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "missing-policy.toml");
      Missing_Read_DB : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "missing-read.db");
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
            raise Program_Error with Label & " did not report: " & Expected_Text & ASCII.LF & To_String (Result.Output);
         end if;
      end Run_CLI;

      function Latest_Completed_Assessment_Id return Positive is
         Result : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture
             ("completed assessment identity", Root, CLI_Binary,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("status"),
                  Project_Tools.Processes.Argument ("--database"),
                  Project_Tools.Processes.Argument (DB_Path)]),
              Quiet => True);
         Output : constant String := To_String (Result.Output);
         Marker : constant Natural :=
           Ada.Strings.Fixed.Index (Output, " project 1 completed", Going => Ada.Strings.Backward);
         Line_Start : Natural := Marker;
      begin
         if Result.Status /= 0 or else Marker = 0 then
            raise Program_Error with "completed assessment identity is unavailable" & ASCII.LF & Output;
         end if;
         while Line_Start > Output'First and then Output (Line_Start - 1) /= ASCII.LF loop
            Line_Start := Line_Start - 1;
         end loop;
         return Positive'Value
           (Ada.Strings.Fixed.Trim (Output (Line_Start .. Marker - 1), Ada.Strings.Both));
      end Latest_Completed_Assessment_Id;

      procedure Exercise_Happy_Path is
         First_Assessment  : Positive := 1;
         Second_Assessment : Positive := 1;

         function Image (Value : Positive) return String is
           (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));
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
      First_Assessment := Latest_Completed_Assessment_Id;
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
      Second_Assessment := Latest_Completed_Assessment_Id;
      Run_CLI
        ("regressions with compatible baseline",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
      Run_CLI
        ("selected assessment text",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("show"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--no-color")]),
         Expected_Text => "STR-01");
      for Format of Project_Tools.Processes.Argument_Items'
        ([Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("sarif"),
          Project_Tools.Processes.Argument ("junit")])
      loop
         declare
            Name : constant String := To_String (Format);
            Expected : constant String :=
              (if Name = "json" then """assessment_id"""
               elsif Name = "sarif" then """version"": ""2.1.0"""
               else "<testsuites tests=""33""");
         begin
            Run_CLI
              ("selected assessment " & Name,
               Project_Tools.Processes.Arguments
                 ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("show"),
                   Project_Tools.Processes.Argument (Image (First_Assessment)),
                   Project_Tools.Processes.Argument ("--format"), Format,
                   Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
                   Project_Tools.Processes.Argument ("--no-color")]),
               Expected_Text => Expected);
         end;
      end loop;
      Run_CLI
        ("selected assessment regressions",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--current"),
             Project_Tools.Processes.Argument (Image (Second_Assessment)),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
      Run_CLI
        ("explicit assessment comparison text",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("diff"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument (Image (Second_Assessment)),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
      Run_CLI
        ("explicit assessment comparison JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("diff"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument (Image (Second_Assessment)),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("json"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""assessment-comparison""");
      Run_CLI
        ("explicit regression baseline",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--baseline"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument ("--current"),
             Project_Tools.Processes.Argument (Image (Second_Assessment)),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
      Run_CLI
        ("filtered history JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--status"),
             Project_Tools.Processes.Argument ("completed"), Project_Tools.Processes.Argument ("--limit"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--since"),
             Project_Tools.Processes.Argument ("2000-01-01T00:00:00Z"),
             Project_Tools.Processes.Argument ("--until"),
             Project_Tools.Processes.Argument ("2099-12-31T23:59:59Z"),
             Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""assessment-history""");
      Run_CLI
        ("metric trend text",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("trend"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--indicator"),
             Project_Tools.Processes.Argument ("SRC-03"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "SRC-03=");
      Run_CLI
        ("metric trend JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("trend"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--indicator"),
             Project_Tools.Processes.Argument ("SRC-03"), Project_Tools.Processes.Argument ("--json"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""metric-trend""");
      Run_CLI
        ("multi-metric trend JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("trend"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--all"),
             Project_Tools.Processes.Argument ("--from-run"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument ("--to-run"),
             Project_Tools.Processes.Argument (Image (Second_Assessment)),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("json"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""metric-trends""");
      Run_CLI
        ("multi-metric trend CSV",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("trend"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--all"),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("csv"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "project_id,indicator,unit,run_id,value");
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
         Coverage_Is_Stale : constant Boolean :=
           Project_Tools.Files.Value_Of (Summary_Path, "source_fingerprint") /=
             To_String (Current_Source_Fingerprint);
      begin
         --  Exit 2 is reserved by the release checker for stale coverage. It
         --  is expected only while this driver is generating the replacement.
         if Release_Run.Status /= 0 and then
           (Release_Run.Status /= 2 or else not Coverage_Is_Stale)
         then
            raise Program_Error with "instrumented release checker failed";
         end if;
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
        ("read command does not create a database",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (Missing_Read_DB)]),
         Allow_Four => True);
      if Project_Tools.Files.File_Exists (Missing_Read_DB) then
         raise Program_Error with "read-only CLI command created its missing database";
      end if;
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
      Run_CLI
        ("invalid history status",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--status"),
             Project_Tools.Processes.Argument ("unknown"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Allow_Two => True);
      Run_CLI
        ("invalid history timestamp",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--since"),
             Project_Tools.Processes.Argument ("yesterday"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Allow_Two => True);
      Run_CLI
        ("conflicting trend selectors",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("trend"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--all"),
             Project_Tools.Processes.Argument ("--indicator"), Project_Tools.Processes.Argument ("SRC-03"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Allow_Two => True);
      Run_CLI
        ("reversed assessment comparison",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("diff"),
             Project_Tools.Processes.Argument ("2"), Project_Tools.Processes.Argument ("1"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Allow_Two => True);
      end Exercise_Error_Paths;

      procedure Exercise_Batch_Continuation is
         Batch_Root : constant String :=
           Ada_Quality.Temporary_Directories.Child (Scratch, "batch-projects");

         procedure Create_Project (Number : Positive; Failing : Boolean := False) is
            Directory : constant String := Project_Tools.Files.Join
              (Batch_Root, "project-" & Ada.Strings.Fixed.Trim (Positive'Image (Number), Ada.Strings.Both));
            Manifest : Unbounded_String := To_Unbounded_String
              ("name = ""batch_" & Ada.Strings.Fixed.Trim (Positive'Image (Number), Ada.Strings.Both) &
               """" & ASCII.LF & "version = ""0.1.0""" & ASCII.LF);
         begin
            Ada.Directories.Create_Path (Directory);
            if Failing then
               Append
                 (Manifest,
                  "[[pins]]" & ASCII.LF & "outside = { path = ""../../../etc"" }" & ASCII.LF);
            end if;
            Project_Tools.Files.Write_Text_File
              (Project_Tools.Files.Join (Directory, "alire.toml"), To_String (Manifest));
            Run_CLI
              ("batch project add" & Positive'Image (Number),
               Project_Tools.Processes.Arguments
                 ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("add"),
                   Project_Tools.Processes.Argument (Directory), Project_Tools.Processes.Argument ("--database"),
                   Project_Tools.Processes.Argument (DB_Path)]));
         end Create_Project;
      begin
         Cleanup_Database;
         Ada.Directories.Create_Path (Batch_Root);
         Run_CLI
           ("batch database init",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
                Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("init")]));
         Create_Project (1);
         Create_Project (2, Failing => True);
         Create_Project (3);
         Run_CLI
           ("three-project assessment",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--all"),
                Project_Tools.Processes.Argument ("--json"),
                Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
                Project_Tools.Processes.Argument ("--policy"),
                Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml")),
                Project_Tools.Processes.Argument ("--no-color")]),
            Allow_Three => True, Expected_Text => """kind"": ""assessment-batch""");
         Run_CLI
           ("interrupted middle project",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--database"),
                Project_Tools.Processes.Argument (DB_Path)]),
            Expected_Text => "project 2 interrupted");
         Run_CLI
           ("completed final project",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--database"),
                Project_Tools.Processes.Argument (DB_Path)]),
            Expected_Text => "project 3 completed");
      end Exercise_Batch_Continuation;
begin
      Exercise_Happy_Path;
      Exercise_Error_Paths;
      Exercise_Batch_Continuation;
      Cleanup_Database;
   exception
      when Program_Error =>
         Cleanup_Database;
         raise;
end Exercise_CLI;
