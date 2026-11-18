# JSON contracts

Assessment, multi-project batch, archive, comparison, filtered-history, and metric-trend JSON are schema-versioned, deterministically member-sorted, UTF-8
preserving, and free of ANSI styling. A single assessment exports all 33 results, typed measurements, findings, and
tool executions. A batch exports every completed or interrupted project outcome in one document. Archive v2 exports
projects, assessments/history, results, measurements, findings, executions, events, comparison availability, and
derived regressions. A selected comparison records its exact baseline/current identities and classified changes. A
filtered history exports validated run metadata. Metric trends export one or every trend-enabled compatible numeric
series for a project.
Schemas are `assessment.schema.json`, `assessment-batch.schema.json`, `archive.schema.json`, and
`metric-trend.schema.json`, `metric-trends.schema.json`, `assessment-history.schema.json`, and
`assessment-comparison.schema.json`. SARIF uses the external SARIF 2.1.0 contract; JUnit is emitted as XML rather than JSON.
