# AQ-009 indicator verification

A fresh assessment against the disposable review database exited 0 and published one completed assessment with 33
unique results.

| Group | Verified result |
|---|---|
| STR-01 through STR-05 | 5 succeeded/pass |
| BLD-01 through BLD-04 | 4 succeeded/pass |
| TST-01 through TST-04 | 4 succeeded/pass |
| SRC-01 through SRC-06 | 6 succeeded/pass |
| DOC-01 through DOC-03 | 3 succeeded/pass |
| DEP-01 through DEP-03 | 3 succeeded/pass |
| SEC-01 through SEC-03 | 3 succeeded/pass |
| REL-01 through REL-04 | 4 succeeded/pass |
| PRF-01 | not-applicable/not-applicable: no source declares `SPARK_Mode` |

The JSON archive independently confirmed 33 result rows, 33 unique indicator names, 32 `succeeded/pass` states, one
`not-applicable/not-applicable` state, a completed terminal assessment, and a source fingerprint equal to the
reviewed tree.

All broad exception handlers are explicit audited boundaries. Inspection confirmed that they restore directory,
process, environment, coverage-artifact, database, or test state and re-raise, or translate an exception at a defined
policy, presentation, execution, or CLI boundary. No unsafe broad handler is accepted by SRC-05.

DOC-01 and DOC-02 were reverified after documenting the complete project-owned API and excluding dependency project
files from this project's GNATdoc scope. `gnatdoc --warnings` completed with no diagnostic output.
