# Ada Quality — System Specification v1.0

## Architecture
Standalone Ada 2022 Alire CLI. Components: CLI, project registry, assessment controller, static indicator registry, native/external measurement adapters, pure policy evaluator, typed database persistence, history/comparison, structured JSON reporting. Exactly one project assessed at a time. No visualization, GitHub discovery, dynamic plugins, distributed workers, QMR/qmrlib/qaelib, or automatic remediation.

## Standard libraries
Use existing `database` (typed rows, tables, transactions, persistent locking), `project_tools` (Alire manifests, Ada source, AUnit, coverage, process and release helpers), `messages`, `regexp`, `terminal_styles`, `jsonlib`. Verify actual APIs before coding. GNAT 15 through Alire, AUnit child crate, GNATdoc, 120-character source lines.

## Policy and results
One TOML policy for every project, no project overrides. Coverage >=90% of complete eligible executable production lines; GNATprove required for declared SPARK units; release checker executed every full assessment. All 33 indicators represented. Execution status distinct from compliance and completeness. Missing/blocked/error evidence never passes. Not-applicable requires evidence.

## Assessment lifecycle
Read enabled project IDs from database in stable order; validate Alire root; capture source identity including tracked modifications and relevant untracked files; create running record; execute prerequisite-ordered checks; collect typed measurements, findings, tool versions, bounded evidence; recheck source fingerprint; atomically publish completed results or mark invalid/interrupted; compare compatible historical baseline; proceed to next project. No DB write transaction during external tools. Stop on system-wide storage failures.

## Database
Eight logical tables: Projects, Assessment_Runs, Indicator_Results, Measurements, Findings, Tool_Executions, Assessment_Events, Schema_Metadata. Explicit typed Ada row mappings and transaction boundaries; no SQL or second database. Completed results immutable; migrations explicit; process-level persistent lock conflict handled. Recovery idempotently marks abandoned running assessments interrupted.

## Findings and history
Stable finding fingerprint uses indicator/rule and semantic relative source context, not only line number. Classify new, persistent, resolved, reintroduced, unconfirmed. Resolution only after successful comparable remeasurement. Regression types include new violations, worsened metric, increased severity, failed gate, lost evidence, policy-induced change. Preserve policy/tool/source semantics in baseline compatibility.

## CLI
`project add/list/show/enable/disable/remove`, `check --all|--project`, `status`, `findings`, `regressions`, `history`, `report --format json`, `policy validate/show`, `database init/check/recover`. Exit 0 success, 1 quality violations, 2 argument/config errors, 3 incomplete/tool errors, 4 database/integrity errors. JSON versioned, deterministic, Unicode-safe, no ANSI; human output uses messages/terminal_styles.

## Safety and tests
Explicit argv, no shell interpolation, bounded stdout/stderr, enforced timeouts/cancellation, process cleanup, safe symlinks/staging, no tracked source modifications, secret redaction. AUnit positive/negative/boundary fixtures, real Alire/GNAT/AUnit/GNATprove/GNATdoc integration, persistent DB fault injection, process-level CLI E2E, schema validation and project_tools release checks. Record actual commands and outcomes.
