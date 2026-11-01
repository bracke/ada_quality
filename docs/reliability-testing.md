# Reliability testing

The reliability suite combines 21 AUnit cases with process-level instrumented CLI workflows. It covers registry
and domain invariants, native analysis, policy failures, strict JSON/schema parsing, persistent reopen, migrations,
commit-boundary rollback, recovery, hostile process paths, timeouts, signals, output bounds, SPARK applicability,
recursive pin staging, link escape/cycle handling, deep trees, and 1,000-run histories.

The coverage workflow builds separate instrumented test/CLI/release binaries, runs two full assessments, exercises
all project lifecycle operations, database init/check/recover, policy validate/show, JSON archive reporting, history,
status, findings, regressions, invalid commands, invalid IDs, missing projects, and missing policy files.

Determinism controls include sorted source paths, stable database IDs under the single-process assessment model,
sorted JSON object members, two consecutive test actions, and a before/after source fingerprint. Projects are assessed
sequentially by design.

The tests deliberately use `/tmp` fixtures with explicit names and safe link-aware cleanup. They do not modify tracked
project sources. Because those names are fixed, independent copies of the suite must run sequentially; this matches
the product's explicit single-assessment execution model.
