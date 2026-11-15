# AQ-009 test and coverage review

The AUnit action now runs 49 tests: component cases for registry, coverage arithmetic, status invariants, policy,
JSON, storage, execution, proof applicability, source analysis, database integrity, symbolic-link safety, finding
identity, and history; read-only reporting cases; and 29 separately registered persistence-corruption cases. Each
corruption mode receives a fresh fixture and an independent AUnit result. Result: 49 successful,
zero failed assertions, zero unexpected errors.

Fresh isolated instrumented runs observed:

```text
covered=<current tracked count>
total=<current tracked count>
complete=true
inventory=gcov-production-lines-v3
excluded_ada_quality_coverage=coverage-driver
source_fingerprint=<matched reviewed tree>
toolchain_fingerprint=<matched selected GNAT toolchain>
```

The tracked ratio is required to remain at or above 90%. Unchanged complete runs produce identical aggregate and
per-production-unit counts. The driver
stores an independent stability artifact and rejects drift for the same source and toolchain. Self-assessment never
redirects or replaces canonical coverage evidence: its explicit internal switch can only disable TST-03 evidence and
therefore fails closed. Stability is atomically published before the consumer-facing summary.
The v3 inventory independently enumerates eligible production units and rejects missing instrumentation. AQ9-002 is
resolved.

The coverage workflow exercises the CLI help/version surface, database and policy commands, project lifecycle, two
full assessments, JSON reporting, history/status/findings/regressions, recovery, release checking, and representative
error exits. Added cases cover interruption-commit rollback, closed/unsupported schema paths, missing and symlinked
project roots, same-identity workspace isolation, policy comments, incomplete history comparisons, and lifecycle
regressions.
