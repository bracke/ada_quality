# Implementation audit

Audit date: 2026-10-29. Scope: every unit under `src/`, the AUnit child crate, project metadata, database boundaries,
external execution, coverage, JSON, CLI workflows, and release tooling.

| Area | Owning unit | Audit result |
|---|---|---|
| Domain invariants | `Ada_Quality.Types` | Execution and compliance remain separate; blocked evidence cannot pass. |
| Registry | `Ada_Quality.Indicators` | Exactly 33 stable version-1 identifiers. |
| Policy | `Ada_Quality.Policy` | Unknown/duplicate keys and unsafe resource ceilings are rejected. |
| Evaluation | `Ada_Quality.Evaluation` | Deterministic mapping; unavailable evidence cannot pass. |
| Source checks | `Ada_Quality.Checks` | Ada-aware tokens, bounded traversal, complete source-bound coverage. |
| Processes | `Ada_Quality.Execution` | Explicit argv, streaming bounded capture, timeout and forced cleanup. |
| Workspaces | `Ada_Quality.Workspaces` | Isolated recursive local-pin staging with link/escape rejection. |
| Persistence | `Ada_Quality.Storage` | Eight typed tables, v1→v2 migration, immutable atomic publication/recovery. |
| History | `Ada_Quality.History` | Compatible baselines, lifecycle, regressions, and typed metric trends. |
| JSON | `Ada_Quality.JSON` | Versioned assessment/archive/regression exports and UTF-8 fixtures. |
| CLI | `Ada_Quality.CLI` | Strict options, messages/styles, complete commands, and exit classes 0–4. |

Resolved audit defects:

- AQ8-001 (high): stale coverage could pass after source changes. Coverage now records and verifies a source
  fingerprint.
- AQ8-002 (high): generic tree walking could follow external or cyclic symbolic links. Assessment traversal now rejects
  root links, never follows child links, fingerprints their paths, and makes SEC-03 fail when they exist.
- AQ8-003 (high): captured output was truncated only after unbounded accumulation. Capture is now streamed into the
  configured byte ceiling with a fixed internal process buffer.
- AQ8-004 (high): `require_clean_worktree` was ignored. REL-04 now requires clean Git evidence before and after tools.
- AQ8-005 (medium): recovery did not record an event atomically. State and event now commit together with rollback.
- AQ8-006 (medium): storage accepted partial or duplicate terminal result sets. Publication now requires 33 unique,
  valid results and rejects running-state publication.
- AQ8-007 (high): local-pin projects bypassed isolated staging. Pins and their transitive local crates are now copied
  recursively into a bounded container; absolute/escaping paths and links fail closed.
- AQ8-008 (high): finding absence in a completed but blocked remeasurement could be reported resolved. Resolution now
  requires successful remeasurement of that specific indicator.
- AQ8-009 (medium): the archive omitted regressions and CLI comparison could cross toolchains. Regression export is
  versioned and toolchain-incompatible runs are excluded.
- AQ8-010 (medium): schema migration and commit boundary failures lacked fixtures. Version 2 migration and five commit
  injection points now prove rollback/retry behavior.

No critical or high defect remains open from this audit. Lower-risk limitations are recorded in
`release-readiness.md`.
