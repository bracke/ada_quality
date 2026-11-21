# JSON schemas

`assessment.schema.json` constrains a single report's identity, fingerprints, terminal state, exactly 33 results,
measurements, findings, and executions. `assessment-batch.schema.json` defines the single-document result of
`check --all --json`, including completed, reused, and interrupted project outcomes.
`assessment-reuse.schema.json` defines a single project's compact exact-reuse reference. Archive v2 requires all persisted logical
collections, an explicit typed comparison-selection result for every project, and derived regressions with
project/baseline/current IDs. Archive executions expose typed command, status, exit, digest, retained-size, and
truncation members rather than the private persistence payload. The schemas declare JSON Schema draft 2020-12 and
reject unknown top-level members.
`check-plan.schema.json` defines the project fingerprints, reuse eligibility, and selected action emitted by
`check --dry-run --json`.

`metric-trend.schema.json` constrains one project's compatible numeric points for one canonical indicator and records
the registry measurement unit. `metric-trends.schema.json` applies the same point contract to an ordered collection
of trend-enabled indicators. `assessment-history.schema.json` defines filtered validated run metadata, while
`assessment-comparison.schema.json` defines exact selected IDs, availability, and classified regressions.
`portfolio-status.schema.json` defines the latest project/assessment/comparison summary, and
`indicator-catalog.schema.json` defines registry discovery output. SARIF and JUnit use their standard external
contracts instead of project-local schemas. Changed-source scans, project list/discovery, assessment aliases, and
database statistics are constrained by their correspondingly named v1 schema files.
`findings.schema.json` constrains structured finding queries independently of a complete assessment.
Administrative schemas additionally cover errors, command results, policies, policy diffs and impact, regression
sets, signature metadata, trusted keys, batch doctor/waiver reports, and multi-source merge results. Paged schemas
require snapshot metadata and accept legacy v1, snapshot-bound v2, project-revision v3,
assessment/project/revision-bound v4, and query-bound v5 cursor syntax. Doctor and waiver contracts expose observed counts, configured
thresholds, and the exact threshold decision represented by the command exit status.
