# AQ-008 verification

Date: 2026-10-29. Toolchain: Alire-selected GNAT 15.2.1. Status: complete; all mandatory phase gates pass.

Implemented or reviewed packages: `Ada_Quality.Types`, `Indicators`, `Policy`, `Evaluation`, `Execution`, `Checks`,
`Workspaces`, `Tools`, `Storage`, `History`, `JSON`, `Presentation`, `CLI`, the coverage driver, release checker, and
AUnit suite.

| Command | Exit | Evidence |
|---|---:|---|
| `alr build --validation -- -f` | 0 | Ada Quality sources compile under the validation profile |
| `alr test` | 0 | 21 run, 21 successful, 0 failed assertions, 0 unexpected errors |
| `alr exec -- ./bin/coverage` | 0 | 3,320/3,687 production lines, 90.04%; full CLI E2E completed |
| `alr exec -- gnatdoc -P ada_quality.gpr -O /tmp/ada-quality-phase8-gnatdoc --warnings` | 0 | generated docs; warnings retained as DOC-01 evidence |
| `./bin/check_all` | 0 | 21 AUnit cases and the complete AQ-000..AQ-008 release structure pass |

Failures encountered and resolved during hardening:

- the expanded implementation first measured 88.22%; descriptor, typed JSON, malformed-history, and other real
  branch fixtures raised it above policy; the current expanded source measures 90.04%;
- the first rerun exposed missing `messages`/`regexp` imports in the coverage GPR; the instrumented project now mirrors
  production dependencies;
- an aborted E2E run left WAL/full-text sidecars after deleting only the main temporary database; cleanup now removes
  the full database file set and the repeated run passes;
- local-pin projects formerly executed tools in their original trees; recursive isolated pin staging now covers them.

No automatic transition to AQ-009 is authorized by this report.

Changed implementation areas: typed measurements/executions, evaluator invariants, Ada-aware source analysis,
production/test/generated inventory, source-bound complete coverage, environment isolation, recursive staged pins,
strict CLI options, messages/regexp integration, compatible history/trends, versioned JSON regressions, migration and
commit fault injection, complete phase documentation, expanded stress/E2E tests, and release gates.

Unresolved blockers: none. Recommended next task: AQ-009 independent read-only implementation and release-readiness
review.
