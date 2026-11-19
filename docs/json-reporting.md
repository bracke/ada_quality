# JSON reporting

`check --project ID --json` emits one versioned assessment object. `check --all --json` emits one versioned batch
object with an ordered outcome for every selected project, including interrupted assessments and their diagnostics;
it never concatenates top-level JSON values. `report --format json` emits the v2 persistent archive, including removed
projects, one explicit comparison-selection status per project, and derived regression events. Project and inclusive
start-time filters emit only selected runs and their children; comparisons require both referenced runs. All formats use
jsonlib, sorted members, UTF-8 strings, and no terminal markers or ANSI sequences. Archive measurement entries expose
their value kind separately from the persisted versioned semantics string.

`assessment show RUN_ID --format json` renders the same assessment-v1 object from validated immutable evidence.
`trend --project ID --indicator ID --json` emits metric-trend-v1 with compatible points in run-ID order. CI-native
exports are available from `assessment show`: SARIF 2.1.0 for findings and JUnit XML for all indicator outcomes.
`assessment diff BASELINE CURRENT --format json` emits assessment-comparison-v1 without replacing either selected
run. Filtered `history --json` emits assessment-history-v1. `trend --all --format json` emits metric-trends-v1;
the CSV form uses a fixed five-column header and registry/run ordering.

`status --json` emits portfolio-status-v1 with one latest-state entry per active project. `indicator list --format
json` emits indicator-catalog-v1 and may be category-filtered. Both are deterministically member-sorted and contain no
terminal styling.

Changed-source scan, project list/discovery, assessment aliases, and database statistics also emit deterministic,
versioned JSON under their named v1 schemas. Scan findings can alternatively be emitted as SARIF 2.1.0.
