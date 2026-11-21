separate (Ada_Quality_Coverage.Exercise_CLI)
procedure Exercise_Happy_Setup is
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
          Project_Tools.Processes.Argument (Coverage_Policy)]));
   Run_CLI
     ("policy show",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("show"),
          Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy)]));
   Run_CLI
     ("policy show JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("show"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Expected_Text => """kind"": ""policy""");
   Run_CLI
     ("policy init",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("init"),
          Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "created ");
   Run_CLI
     ("policy init JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("init"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (JSON_Policy_Base)]),
      Expected_Text => "command-result");
   Run_CLI
     ("policy validate JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("validate"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "command-result");
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
     ("policy profiles JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("profiles"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "policy-profiles");
   Project_Tools.Files.Write_Text_File
     (Policy_Profile,
      "coverage_minimum_basis_points = 8999" & ASCII.LF &
      "maximum_source_lines = 999" & ASCII.LF &
      "maximum_complexity = 16" & ASCII.LF &
      "process_timeout_seconds = 599" & ASCII.LF &
      "maximum_output_bytes = 1048575" & ASCII.LF &
      "require_clean_worktree = true" & ASCII.LF);
   Run_CLI
     ("explain indicator",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("explain"), Project_Tools.Processes.Argument ("SRC-03")]),
      Expected_Text => "remediation:");
   Run_CLI
     ("policy diff",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("diff"),
          Project_Tools.Processes.Argument ("default"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "maximum_complexity");
   Run_CLI
     ("policy diff JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("diff"),
          Project_Tools.Processes.Argument ("default"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "policy-diff");
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
     ("command-specific option rejection",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("list"),
          Project_Tools.Processes.Argument ("--max-failures"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
      Allow_Two => True, Expected_Text => "option is not valid for this command",
      Merge_Standard_Error => True);
   Run_CLI
     ("project list snapshot cursor",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("list"),
          Project_Tools.Processes.Argument ("--cursor"),
          Project_Tools.Processes.Argument ("v2:999999:0"),
          Project_Tools.Processes.Argument ("--limit"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => """snapshot"": 999999");
   Run_CLI
     ("effective project policy",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("effective"),
          Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--profile"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--explain"),
          Project_Tools.Processes.Argument ("--output"), Project_Tools.Processes.Argument (Effective_Output),
          Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]));
   Run_CLI
     ("effective project policy JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("effective"),
          Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--profile"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--json"),
          Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => """kind"": ""policy""");
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
     ("project tag",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("tag"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => "tagged project 1");
   Run_CLI
     ("project tags",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("tags"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]), Expected_Text => "ci");
   Run_CLI
     ("project show JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("project"), Project_Tools.Processes.Argument ("show"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--json"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => "project-list");
   Run_CLI
     ("policy impact JSON",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("impact"),
          Project_Tools.Processes.Argument ("default"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "policy-impact");
   Run_CLI
     ("policy impact text",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("impact"),
          Project_Tools.Processes.Argument ("default"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "project 1");
   Run_CLI
     ("policy impact project filter",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("impact"),
          Project_Tools.Processes.Argument ("default"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "policy-impact");
   Run_CLI
     ("policy impact tag filter",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("policy"), Project_Tools.Processes.Argument ("impact"),
          Project_Tools.Processes.Argument ("default"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--tag"), Project_Tools.Processes.Argument ("ci"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--policy"), Project_Tools.Processes.Argument (Policy_Base)]),
      Expected_Text => "project 1");
   Run_CLI
     ("check dry run",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("check"), Project_Tools.Processes.Argument ("--tag"),
          Project_Tools.Processes.Argument ("ci"), Project_Tools.Processes.Argument ("--dry-run"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Expected_Text => "check-plan");
   Run_CLI
     ("doctor",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("doctor"), Project_Tools.Processes.Argument ("--project"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy),
          Project_Tools.Processes.Argument ("--json")]),
      Allow_Three => True, Expected_Text => "doctor-report");
   Run_CLI
     ("doctor portfolio",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("doctor"), Project_Tools.Processes.Argument ("--all"),
          Project_Tools.Processes.Argument ("--max-failures"), Project_Tools.Processes.Argument ("99"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy),
          Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => """schema_version"": 2");
   Run_CLI
     ("doctor portfolio text",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("doctor"), Project_Tools.Processes.Argument ("--all"),
          Project_Tools.Processes.Argument ("--max-failures"), Project_Tools.Processes.Argument ("99"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Expected_Text => "project 1");
   Run_CLI
     ("waiver audit",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("waiver"), Project_Tools.Processes.Argument ("audit"),
          Project_Tools.Processes.Argument ("--project"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy),
          Project_Tools.Processes.Argument ("--json")]),
      Allow_One => True, Expected_Text => "waiver-audit");
   Run_CLI
     ("waiver portfolio",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("waiver"), Project_Tools.Processes.Argument ("audit"),
          Project_Tools.Processes.Argument ("--all"), Project_Tools.Processes.Argument ("--max-invalid"),
          Project_Tools.Processes.Argument ("99"), Project_Tools.Processes.Argument ("--max-expiring"),
          Project_Tools.Processes.Argument ("99"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy),
          Project_Tools.Processes.Argument ("--json")]),
      Expected_Text => """schema_version"": 2");
   Run_CLI
     ("waiver portfolio text",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("waiver"), Project_Tools.Processes.Argument ("audit"),
          Project_Tools.Processes.Argument ("--all"), Project_Tools.Processes.Argument ("--max-invalid"),
          Project_Tools.Processes.Argument ("99"), Project_Tools.Processes.Argument ("--max-expiring"),
          Project_Tools.Processes.Argument ("99"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path), Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Expected_Text => "project 1");
   Run_CLI
     ("changed source scan",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("scan"), Project_Tools.Processes.Argument ("--project"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--changed-file"),
          Project_Tools.Processes.Argument ("src/ada_quality.ads"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy)]),
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
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Allow_One => True, Expected_Text => "changed source(s)");
   Project_Tools.Files.Write_Text_File
     (Changed_List_Path,
      [1 .. Ada_Quality.Resource_Limits.Maximum_Path_Input_Bytes + 1 => 'x'] & ASCII.LF);
   Run_CLI
     ("oversized changed source list entry",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("scan"), Project_Tools.Processes.Argument ("--project"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--files-from"),
          Project_Tools.Processes.Argument (Changed_List_Path),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path),
          Project_Tools.Processes.Argument ("--policy"),
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Allow_Two => True);
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
             Project_Tools.Processes.Argument (Coverage_Policy)]),
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
          Project_Tools.Processes.Argument (Coverage_Policy)]),
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
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Allow_One => True);
   if not Project_Tools.Files.File_Exists (Scan_Output) or else
     Ada.Strings.Fixed.Index
       (Ada_Quality.Bounded_Files.Read
          (Scan_Output, Ada_Quality.Resource_Limits.Maximum_File_Bytes),
        "changed-source-scan") = 0
   then
      raise Program_Error with "Git working tree scan output was not created";
   end if;
end Exercise_Happy_Setup;
