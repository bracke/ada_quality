# Release readiness

Release gates are `alr build --validation -- -f`, `alr test`, `alr exec -- ./bin/coverage`, GNATdoc generation, and
`./bin/check_all`. The coverage driver is the exact >=90% gate. The standard checker independently requires all
AQ-000 through AQ-008 records, both JSON schemas, exactly 33 indicators, the coverage artifact, and a passing
twelve-case AUnit binary. Keeping these gates
separate allows a failed coverage artifact to be replaced by a fresh measurement.

The crate is ready for AQ-009 independent review when `phase-8-verification.md` records all gates passing. No
critical/high AQ-008 audit defect is open.

Known non-blocking limitations:

- this exported workspace has no Git metadata, so its checked-in policy disables the optional Git gate while REL-04
  still requires the source fingerprint to remain unchanged; Git-backed deployments may enable the stronger gate;
- schema version 2 has an atomic version-1 migration and injected migration-commit retry fixture; unknown versions
  fail closed;
- PRF-01 is not applicable to Ada Quality itself because its sources do not declare `SPARK_Mode`;
- AQ-000 through AQ-007 reports are current reconstruction records, explicitly not fabricated historical logs;
- the release manifest contains no local workspace pins; deterministic development links remain in the committed
  lockfile and are staged recursively without weakening DEP-02.

AQ-009 must remain read-only and independently confirm requirement coverage, database safety, CLI/JSON behavior,
and release evidence.
