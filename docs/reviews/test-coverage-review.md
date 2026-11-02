# AQ-009 test and coverage review

The AUnit action ran 21 tests: twelve component cases for registry, coverage arithmetic, status invariants, policy,
JSON, storage, execution, proof applicability, source analysis, database integrity, symbolic-link safety, and
history, plus nine read-only reporting cases. Result: 21 successful,
zero failed assertions, zero unexpected errors.

Fresh isolated instrumented runs observed:

```text
covered=3702
total=4113
complete=true
inventory=gcov-production-lines-v2
excluded_ada_quality_coverage=coverage-driver
source_fingerprint=<matched reviewed tree>
toolchain_fingerprint=<matched selected GNAT toolchain>
```

This is 90.00%. Unchanged complete runs produced identical aggregate and per-production-unit counts. The driver
stores an independent stability artifact and rejects drift for the same source and toolchain. It seeds its temporary
self-assessment evidence with the current fingerprint, eliminating the former first-run/second-run path difference.
The v2 inventory independently enumerates eligible production units and rejects missing instrumentation. AQ9-002 is
resolved.

The coverage workflow exercises the CLI help/version surface, database and policy commands, project lifecycle, two
full assessments, JSON reporting, history/status/findings/regressions, recovery, release checking, and representative
error exits. Added cases cover interruption-commit rollback, closed/unsupported schema paths, missing and symlinked
project roots, same-identity workspace isolation, policy comments, incomplete history comparisons, and lifecycle
regressions.
