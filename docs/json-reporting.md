# JSON reporting

`check --project ID --json` emits one versioned assessment object. `check --all --json` emits one versioned batch
object with an ordered outcome for every selected project, including interrupted assessments and their diagnostics;
it never concatenates top-level JSON values. `report --format json` emits the v2 persistent archive, including removed
projects, one explicit comparison-selection status per project, and derived regression events. All formats use
jsonlib, sorted members, UTF-8 strings, and no terminal markers or ANSI sequences. Archive measurement entries expose
their value kind separately from the persisted versioned semantics string.

`assessment show RUN_ID --format json` renders the same assessment-v1 object from validated immutable evidence.
`trend --project ID --indicator ID --json` emits metric-trend-v1 with compatible points in run-ID order. CI-native
exports are available from `assessment show`: SARIF 2.1.0 for findings and JUnit XML for all indicator outcomes.
