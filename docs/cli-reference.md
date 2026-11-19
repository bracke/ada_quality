# CLI reference

Commands are `project add/discover/list/show/enable/disable/remove/relocate/tag/untag/tags`,
`check (--all|--project ID|--tag NAME) [--dry-run] [--json]`,
`scan --project ID (--changed-file PATH|--files-from FILE|-) [--format text|json|sarif]`,
`assessment show RUN_REF [--format text|json|sarif|junit]`,
`assessment diff BASELINE_REF CURRENT_REF [--format text|json]`,
`assessment alias NAME RUN_ID`, `assessment aliases [RUN_REF] [--json]`,
`status [--tag NAME] [--only unhealthy|stale|regressed] [--since TIME] [--json]`, `findings [--tag NAME]`,
`regressions [--project ID|--tag NAME] [--current RUN_REF] [--baseline RUN_REF] [--fail-on-regression]`,
`history [--project ID] [--tag NAME] [--status STATE] [--limit N] [--cursor TOKEN] [--json]`,
`trend --project ID (--indicator ID|--all) [--from-run ID] [--to-run ID] [--since TIME] [--until TIME]
[--format text|json|csv]`, `explain INDICATOR_ID`, `indicator list [--category CATEGORY] [--format text|json]`,
`report --format json [--project ID] [--since TIME] [--until TIME]`, `completion bash|zsh|fish`,
`doctor`, `waiver audit`, `policy init/validate/show/profiles/effective/diff`, and
`database init/check/recover/compact/stats/backup/export/import/restore/archive/merge/keygen/verify`. During
`check --all`, a project-local source or assessment exception interrupts that project's run, contributes exit class 3,
and does not prevent later enabled projects from running. Database start, publication, interruption, and integrity
failures remain batch-fatal. `regressions` reports one of three distinct outcomes per project: concrete regressions,
no regressions in comparable completed assessments, or comparison unavailable with the reason. `check --project ID
--json` emits the assessment-v1 object. `check --all --json` emits one assessment-batch-v1 document whose ordered
outcomes include both completed assessments and project-local interruptions. Global options are
`--database`, `--policy`, `--color`, and `--no-color`. Unknown options, missing values, and conflicting selectors are
rejected.

Read commands accept `--output`; collection views accept `--limit`, `--offset`, and `--cursor`, with total and
next-cursor JSON metadata. A dry-run check emits resolved fingerprints, reuse eligibility, and the selected action
without writing the database. Tags select checks and every portfolio query surface. Doctor, waiver inventory,
retention previews, and merge plans/results have versioned JSON. Merge preflights conflicts and commits every added
row atomically. Effective-policy explanation identifies per-key sources; policy diff reports changed values.

Selected-assessment JSON reuses assessment-v1. SARIF exports findings with stable fingerprints and physical source
locations. JUnit represents every indicator as a test case, distinguishing violations, unavailable evidence, and
not-applicability. Selected comparisons ignore runs later than `--current`. Trend JSON is metric-trend-v1 and contains
the project, indicator, measurement unit, and compatible run/value points in ascending run order.
Explicit comparisons retain both selected IDs and use assessment-comparison-v1 for JSON. History filters use inclusive
start timestamps and retain the most recent `--limit` matches in ascending order. Multi-metric JSON uses
metric-trends-v1; CSV has one deterministic row per point.
Changed-source scans apply the native source rules without traversing unrelated
files. Relocation keeps project identity and history. Database backup and
restore use verified physical artifacts; export uses the database-native
logical format and does not emit SQL. Backup and export can create Ed25519
signatures; verify, restore, and import validate them against an explicitly
selected public key.

Status is a latest-per-project portfolio snapshot with a portfolio-status-v1 JSON form. The optional regression gate
maps clean/regressed/unavailable comparison results to exits 0/1/3. Changed-file lists accept one project-relative
path per line or standard input. Indicator catalog JSON uses indicator-catalog-v1. Local discovery is bounded by the
same entry/depth limits as source traversal and skips generated directories and links. Completed assessments accept
globally unique append-only aliases, which resolve in show/diff/regression commands without changing evidence.
Database statistics expose snapshot row and text consumption against the configured reporting limits. Administration
and scan commands expose versioned JSON, scan also exposes SARIF, filtered archives remain referentially
self-contained, trend bounds accept aliases, and transactional compaction is integrity-checked before and after.
