# JSON schemas

`assessment.schema.json` constrains a single report's identity, fingerprints, terminal state, exactly 33 results,
measurements, findings, and executions. `assessment-batch.schema.json` defines the single-document result of
`check --all --json`, including completed and interrupted project outcomes. Archive v2 requires all persisted logical
collections, an explicit typed comparison-selection result for every project, and derived regressions with
project/baseline/current IDs. Archive executions expose typed command, status, exit, digest, retained-size, and
truncation members rather than the private persistence payload. The schemas declare JSON Schema draft 2020-12 and
reject unknown top-level members.

`metric-trend.schema.json` constrains one project's compatible numeric points for one canonical indicator and records
the registry measurement unit. SARIF and JUnit use their standard external contracts instead of project-local schemas.
