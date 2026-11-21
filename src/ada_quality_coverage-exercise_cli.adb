separate (Ada_Quality_Coverage)
procedure Exercise_CLI is
      CLI_Binary : constant String := Binary ("ada-quality");
      DB_Path    : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.db");
      Backup_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.backup");
      Export_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage.export");
      Private_Key_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "signing.key");
      Public_Key_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "signing.pub");
      Auxiliary_Private_Key_Path : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "auxiliary-signing.key");
      Auxiliary_Public_Key_Path : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "auxiliary-signing.pub");
      Trust_Store : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "trust-store");
      Restored_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage-restored.db");
      Imported_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage-imported.db");
      Merge_Path : constant String := Ada_Quality.Temporary_Directories.Child (Scratch, "coverage-merge.db");
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
      JSON_Policy_Base : constant String :=
        Ada_Quality.Temporary_Directories.Child (Scratch, "generated-policy-json.toml");
      Policy_Profile : constant String := Ada_Quality.Temporary_Directories.Child
        (Scratch, "generated-policy.ci.toml");
      Coverage_Policy : constant String := Ada_Quality.Temporary_Directories.Child
        (Scratch, "coverage-policy.toml");
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
         Project_Tools.Files.Delete_File_If_Present (Export_Path & ".sig");
         Project_Tools.Files.Delete_File_If_Present (Private_Key_Path);
         Project_Tools.Files.Delete_File_If_Present (Public_Key_Path);
         Project_Tools.Files.Delete_File_If_Present (Restored_Path);
         Project_Tools.Files.Delete_File_If_Present (Restored_Path & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Restored_Path & ".fts");
         Project_Tools.Files.Delete_File_If_Present (Restored_Path & ".lock");
         Project_Tools.Files.Delete_File_If_Present (Imported_Path);
         Project_Tools.Files.Delete_File_If_Present (Imported_Path & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Imported_Path & ".fts");
         Project_Tools.Files.Delete_File_If_Present (Imported_Path & ".lock");
         Project_Tools.Files.Delete_File_If_Present (Merge_Path);
         Project_Tools.Files.Delete_File_If_Present (Merge_Path & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Merge_Path & ".fts");
         Project_Tools.Files.Delete_File_If_Present (Merge_Path & ".lock");
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
         Project_Tools.Files.Delete_File_If_Present (JSON_Policy_Base);
         Project_Tools.Files.Delete_File_If_Present (Policy_Profile);
         Project_Tools.Files.Delete_File_If_Present (Effective_Output);
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB);
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB & ".wal");
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB & ".fts");
         Project_Tools.Files.Delete_File_If_Present (Missing_Read_DB & ".lock");
         if Project_Tools.Files.Exists (Backup_Path) then
            Project_Tools.Files.Delete_Tree (Backup_Path);
         end if;
         if Project_Tools.Files.Exists (Trust_Store) then
            Project_Tools.Files.Delete_Tree (Trust_Store);
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
         Expected_Alternate : String := "";
         Merge_Standard_Error : Boolean := False)
      is
         Result : constant Project_Tools.Processes.Captured_Process :=
           (if Merge_Standard_Error then
               Project_Tools.Processes.Capture_Command
                 (CLI_Binary, Args, Err_To_Out => True)
            else Project_Tools.Processes.Capture (Label, Root, CLI_Binary, Args, Quiet => True));
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
               Project_Tools.Processes.Argument (Coverage_Policy),
               Project_Tools.Processes.Argument ("--no-color")]);
         Last_Status : Integer := 0;
         Last_Output : Unbounded_String;
      begin
         for Attempt in 1 .. 2 loop
            declare
               Result : constant Project_Tools.Processes.Captured_Process :=
                 Project_Tools.Processes.Capture
                   (Label & (if Attempt = 1 then "" else " retry"),
                    Root, CLI_Binary, Arguments, Quiet => True);
            begin
               Last_Status := Result.Status;
               Last_Output := Result.Output;
               if Result.Status not in 0 | 1 | 3 then
                  raise Program_Error with
                    Label & " failed with status" & Integer'Image (Result.Status) & ASCII.LF &
                    To_String (Result.Output);
               end if;
            end;
            if Latest_Assessment_Completed then
               return;
            end if;
         end loop;
         declare
            History : constant Project_Tools.Processes.Captured_Process :=
              Project_Tools.Processes.Capture
                ("assessment history", Root, CLI_Binary,
                 Project_Tools.Processes.Arguments
                   ([Project_Tools.Processes.Argument ("history"),
                     Project_Tools.Processes.Argument ("--database"),
                     Project_Tools.Processes.Argument (DB_Path)]),
                 Quiet => True);
         begin
            raise Program_Error with
              Label & " did not produce a completed assessment; last status" &
              Integer'Image (Last_Status) & ASCII.LF & To_String (Last_Output) &
              "assessment history:" & ASCII.LF & To_String (History.Output);
         end;
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

      First_Assessment  : Positive := 1;
      Second_Assessment : Positive := 1;

      function Image (Value : Positive) return String is
        (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

      procedure Exercise_Happy_Setup is separate;
      procedure Exercise_Happy_Assessments is separate;
      procedure Exercise_Happy_Reports is separate;

      procedure Exercise_Happy_Path is
      begin
         Exercise_Happy_Setup;
         Exercise_Happy_Assessments;
         Exercise_Happy_Reports;
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
             Project_Tools.Processes.Argument (Coverage_Policy)]));
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
        ("structured unknown command",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("unknown"),
             Project_Tools.Processes.Argument ("--error-format"),
             Project_Tools.Processes.Argument ("json")]),
         Allow_Two => True, Expected_Text => """kind"":""error""",
         Merge_Standard_Error => True);
      Run_CLI
        ("structured invalid check policy",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("check"),
             Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1"),
             Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
             Project_Tools.Processes.Argument ("--policy"),
             Project_Tools.Processes.Argument
               (Ada_Quality.Temporary_Directories.Child (Scratch, "missing-policy.toml")),
             Project_Tools.Processes.Argument ("--error-format"),
             Project_Tools.Processes.Argument ("json")]),
         Allow_Two => True, Expected_Text => """kind"":""error""",
         Merge_Standard_Error => True);
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
             Project_Tools.Processes.Argument (Coverage_Policy)]),
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
             Project_Tools.Processes.Argument (Coverage_Policy)]),
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
        ("conflicting output selectors",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("indicator"),
             Project_Tools.Processes.Argument ("list"),
             Project_Tools.Processes.Argument ("--json"),
             Project_Tools.Processes.Argument ("--format"),
             Project_Tools.Processes.Argument ("text")]),
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
            Run_CLI
              ("batch project tag" & Positive'Image (Number),
               Project_Tools.Processes.Arguments
                 ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("tag"),
                   Project_Tools.Processes.Argument
                     (Ada.Strings.Fixed.Trim (Positive'Image (Number), Ada.Strings.Both)),
                   Project_Tools.Processes.Argument ("batch"), Project_Tools.Processes.Argument ("--database"),
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
              ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--tag"),
                Project_Tools.Processes.Argument ("batch"),
                Project_Tools.Processes.Argument ("--jobs"), Project_Tools.Processes.Argument ("2"),
                Project_Tools.Processes.Argument ("--json"),
                Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
                Project_Tools.Processes.Argument ("--policy"),
                Project_Tools.Processes.Argument (Coverage_Policy),
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
      Project_Tools.Files.Write_Text_File
        (Coverage_Policy,
         "coverage_minimum_basis_points = 9000" & ASCII.LF &
         "maximum_source_lines = 1000" & ASCII.LF &
         "maximum_complexity = 15" & ASCII.LF &
         --  Instrumentation and shared CI hosts make staged self-assessments
         --  slower than normal product runs; keep the product default intact.
         "process_timeout_seconds = 1200" & ASCII.LF &
         "maximum_output_bytes = 1048576" & ASCII.LF &
         "require_clean_worktree = false" & ASCII.LF);
      Exercise_Happy_Path;
      Exercise_Error_Paths;
      Exercise_Batch_Continuation;
      Cleanup_Database;
   exception
      when Program_Error =>
         Cleanup_Database;
         raise;
end Exercise_CLI;
