# AQ-009 test and coverage review

The AUnit action ran 12 tests: registry, coverage arithmetic, status invariants, policy, JSON, storage, execution,
proof applicability, source analysis, database integrity, symbolic-link safety, and history. Result: 12 successful,
zero failed assertions, zero unexpected errors.

Fresh isolated instrumented runs observed:

```text
covered=2742
total=2979
complete=true
inventory=gcov-production-lines-v1
source_fingerprint=<matched reviewed tree>
toolchain_fingerprint=<matched selected GNAT toolchain>
```

This is 92.04%. Two unchanged complete runs produced identical aggregate and per-production-unit counts. The driver
stores an independent stability artifact and rejects drift for the same source and toolchain. It seeds its temporary
self-assessment evidence with the current fingerprint, eliminating the former first-run/second-run path difference.
AQ9-002 is resolved.

The coverage workflow exercises the CLI help/version surface, database and policy commands, project lifecycle, two
full assessments, JSON reporting, history/status/findings/regressions, recovery, release checking, and representative
error exits. Added cases cover interruption-commit rollback, closed/unsupported schema paths, missing and symlinked
project roots, same-identity workspace isolation, policy comments, incomplete history comparisons, and lifecycle
regressions.
