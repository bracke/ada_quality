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
Schemas are `assessment.schema.json`, `assessment-batch.schema.json`, `assessment-reuse.schema.json`, `archive.schema.json`,
`metric-trend.schema.json`, `metric-trends.schema.json`, `assessment-history.schema.json`, and
`assessment-comparison.schema.json`. `portfolio-status.schema.json` and `indicator-catalog.schema.json` define the
latest-project summary and registry-discovery surfaces. SARIF uses the external SARIF 2.1.0 contract; JUnit is emitted
as XML rather than JSON. The additional contracts are `changed-source-scan.schema.json`, `project-list.schema.json`,
`project-discovery.schema.json`, `assessment-aliases.schema.json`, and `database-statistics.schema.json`.
Filtered finding collections use `findings.schema.json`; SARIF remains available for the same selected records.
