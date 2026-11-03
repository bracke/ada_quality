# Requirements traceability

| Requirement | Implementation | Verification |
|---|---|---|
| Exactly 33 indicators | `Ada_Quality.Indicators`, `Types.Indicator_Id` | `REGISTRY_TEST`; release checker count gate |
| Execution/compliance separation | `Types.Is_Valid`, result constructors in `Checks` | `STATUS_TEST` |
| One central strict policy | `Ada_Quality.Policy` | `POLICY_TEST`; CLI policy E2E |
| Persistent eight-table store | `Ada_Quality.Storage` | `STORAGE_TEST`; `INTEGRITY_TEST`; database CLI E2E |
| Atomic terminal publication | `Storage.Publish` | injected encoding failure and rollback assertions |
| Idempotent crash recovery | `Storage.Recover` | repeated recovery and event-count assertions |
| Sequential full assessment | `Checks.Assess`, `CLI.Check_Project` | instrumented CLI E2E |
| Explicit argv and timeouts | `Ada_Quality.Execution` | missing, loud, and slow process fixtures |
| Bounded evidence | streaming capture filter in `Execution` | exact five-byte truncation assertion |
| Safe source traversal | `Checks.Tree_Entries` | external and cyclic link fixture |
| Source identity stability | `Checks.Source_Fingerprint` | deterministic and link-target isolation assertions |
| Exact coverage gate | `Types.Coverage_Passes`, `Checks` | boundary/overflow test; instrumented production coverage |
| Coverage/source compatibility | coverage tool and TST-03 adapter | fingerprint field required and compared |
| GNATprove applicability | `Checks.Declares_SPARK`, `Checks.Dedicated_Proof_Projects`, PRF-01 branch | `APPLICABILITY_TEST` |
| Release checker execution | REL-01 adapter and `bin/check_all` | full assessment E2E; final release gate |
| Clean staged source | REL-04 Git and fingerprint checks | negative semantics reviewed; full assessment E2E |
| Deterministic RFC 8259 JSON | `Ada_Quality.JSON` | strict jsonlib parse and 33-result assertions |
| Finding lifecycle | CLI `findings` comparison | two-assessment E2E exercises history paths |
| Exit classes 0-4 | CLI dispatcher | positive and negative process-level E2E scenarios |

The AQ-000 through AQ-007 specification files existed without formal phase verification reports when AQ-008 began.
This document reconstructs traceability from actual source and executed tests; it does not invent missing historical
evidence.
