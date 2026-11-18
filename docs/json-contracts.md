# JSON contracts

Assessment, multi-project batch, archive, and metric-trend JSON are schema-versioned, deterministically member-sorted, UTF-8
preserving, and free of ANSI styling. A single assessment exports all 33 results, typed measurements, findings, and
tool executions. A batch exports every completed or interrupted project outcome in one document. Archive v2 exports
projects, assessments/history, results, measurements, findings, executions, events, comparison availability, and
derived regressions. A metric trend exports compatible numeric run/value points for one project and indicator.
Schemas are `assessment.schema.json`, `assessment-batch.schema.json`, `archive.schema.json`, and
`metric-trend.schema.json`. SARIF uses the external SARIF 2.1.0 contract; JUnit is emitted as XML rather than JSON.
