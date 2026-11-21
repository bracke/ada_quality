package body Ada_Quality.Schema_Catalog is
   type String_Access is access constant String;
   Names : constant array (Schema_Index) of String_Access :=
     [new String'("assessment.schema.json"),
      new String'("archive.schema.json"),
      new String'("assessment-batch.schema.json"),
      new String'("assessment-reuse.schema.json"),
      new String'("check-plan.schema.json"),
      new String'("metric-trend.schema.json"),
      new String'("metric-trends.schema.json"),
      new String'("assessment-history.schema.json"),
      new String'("assessment-comparison.schema.json"),
      new String'("portfolio-status.schema.json"),
      new String'("indicator-catalog.schema.json"),
      new String'("changed-source-scan.schema.json"),
      new String'("project-list.schema.json"),
      new String'("project-discovery.schema.json"),
      new String'("assessment-aliases.schema.json"),
      new String'("database-statistics.schema.json"),
      new String'("findings.schema.json"),
      new String'("doctor-report.schema.json"),
      new String'("waiver-audit.schema.json"),
      new String'("retention-preview.schema.json"),
      new String'("database-merge.schema.json"),
      new String'("error.schema.json"),
      new String'("command-result.schema.json"),
      new String'("policy.schema.json"),
      new String'("policy-diff.schema.json"),
      new String'("policy-impact.schema.json"),
      new String'("regressions.schema.json"),
      new String'("artifact-signature.schema.json"),
      new String'("trusted-keys.schema.json")];

   function Name (Index : Schema_Index) return String is (Names (Index).all);
end Ada_Quality.Schema_Catalog;
