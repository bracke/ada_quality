separate (Ada_Quality_Coverage.Exercise_CLI)
procedure Exercise_Happy_Reports is
begin
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
          Project_Tools.Processes.Argument ("json"), Project_Tools.Processes.Argument ("--tag"),
          Project_Tools.Processes.Argument ("ci"), Project_Tools.Processes.Argument ("--database"),
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
   Run_CLI
     ("portfolio status snapshot cursor",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--cursor"),
          Project_Tools.Processes.Argument ("v3:999999:999999:0"),
          Project_Tools.Processes.Argument ("--limit"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => """snapshot"": 999999");
   Run_CLI
     ("portfolio status rejects foreign current cursor",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("status"), Project_Tools.Processes.Argument ("--cursor"),
          Project_Tools.Processes.Argument ("v5:1:999999:999999:1:0"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]),
      Allow_Two => True, Expected_Text => "cursor does not belong to this command and filter set",
      Merge_Standard_Error => True);
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
     ("invalid completion shell",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("completion"),
          Project_Tools.Processes.Argument ("invalid")]),
      Allow_Two => True,
      Expected_Text => "unknown completion subcommand: invalid",
      Merge_Standard_Error => True);
   Run_CLI
     ("database signing key generation",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("keygen"),
          Project_Tools.Processes.Argument (Private_Key_Path),
          Project_Tools.Processes.Argument (Public_Key_Path)]),
      Expected_Text => "generated Ed25519 keypair");
   Run_CLI
     ("database signing key generation JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("keygen"),
          Project_Tools.Processes.Argument (Auxiliary_Private_Key_Path),
          Project_Tools.Processes.Argument (Auxiliary_Public_Key_Path),
          Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => "command-result");
   Run_CLI
     ("database backup",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("backup"),
          Project_Tools.Processes.Argument (Backup_Path), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--sign-key"),
          Project_Tools.Processes.Argument (Private_Key_Path)]),
      Expected_Text => "backup created");
   Run_CLI
     ("database export",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("export"),
          Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--sign-key"),
          Project_Tools.Processes.Argument (Private_Key_Path)]),
      Expected_Text => "export created");
   Run_CLI
     ("database signature inspection",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("inspect"),
          Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => "artifact-signature");
   Run_CLI
     ("database signature inspection text",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("inspect"),
          Project_Tools.Processes.Argument (Export_Path)]),
      Expected_Text => "key_id=ed25519-");
   Run_CLI
     ("database trust add",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("trust"),
          Project_Tools.Processes.Argument ("add"), Project_Tools.Processes.Argument (Public_Key_Path),
          Project_Tools.Processes.Argument ("--trust-store"), Project_Tools.Processes.Argument (Trust_Store)]),
      Expected_Text => "trusted ed25519-");
   Run_CLI
     ("database trust list",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("trust"),
          Project_Tools.Processes.Argument ("list"), Project_Tools.Processes.Argument ("--trust-store"),
          Project_Tools.Processes.Argument (Trust_Store), Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => "trusted-keys");
   Run_CLI
     ("database trust list text",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("trust"),
          Project_Tools.Processes.Argument ("list"), Project_Tools.Processes.Argument ("--trust-store"),
          Project_Tools.Processes.Argument (Trust_Store)]),
      Expected_Text => "ed25519-");
   declare
      Trusted_Key_Id : constant String :=
        Ada_Quality.Artifact_Signing.Key_Id (Public_Key_Path);
   begin
      Run_CLI
        ("database trust remove JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("trust"),
             Project_Tools.Processes.Argument ("remove"),
             Project_Tools.Processes.Argument (Trusted_Key_Id),
             Project_Tools.Processes.Argument ("--trust-store"),
             Project_Tools.Processes.Argument (Trust_Store),
             Project_Tools.Processes.Argument ("--json")]),
         Expected_Text => "command-result");
      Run_CLI
        ("database trust add JSON",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("trust"),
             Project_Tools.Processes.Argument ("add"), Project_Tools.Processes.Argument (Public_Key_Path),
             Project_Tools.Processes.Argument ("--trust-store"),
             Project_Tools.Processes.Argument (Trust_Store),
             Project_Tools.Processes.Argument ("--json")]),
         Expected_Text => "command-result");
   end;
   Run_CLI
     ("database trusted verification",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("verify"),
          Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument ("--trust-store"),
          Project_Tools.Processes.Argument (Trust_Store), Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => """verified"": true");
   Run_CLI
     ("database trusted verification text",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("verify"),
          Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument ("--trust-store"),
          Project_Tools.Processes.Argument (Trust_Store)]),
      Expected_Text => "artifact signature verified");
   for Artifact of Project_Tools.Processes.Argument_Items'
     ([Project_Tools.Processes.Argument (Backup_Path), Project_Tools.Processes.Argument (Export_Path)])
   loop
      Run_CLI
        ("database signature verification",
         Project_Tools.Processes.Arguments
           ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("verify"),
             Artifact, Project_Tools.Processes.Argument ("--public-key"),
             Project_Tools.Processes.Argument (Public_Key_Path)]),
         Expected_Text => "artifact signature verified");
   end loop;
   Run_CLI
     ("database retention preview",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("archive"),
          Project_Tools.Processes.Argument ("--dry-run"), Project_Tools.Processes.Argument ("--before"),
          Project_Tools.Processes.Argument ("2000-01-01T00:00:00Z"),
          Project_Tools.Processes.Argument ("--keep"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => "retention-preview");
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
     ("database restore rejects irrelevant options",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("restore"),
          Project_Tools.Processes.Argument (Backup_Path), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (Restored_Path), Project_Tools.Processes.Argument ("--dry-run")]),
      Allow_Two => True, Expected_Text => "option is not valid for this command",
      Merge_Standard_Error => True);
   Run_CLI
     ("database restore",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("restore"),
          Project_Tools.Processes.Argument (Backup_Path), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (Restored_Path), Project_Tools.Processes.Argument ("--public-key"),
          Project_Tools.Processes.Argument (Public_Key_Path)]),
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
          Project_Tools.Processes.Argument (Imported_Path), Project_Tools.Processes.Argument ("--public-key"),
          Project_Tools.Processes.Argument (Public_Key_Path)]),
      Expected_Text => "imported ");
   Run_CLI
     ("imported database check",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("check"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (Imported_Path)]),
      Expected_Text => "integrity check passed");
   Run_CLI
     ("database merge",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("init"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (Merge_Path)]),
      Expected_Text => "initialized");
   Run_CLI
     ("database merge preview",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("merge"),
          Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument (Export_Path),
          Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (Merge_Path), Project_Tools.Processes.Argument ("--dry-run"),
          Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => "database-merge");
   Run_CLI
     ("database merge export",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("database"), Project_Tools.Processes.Argument ("merge"),
          Project_Tools.Processes.Argument (Export_Path), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (Merge_Path)]),
      Expected_Text => "merged");
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
        Project_Tools.Processes.Capture_Command
          (Binary ("check_all"),
           Project_Tools.Processes.No_Arguments,
           Err_To_Out => True);
      Coverage_Is_Stale : constant Boolean :=
        Project_Tools.Files.Value_Of (Summary_Path, "source_fingerprint") /=
          To_String (Current_Source_Fingerprint);
      Stale_Diagnostic : constant Boolean :=
        Ada.Strings.Fixed.Index
          (To_String (Release_Run.Output), "coverage evidence is stale:") > 0;
   begin
      --  The release checker normally reserves exit 2 for stale coverage.
      --  Some instrumented runtimes report the handled exception as exit 1,
      --  so accept that value only when both independent stale-evidence
      --  checks also agree while this driver is generating the replacement.
      if Release_Run.Status /= 0 and then
        (Release_Run.Status not in 1 | 2 or else
         not Coverage_Is_Stale or else not Stale_Diagnostic)
      then
         raise Program_Error with
           "instrumented release checker failed with status" &
           Integer'Image (Release_Run.Status) & ASCII.LF &
           To_String (Release_Run.Output);
      end if;
   end;
   Run_CLI
     ("project remove",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("remove"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]));
end Exercise_Happy_Reports;
