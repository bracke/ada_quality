separate (Ada_Quality_Coverage)
--  AQ-WAIVER: SRC-03 target=image justification=coverage-driver-exercises-one-ordered-cli-workflow-matrix
procedure Exercise_CLI is
      CLI_Binary : constant String := Binary ("ada-quality");
      DB_Path    : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.db");
      Backup_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.backup");
      Export_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.export");
      Restored_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage-restored.db");
      Imported_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage-imported.db");
      Archive_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "retention.export");
      HTML_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "portfolio.html");
      Assessment_HTML_Path : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "assessment.html");
      Changed_List_Path : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "changed-files.txt");
      Reuse_Output : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "reuse.json");
      Scan_Output : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "scan.json");
      Diff_Output : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "comparison.json");
      Trend_Output : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "trend.csv");
      Findings_Output : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "findings.json");
      Policy_Base : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "generated-policy.toml");
      Policy_Profile : constant String := Ada_Quality.Temporary_Directories.Child
        (Scratch, "generated-policy.ci.toml");
      Effective_Output : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "effective.toml");
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
         Project_Tools.Files.Delete_File_If_Present (Export_Path);
         Project_Tools.Files.Delete_File_If_Present (Restored_Path);
         Project_Tools.Files.Delete_File_If_Present (Restored_Path & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Restored_Path & ".fts");
         Project_Tools.Files.Delete_File_If_Present (Restored_Path & ".lock");
         Project_Tools.Files.Delete_File_If_Present (Imported_Path);
         Project_Tools.Files.Delete_File_If_Present (Imported_Path & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Imported_Path & ".fts");
         Project_Tools.Files.Delete_File_If_Present (Imported_Path & ".lock");
         Project_Tools.Files.Delete_File_If_Present (Archive_Path);
         Project_Tools.Files.Delete_File_If_Present (HTML_Path);
         Project_Tools.Files.Delete_File_If_Present (Assessment_HTML_Path);
         Project_Tools.Files.Delete_File_If_Present (Changed_List_Path);
         Project_Tools.Files.Delete_File_If_Present (Reuse_Output);
         Project_Tools.Files.Delete_File_If_Present (Scan_Output);
         Project_Tools.Files.Delete_File_If_Present (Diff_Output);
         Project_Tools.Files.Delete_File_If_Present (Trend_Output);
         Project_Tools.Files.Delete_File_If_Present (Findings_Output);
         Project_Tools.Files.Delete_File_If_Present (Policy_Base);
         Project_Tools.Files.Delete_File_If_Present (Policy_Profile);
         Project_Tools.Files.Delete_File_If_Present (Effective_Output);
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB);
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB & ".fts");
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB & ".lock");
         if Project_Tools.Files.Exists (Backup_Path) then
            Project_Tools.Files.Delete_Tree (Backup_Path);
         end if;
      end Cleanup_Database;

      procedure Run_CLI
        (Label       : String;
         Args        : Project_Tools.Processes.Argument_Vectors.Vector;
         Allow_One   : Boolean := False;
         Allow_Two   : Boolean := False;
         Allow_Three : Boolean := False;
         Allow_Four  : Boolean := False;
         Expected_Text : String := "";
         Expected_Alternate : String := "")
      is
         Result : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture (Label, Root, CLI_Binary, Args, Quiet => True);
      begin
         if Result.Status /= 0 and then not (Allow_One and then Result.Status = 1) and then
           not (Allow_Two and then Result.Status = 2) and then not (Allow_Three and then Result.Status = 3) and then
           not (Allow_Four and then Result.Status = 4)
         then
            raise Program_Error with
              Label & " failed with status" & Integer'Image (Result.Status) & ASCII.LF &
              To_String (Result.Output);
         elsif Expected_Text'Length > 0 and then
           Ada.Strings.Fixed.Index (To_String (Result.Output), Expected_Text) = 0 and then
           (Expected_Alternate'Length = 0 or else
            Ada.Strings.Fixed.Index (To_String (Result.Output), Expected_Alternate) = 0)
         then
            raise Program_Error with Label & " did not report: " & Expected_Text & ASCII.LF & To_String (Result.Output);
         end if;
      end Run_CLI;

      function Latest_Assessment_Completed return Boolean is
         Result : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture
             ("assessment status", Root, CLI_Binary,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("history"),
                  Project_Tools.Processes.Argument ("--database"),
                  Project_Tools.Processes.Argument (DB_Path)]),
              Quiet => True);
         Output : constant String := To_String (Result.Output);
         Completed_At : constant Natural :=
           Ada.Strings.Fixed.Index (Output, "project 1 completed", Going => Ada.Strings.Backward);
         Latest_At : constant Natural := Natural'Max
           (Completed_At,
            Natural'Max
              (Ada.Strings.Fixed.Index
                 (Output, "project 1 interrupted", Going => Ada.Strings.Backward),
               Natural'Max
                 (Ada.Strings.Fixed.Index
                    (Output, "project 1 invalid", Going => Ada.Strings.Backward),
                  Ada.Strings.Fixed.Index
                    (Output, "project 1 running", Going => Ada.Strings.Backward))));
      begin
         if Result.Status /= 0 then
            raise Program_Error with "assessment status failed" & ASCII.LF & Output;
         end if;
         return Completed_At > 0 and then Completed_At = Latest_At;
      end Latest_Assessment_Completed;

      procedure Run_Completed_Assessment (Label : String) is
         Arguments : constant Project_Tools.Processes.Argument_Vectors.Vector :=
           Project_Tools.Processes.Arguments
             ([Project_Tools.Processes.Argument ("check"),
               Project_Tools.Processes.Argument ("--project"),
               Project_Tools.Processes.Argument ("1"),
               Project_Tools.Processes.Argument ("--database"),
               Project_Tools.Processes.Argument (DB_Path),
               Project_Tools.Processes.Argument ("--policy"),
               Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml")),
               Project_Tools.Processes.Argument ("--no-color")]);
      begin
         for Attempt in 1 .. 2 loop
            Run_CLI
              (Label & (if Attempt = 1 then "" else " retry"), Arguments,
               Allow_One => True, Allow_Three => True);
            if Latest_Assessment_Completed then
               return;
            end if;
         end loop;
         raise Program_Error with Label & " did not produce a completed assessment";
      end Run_Completed_Assessment;

      function Latest_Completed_Assessment_Id return Positive is
         Result : constant Project_Tools.Processes.Captured_Process :=
           Project_Tools.Processes.Capture
             ("completed assessment identity", Root, CLI_Binary,
              Project_Tools.Processes.Arguments
                ([Project_Tools.Processes.Argument ("history"),
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
        ("policy init",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("init"),
             Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base)]),
         Expected_Text => "created ");
      Run_CLI
        ("policy profile init",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("init"),
             Project_Tools.Processes.Argument ("--profile"), Project_Tools.Processes.Argument ("ci"),
             Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base)]),
         Expected_Text => "created ");
      Run_CLI
        ("policy profiles",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("profiles"),
             Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base)]),
         Expected_Text => "ci");
      Run_CLI
        ("explain indicator",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("explain"), Project_Tools.Processes.Argument ("SRC-03")]),
         Expected_Text => "remediation:");
      Run_CLI
        ("indicator list JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("indicator"), Project_Tools.Processes.Argument ("list"),
             Project_Tools.Processes.Argument ("--category"), Project_Tools.Processes.Argument ("source"),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("json")]),
         Expected_Text => """kind"": ""indicator-catalog""");
      Run_CLI
        ("project add",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("add"),
             Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]));
      Run_CLI
        ("project list JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("list"),
             Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""project-list""");
      Run_CLI
        ("effective project policy",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("effective"),
             Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1"),
             Project_Tools.Processes.Argument ("--profile"), Project_Tools.Processes.Argument ("ci"),
             Project_Tools.Processes.Argument ("--output"), Project_Tools.Processes.Argument (Effective_Output),
             Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      if not Project_Tools.Files.File_Exists (Effective_Output) then
         raise Program_Error with "effective policy output was not created";
      end if;
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
        ("project discover dry run",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("discover"),
             Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "registered 1");
      Run_CLI
        ("project discover JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("discover"),
             Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("--json"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""project-discovery""");
      Run_CLI
        ("project registry sync",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("sync"),
             Project_Tools.Processes.Argument (Root), Project_Tools.Processes.Argument ("--json"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""project-discovery""");
      Run_CLI
        ("project relocate",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("relocate"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument (Root),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "relocated project 1");
      Run_CLI
        ("changed source scan",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("scan"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--changed-file"),
             Project_Tools.Processes.Argument ("src/ada_quality.ads"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_One => True, Expected_Text => "changed source(s)");
      Project_Tools.Files.Write_Text_File (Changed_List_Path, "src/ada_quality.ads" & ASCII.LF);
      Run_CLI
        ("changed source list scan",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("scan"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--files-from"),
             Project_Tools.Processes.Argument (Changed_List_Path),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_One => True, Expected_Text => "changed source(s)");
      for Format of Project_Tools.Processes.Argument_Items'
        ([Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("sarif")])
      loop
         Run_CLI
           ("changed source " & To_String (Format),
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("scan"), Project_Tools.Processes.Argument ("--project"),
                Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--changed-file"),
                Project_Tools.Processes.Argument ("src/ada_quality.ads"),
                Project_Tools.Processes.Argument ("--format"), Format,
                Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
                Project_Tools.Processes.Argument ("--policy"),
                Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
            Allow_One => True,
            Expected_Text => (if To_String (Format) = "json" then "changed-source-scan" else "2.1.0"));
      end loop;
      Run_CLI
        ("Git changed source scan",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("scan"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--git-diff"),
             Project_Tools.Processes.Argument ("HEAD"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_One => True, Expected_Text => "changed source(s)");
      Run_CLI
        ("Git working tree modes",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("scan"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--staged"),
             Project_Tools.Processes.Argument ("--unstaged"), Project_Tools.Processes.Argument ("--untracked"),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("json"),
             Project_Tools.Processes.Argument ("--output"), Project_Tools.Processes.Argument (Scan_Output),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_One => True);
      if not Project_Tools.Files.File_Exists (Scan_Output) or else
        Ada.Strings.Fixed.Index
          (Project_Tools.Files.Read_Raw_File (Scan_Output), "changed-source-scan") = 0
      then
         raise Program_Error with "Git working tree scan output was not created";
      end if;
      Run_Completed_Assessment ("full assessment");
      First_Assessment := Latest_Completed_Assessment_Id;
      Run_CLI
        ("first assessment alias",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("alias"),
             Project_Tools.Processes.Argument ("release-1"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "aliased release-1");
      Run_CLI
        ("regressions without baseline",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "comparison unavailable: no baseline assessment exists",
         Expected_Alternate => "comparison unavailable: no completed baseline exists");
      Run_CLI
        ("regression gate without baseline",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1"),
             Project_Tools.Processes.Argument ("--fail-on-regression"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Allow_Three => True, Expected_Text => "comparison unavailable");
      Run_Completed_Assessment ("second full assessment");
      Second_Assessment := Latest_Completed_Assessment_Id;
      Run_CLI
        ("reuse unchanged assessment",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--reuse-unchanged"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_Three => True, Expected_Text => "reused assessment");
      Run_CLI
        ("reuse unchanged assessment JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--reuse-unchanged"),
             Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--output"),
             Project_Tools.Processes.Argument (Reuse_Output),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument (Project_Tools.Files.Join (Root, "quality-policy.toml"))]),
         Allow_Three => True);
      if not Project_Tools.Files.File_Exists (Reuse_Output) or else
        Ada.Strings.Fixed.Index (Project_Tools.Files.Read_Raw_File (Reuse_Output), "assessment-reuse") = 0
      then
         raise Program_Error with "reuse JSON output was not created";
      end if;
      Run_CLI
        ("second assessment alias",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("alias"),
             Project_Tools.Processes.Argument ("release-2"),
             Project_Tools.Processes.Argument (Image (Second_Assessment)),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      Run_CLI
        ("assessment alias list",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("aliases"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "release-2 assessment");
      Run_CLI
        ("assessment alias list JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("aliases"),
             Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""assessment-aliases""");
      Run_CLI
        ("regressions with compatible baseline",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
      Run_CLI
        ("clean regression gate",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--baseline"), Project_Tools.Processes.Argument ("release-1"),
             Project_Tools.Processes.Argument ("--current"), Project_Tools.Processes.Argument ("release-2"),
             Project_Tools.Processes.Argument ("--fail-on-regression"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
      Run_CLI
        ("selected assessment text",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("show"),
             Project_Tools.Processes.Argument ("release-1"),
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
        ("selected assessment HTML",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("show"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("html"),
             Project_Tools.Processes.Argument ("--output"),
             Project_Tools.Processes.Argument (Assessment_HTML_Path),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      if not Project_Tools.Files.File_Exists (Assessment_HTML_Path) then
         raise Program_Error with "assessment HTML output was not created";
      end if;
      Run_CLI
        ("selected assessment regressions",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("regressions"),
             Project_Tools.Processes.Argument ("--current"),
             Project_Tools.Processes.Argument ("release-2"),
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
        ("assessment comparison file output",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("diff"),
             Project_Tools.Processes.Argument (Image (First_Assessment)),
             Project_Tools.Processes.Argument (Image (Second_Assessment)),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("json"),
             Project_Tools.Processes.Argument ("--output"), Project_Tools.Processes.Argument (Diff_Output),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      Run_CLI
        ("aliased assessment comparison",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("diff"),
             Project_Tools.Processes.Argument ("release-1"),
             Project_Tools.Processes.Argument ("release-2"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "no regressions in comparable assessments");
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
             Project_Tools.Processes.Argument ("release-1"),
             Project_Tools.Processes.Argument ("--to-run"),
             Project_Tools.Processes.Argument ("release-2"),
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
        ("metric trend file output",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("trend"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--all"),
             Project_Tools.Processes.Argument ("--format"), Project_Tools.Processes.Argument ("csv"),
             Project_Tools.Processes.Argument ("--output"), Project_Tools.Processes.Argument (Trend_Output),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      Run_CLI
        ("JSON report",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("report"), Project_Tools.Processes.Argument ("--format"),
             Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--no-color")]));
      Run_CLI
        ("filtered JSON report",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("report"), Project_Tools.Processes.Argument ("--format"),
             Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("--project"),
             Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--since"),
             Project_Tools.Processes.Argument ("2000-01-01T00:00:00Z"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """schema_version"": 2");
      Run_CLI
        ("portfolio HTML report",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("report"), Project_Tools.Processes.Argument ("--format"),
             Project_Tools.Processes.Argument ("html"), Project_Tools.Processes.Argument ("--output"),
             Project_Tools.Processes.Argument (HTML_Path), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]));
      if not Project_Tools.Files.File_Exists (HTML_Path) then
         raise Program_Error with "portfolio HTML output was not created";
      end if;
      Run_CLI
        ("filtered findings JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("findings"), Project_Tools.Processes.Argument ("--severity"),
             Project_Tools.Processes.Argument ("high"), Project_Tools.Processes.Argument ("--format"),
             Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""findings""");
      Run_CLI
        ("findings file output",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("findings"), Project_Tools.Processes.Argument ("--format"),
             Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("--output"),
             Project_Tools.Processes.Argument (Findings_Output),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
      if not Project_Tools.Files.File_Exists (Diff_Output) or else
        not Project_Tools.Files.File_Exists (Trend_Output) or else
        not Project_Tools.Files.File_Exists (Findings_Output)
      then
         raise Program_Error with "structured file output was not created";
      end if;
      Run_CLI
        ("portfolio status JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--json"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""portfolio-status""");
      for Filter of Project_Tools.Processes.Argument_Items'
        ([Project_Tools.Processes.Argument ("unhealthy"),
          Project_Tools.Processes.Argument ("regressed")])
      loop
         Run_CLI
           ("portfolio status " & To_String (Filter),
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--only"), Filter,
                Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
                Project_Tools.Processes.Argument (DB_Path)]),
            Expected_Text => """kind"": ""portfolio-status""");
      end loop;
      Run_CLI
        ("portfolio status stale",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--only"),
             Project_Tools.Processes.Argument ("stale"), Project_Tools.Processes.Argument ("--since"),
             Project_Tools.Processes.Argument ("2099-01-01T00:00:00Z"),
             Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""portfolio-status""");
      Run_CLI
        ("database statistics",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("stats"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "total rows");
      Run_CLI
        ("database statistics JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("stats"),
             Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => """kind"": ""database-statistics""");
      Run_CLI
        ("database compact",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("compact"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "database compacted");
      for Shell of Project_Tools.Processes.Argument_Items'
        ([Project_Tools.Processes.Argument ("bash"), Project_Tools.Processes.Argument ("zsh"),
          Project_Tools.Processes.Argument ("fish")])
      loop
         Run_CLI
           ("completion " & To_String (Shell),
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("completion"), Shell]),
            Expected_Text => "ada-quality");
      end loop;
      Run_CLI
        ("database backup",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("backup"),
             Project_Tools.Processes.Argument (Backup_Path), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "backup created");
      Run_CLI
        ("database export",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("export"),
             Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "export created");
      Run_CLI
        ("database retention archive",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("archive"),
             Project_Tools.Processes.Argument (Archive_Path), Project_Tools.Processes.Argument ("--before"),
             Project_Tools.Processes.Argument ("2000-01-01T00:00:00Z"),
             Project_Tools.Processes.Argument ("--keep"), Project_Tools.Processes.Argument ("1"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
         Expected_Text => "archived database");
      Run_CLI
        ("database restore",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("restore"),
             Project_Tools.Processes.Argument (Backup_Path), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (Restored_Path)]),
         Expected_Text => "restored ");
      Run_CLI
        ("restored database check",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("check"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (Restored_Path)]),
         Expected_Text => "integrity check passed");
      Run_CLI
        ("database logical import",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("import"),
             Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument ("--database"),
             Project_Tools.Processes.Argument (Imported_Path)]),
         Expected_Text => "imported ");
      Run_CLI
        ("imported database check",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("check"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (Imported_Path)]),
         Expected_Text => "integrity check passed");
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
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (Missing_Read_DB),
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
                Project_Tools.Processes.Argument ("--jobs"), Project_Tools.Processes.Argument ("2"),
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
            Expected_Text => "interrupted");
         Run_CLI
           ("completed final project",
            Project_Tools.Processes.Arguments
              ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--database"),
                Project_Tools.Processes.Argument (DB_Path)]),
            Expected_Text => "completed");
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
