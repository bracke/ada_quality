# Indicator audit

Every full assessment appends exactly one valid result for each identifier; storage independently enforces 33 unique
results before terminal publication.

| IDs | Measurement implementation | Failure safety |
|---|---|---|
| STR-01..05 | Manifest, GPR, layout, test crate, release checker inventory | Missing items are violations. |
| BLD-01..04 | Alire build, forced validation build, warnings gate, GNAT toolchain query | Spawn/timeout is blocked. |
| TST-01..04 | Two AUnit actions, registration scan, source-bound gcov, output comparison | Missing/stale evidence blocks. |
| SRC-01..06 | Formatting, naming, complexity, hygiene, handlers, size scan | Links and oversized inputs are rejected. |
| DOC-01..03 | Spec documentation scan, GNATdoc in temporary output, required docs | Tool failure cannot pass. |
| DEP-01..03 | Build resolution, local-pin scan, solution buildability | Failed dependency evidence is a violation. |
| SEC-01..03 | Secret/process pattern scans and artifact/link inventory | Links are reported, never traversed. |
| REL-01..04 | Checker, license/manifest, Git and fingerprint stability | Missing clean evidence is blocked. |
| PRF-01 | SPARK declaration scan and `gnatprove --mode=prove` | N/A needs no declaration; failed proof cannot pass. |

Coverage uses widened arithmetic, a nonzero denominator, the policy threshold, complete production-body gcov totals,
and an exact source fingerprint. The registry fixture round-trips every textual identifier.
