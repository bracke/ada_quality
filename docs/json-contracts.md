# JSON contracts

Assessment, multi-project batch, archive, comparison, filtered-history, and metric-trend JSON are schema-versioned, deterministically member-sorted, UTF-8
preserving, and free of ANSI styling. A single assessment exports all 33 results, typed measurements, findings, and
tool executions. A batch exports every completed, reused, or interrupted project outcome in one document. A single
unchanged JSON check emits `assessment-reuse-v1`. Archive v2 exports
projects, assessments/history, results, measurements, findings, executions, events, comparison availability, and
derived regressions. A selected comparison records its exact baseline/current identities and classified changes. A
filtered history exports validated run metadata. Metric trends export one or every trend-enabled compatible numeric
series for a project. Archive project/time filters retain only selected assessment evidence and emit comparisons only
when every referenced assessment is present. Changed-source scans and the project list/discovery, alias-list, and
database-statistics administration commands also have deterministic versioned JSON forms.
Policy show/diff/impact, regression collections, command results, artifact signatures, and trusted-key inventories
also have dedicated contracts. `--error-format json` emits one stable error document on standard error. Its `code`
distinguishes `usage_error`, `execution_error`, `database_error`, `reporting_error`, and `signing_error`; artifact
key, signature, and trust failures therefore do not masquerade as database failures.
No-write JSON checks emit `check-plan-v1`, including source, policy, and toolchain identities and any reusable run.
Schemas are `assessment.schema.json`, `assessment-batch.schema.json`, `assessment-reuse.schema.json`,
`check-plan.schema.json`, `archive.schema.json`,
`metric-trend.schema.json`, `metric-trends.schema.json`, `assessment-history.schema.json`, and
`assessment-comparison.schema.json`. `portfolio-status.schema.json` and `indicator-catalog.schema.json` define the
latest-project summary and registry-discovery surfaces. SARIF uses the external SARIF 2.1.0 contract; JUnit is emitted
as XML rather than JSON. The additional contracts are `changed-source-scan.schema.json`, `project-list.schema.json`,
`project-discovery.schema.json`, `assessment-aliases.schema.json`, and `database-statistics.schema.json`.
Filtered finding collections use `findings.schema.json`; SARIF remains available for the same selected records.
Paged contracts include a snapshot identity; v2 cursors bind single-identity collections, v3 cursors add a project
boundary or revision, and v4 cursors bind project state plus project and assessment boundaries. Current v5 cursors
also carry a command-and-filter fingerprint and are rejected when reused with a different collection or query. A v4
or v5 continuation fails explicitly if mutable project metadata changed, preventing silent skips or duplicates.
Legacy v1 through v4 cursors remain accepted for compatibility.
Doctor and waiver v2 documents group results by project.
