# CLI reference

```
ada-quality project add PATH
ada-quality project discover ROOT [--add] [--format text|json]
ada-quality project sync ROOT [--remove-missing] [--format text|json]
ada-quality project list [--format text|json]
ada-quality project show ID
ada-quality project enable|disable|remove ID
ada-quality project relocate ID PATH
ada-quality check --all | --project ID [--jobs N] [--reuse-unchanged]
                  [--profile NAME] [--project-policy] [--json]
ada-quality scan --project ID --changed-file PATH [--changed-file PATH ...] [--format text|json|sarif]
ada-quality scan --project ID --files-from FILE|- [--format text|json|sarif]
ada-quality scan --project ID --git-diff BASE [--format text|json|sarif]
ada-quality assessment show RUN_REF [--format text|json|sarif|junit|html] [--output FILE]
ada-quality assessment diff BASELINE_REF CURRENT_REF [--format text|json]
ada-quality assessment alias NAME RUN_ID
ada-quality assessment aliases [RUN_REF] [--format text|json]
ada-quality status [--only unhealthy|stale|regressed] [--since TIME] [--json]
ada-quality findings [--project ID] [--indicator ID] [--severity LEVEL] [--path TEXT]
                     [--since TIME] [--until TIME] [--format text|json|sarif]
ada-quality regressions [--project ID] [--current RUN_REF] [--fail-on-regression]
ada-quality regressions --baseline RUN_REF --current RUN_REF [--fail-on-regression]
ada-quality history [--project ID] [--status STATE] [--limit N]
                    [--since YYYY-MM-DDTHH:MM:SSZ] [--until YYYY-MM-DDTHH:MM:SSZ] [--json]
ada-quality trend --project ID (--indicator TST-03 | --all)
                  [--from-run RUN_REF] [--to-run RUN_REF]
                  [--since YYYY-MM-DDTHH:MM:SSZ] [--until YYYY-MM-DDTHH:MM:SSZ]
                  [--format text|json|csv]
ada-quality explain INDICATOR_ID
ada-quality indicator list [--category CATEGORY] [--format text|json]
ada-quality report --format json|html [--project ID] [--since TIME] [--until TIME] [--output FILE]
ada-quality policy validate|show
ada-quality database init|check|recover|compact
ada-quality database stats [--format text|json]
ada-quality database backup|export DESTINATION
ada-quality database import SOURCE --database DESTINATION
ada-quality database restore SOURCE --database DESTINATION
ada-quality completion bash|zsh|fish
```

Global options are `--database PATH`, `--policy PATH`, `--no-color`, and `--color never`. Environment variables
`ADA_QUALITY_DATABASE` and `ADA_QUALITY_POLICY` provide defaults. JSON never contains ANSI styling.

`assessment show` reads one completed immutable assessment. Text prints the 33 indicator outcomes, JSON uses the
assessment-v1 contract, SARIF 2.1.0 exports structured findings with their stable fingerprints and source locations,
and JUnit maps each indicator to a test case: violations are failures, unavailable evidence is an error, and
not-applicable indicators are skipped. `regressions --current` compares the selected assessment with its newest
compatible predecessor while ignoring later runs. `trend` emits the compatible numeric series for one canonical
indicator ID; `--json` uses the metric-trend-v1 contract.

`assessment diff` compares exactly the two selected assessments; it never substitutes an automatic baseline.
The baseline must precede the current assessment and both must belong to the same project. Its JSON output uses the
assessment-comparison-v1 contract. The equivalent text comparison is available through
`regressions --baseline ID --current ID`.

`history` filters validated runs by project, lifecycle state, inclusive start-time bounds, and a most-recent result
limit. Filtered results remain in ascending assessment-ID order. `--json` emits assessment-history-v1.

`trend --all` exports every registry metric with a defined regression direction. Run-ID and finished-time bounds are
inclusive. Single-indicator JSON remains metric-trend-v1; `--all --format json` emits metric-trends-v1. CSV uses the
stable columns `project_id,indicator,unit,run_id,value` and emits one header even when the selected range is empty.

`scan` runs native source checks only for the named project-relative Ada files,
which makes it suitable for a changed-file preflight hook. `--files-from` reads one path per line; `-` reads standard
input, avoiding shell argument-length limits. `project discover ROOT` recursively reports Alire crates while skipping
generated directories and links; `--add` registers new discoveries. `project relocate`
revalidates a new crate root while preserving the project ID and assessment
history. `explain` prints registry metadata, prerequisites, and remediation. `indicator list` exposes the discoverable
registry, optionally filtered by category; JSON uses indicator-catalog-v1.

Scan JSON uses changed-source-scan-v1; SARIF uses the same finding contract as full assessments. Project list,
discovery, alias listing, and database statistics have versioned JSON forms. Filtered archive reports retain only
selected assessment evidence and omit comparisons unless every referenced run is selected. Trend run bounds accept
numeric IDs or aliases. `status --only stale` requires `--since` and selects projects with no newer timestamp.

`status` is a latest-per-project portfolio view rather than a history alias. It reports enabled state, the newest run,
comparison availability, and regression count; JSON uses portfolio-status-v1. `regressions --fail-on-regression`
turns comparison into a CI gate: exit 0 is comparable and clean, exit 1 means regressions, and exit 3 means comparison
is unavailable. In a multi-project gate, unavailable evidence takes precedence over regressions.

`assessment alias NAME RUN_ID` adds a globally unique append-only name to a completed assessment. Names begin with a
lowercase letter and contain at most 64 lowercase letters, digits, dots, underscores, or hyphens. Numeric IDs and
aliases are accepted by all run selectors, including trend bounds. Aliases never rewrite the
immutable assessment evidence.

`database backup` creates a verified physical backup directory, `export`
creates a verified database-native logical export, and `restore` creates a new
database from a physical backup. Existing destinations are not overwritten. `database stats` reports per-table row
counts plus total row and UTF-8 text consumption against the reporting snapshot limits. `database compact` performs
an integrity check before and after transactional vacuuming. `completion` prints a definition for the named shell;
the roff manual is installed from `docs/ada-quality.1`.

`check --jobs N` runs up to 64 project assessments concurrently while database publication and batch output remain
ordered. `--reuse-unchanged` skips execution only when source, effective-policy, and live-toolchain fingerprints
exactly match a completed assessment. JSON emits a reuse document for one project or a reused batch outcome for
`--all`. `--profile NAME` selects
`quality-policy.NAME.toml`. With `--project-policy`, project-local `quality-policy.override.toml` files partially
overlay the selected base policy.

`project sync` adds discovered crates and reports registered paths under the selected root that are no longer found;
`--remove-missing` tombstones them. `scan --git-diff BASE` uses Git's ACMR name-only diff without a shell;
`--staged`, `--unstaged`, and `--untracked` may be combined and deduplicate Ada paths. Findings
can be filtered by project, indicator, minimum severity, path substring, and inclusive run time, then emitted as
text, findings-v1 JSON, or SARIF. HTML assessment and portfolio reports are self-contained and may be streamed or
written with `--output`. Logical import creates and validates a new database from a native export.

Findings, scans, trends, and assessment diffs accept `--output FILE`. `policy init [--profile NAME]` creates a
complete policy without overwriting, `policy profiles` lists sibling profiles, and `policy effective --project ID
[--profile NAME]` renders the resolved policy. `database archive DEST --before TIME [--keep N]` verifies a full
logical archive before pruning old terminal assessments, retains the newest N per project, and never removes running
work.

Generated Bash, Zsh, and Fish completions query the active database and policy location for project IDs, assessment
aliases, indicator IDs, and named profiles, while falling back cleanly when those files do not yet exist.

Exit status meanings are:

- `0`: completed without violations;
- `1`: completed with quality violations;
- `2`: arguments or policy are invalid;
- `3`: assessment is incomplete, invalid, timed out, or hit a tool/system execution error;
- `4`: database, schema, locking, or integrity failure.

Incomplete evidence takes precedence over an ordinary quality-violation exit because the result cannot be treated as
a complete quality decision.
