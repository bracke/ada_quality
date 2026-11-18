# CLI reference

Commands are `project add/list/show/enable/disable/remove`, `check --all|--project ID [--json]`,
`assessment show RUN_ID [--format text|json|sarif|junit]`, `status`, `findings`,
`regressions [--project ID] [--current RUN_ID]`, `history`,
`trend --project ID --indicator ID [--json]`, `report --format json`, `policy validate/show`, and
`database init/check/recover`. During
`check --all`, a project-local source or assessment exception interrupts that project's run, contributes exit class 3,
and does not prevent later enabled projects from running. Database start, publication, interruption, and integrity
failures remain batch-fatal. `regressions` reports one of three distinct outcomes per project: concrete regressions,
no regressions in comparable completed assessments, or comparison unavailable with the reason. `check --project ID
--json` emits the assessment-v1 object. `check --all --json` emits one assessment-batch-v1 document whose ordered
outcomes include both completed assessments and project-local interruptions. Global options are
`--database`, `--policy`, `--color`, and `--no-color`. Unknown options, missing values, and conflicting selectors are
rejected.

Selected-assessment JSON reuses assessment-v1. SARIF exports findings with stable fingerprints and physical source
locations. JUnit represents every indicator as a test case, distinguishing violations, unavailable evidence, and
not-applicability. Selected comparisons ignore runs later than `--current`. Trend JSON is metric-trend-v1 and contains
the project, indicator, measurement unit, and compatible run/value points in ascending run order.
