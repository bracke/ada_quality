separate (Ada_Quality_Coverage.Exercise_CLI)
procedure Exercise_Happy_Assessments is
begin
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
          Project_Tools.Processes.Argument (Coverage_Policy)]),
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
          Project_Tools.Processes.Argument (Coverage_Policy)]),
      Allow_Three => True);
   if not Project_Tools.Files.File_Exists (Reuse_Output) or else
     Ada.Strings.Fixed.Index
       (Ada_Quality.Bounded_Files.Read
          (Reuse_Output, Ada_Quality.Resource_Limits.Maximum_File_Bytes),
        "assessment-reuse") = 0
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
     ("assessment alias snapshot cursor",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("assessment"), Project_Tools.Processes.Argument ("aliases"),
          Project_Tools.Processes.Argument ("--cursor"),
          Project_Tools.Processes.Argument ("v2:999999:0"),
          Project_Tools.Processes.Argument ("--limit"), Project_Tools.Processes.Argument ("1"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => """snapshot"": 999999");
   Run_CLI
     ("regressions with compatible baseline",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("regressions"),
          Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => "no regressions in comparable assessments",
      Expected_Alternate => "failed-gate");
   Run_CLI
     ("clean regression gate",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("regressions"),
          Project_Tools.Processes.Argument ("--baseline"), Project_Tools.Processes.Argument ("release-1"),
          Project_Tools.Processes.Argument ("--current"), Project_Tools.Processes.Argument ("release-2"),
          Project_Tools.Processes.Argument ("--fail-on-regression"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
      Allow_Three => True,
      Expected_Text => "no regressions in comparable assessments",
      Expected_Alternate => "failed-gate");
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
        ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--tag"),
          Project_Tools.Processes.Argument ("ci"), Project_Tools.Processes.Argument ("--status"),
          Project_Tools.Processes.Argument ("completed"), Project_Tools.Processes.Argument ("--limit"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--since"),
          Project_Tools.Processes.Argument ("2000-01-01T00:00:00Z"),
          Project_Tools.Processes.Argument ("--until"),
          Project_Tools.Processes.Argument ("2099-12-31T23:59:59Z"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => "v5:");
   Run_CLI
     ("history cursor page",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--tag"),
          Project_Tools.Processes.Argument ("ci"), Project_Tools.Processes.Argument ("--limit"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--cursor"),
          Project_Tools.Processes.Argument ("v1:1"), Project_Tools.Processes.Argument ("--json"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => """offset"": 1");
   Run_CLI
     ("history snapshot cursor page",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--tag"),
          Project_Tools.Processes.Argument ("ci"), Project_Tools.Processes.Argument ("--limit"),
          Project_Tools.Processes.Argument ("1"), Project_Tools.Processes.Argument ("--cursor"),
          Project_Tools.Processes.Argument ("v2:999999:1"), Project_Tools.Processes.Argument ("--json"),
          Project_Tools.Processes.Argument ("--database"), Project_Tools.Processes.Argument (DB_Path)]),
      Expected_Text => """snapshot"": 999999");
   Run_CLI
     ("stale project revision cursor",
      Project_Tools.Processes.Arguments
        ([Project_Tools.Processes.Argument ("history"), Project_Tools.Processes.Argument ("--cursor"),
          Project_Tools.Processes.Argument ("v4:999999:999999:1:0"),
          Project_Tools.Processes.Argument ("--json"), Project_Tools.Processes.Argument ("--database"),
          Project_Tools.Processes.Argument (DB_Path)]),
      Allow_Two => True);
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
end Exercise_Happy_Assessments;
