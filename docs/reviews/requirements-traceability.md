# AQ-009 requirements traceability review

The existing traceability was checked against actual source and executable evidence. No required capability is
represented only by a placeholder.

| Requirement | Source boundary | Current verification |
|---|---|---|
| Exactly 33 indicators | `Ada_Quality.Types`, `Ada_Quality.Indicators` | unique source count 33; `REGISTRY_TEST`; full assessment |
| Execution/compliance separation | `Types.Is_Valid`, `Evaluation`, `Checks` | `STATUS_TEST`; JSON states reviewed |
| Strict central policy | `Ada_Quality.Policy` | `POLICY_TEST`; full assessment |
| Eight-table persistent store | `Ada_Quality.Storage` | `STORAGE_TEST`; `INTEGRITY_TEST`; CLI integrity check |
| Atomic publication and recovery | `Storage.Publish`, `Interrupt_Assessment`, `Recover` | start, publication, interruption, and recovery commit-fault rollback assertions |
| Private isolated assessment | `Checks.Assess`, `Workspaces.Prepare`, `Temporary_Directories` | concurrent same-identity workspace regression; staged release checker |
| Explicit process arguments and limits | `Ada_Quality.Execution` | `EXECUTION_TEST`; timeout and bounded-capture fixtures |
| Safe source traversal and identity | `Checks`, `Workspaces` | `SYMLINK_TEST`; fingerprint assertions |
| Exact stable source-bound coverage | `Types.Coverage_Passes`, coverage driver, TST-03 | 3,702/4,113; complete source/toolchain and per-unit stability checked |
| Conditional SPARK proof | `Checks.Declares_SPARK`, PRF-01 | `APPLICABILITY_TEST`; current project reports N/A |
| Deterministic versioned JSON | `Ada_Quality.JSON` | `JSON_TEST`; strict `jq` parse; schemas parse |
| Finding/history lifecycle | `Ada_Quality.History`, CLI comparison | `HISTORY_TEST`; two-assessment coverage workflow |
| CLI commands and exit classes 0-4 | `Ada_Quality.CLI` | coverage workflow; direct exit 2 and exit 4 checks |
| Release evidence | REL-01 through REL-04, `check_all` | full assessment and independent checker pass |

The AQ-000 through AQ-008 verification reports exist and identify reconstructed historical evidence where original
phase-only logs were unavailable. AQ-009 does not reinterpret those reconstructions as historical execution logs.
