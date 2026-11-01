# Verification record

Verified against the local workspace on 2026-11-01:

- Alire 2.1.0 selects GNAT 15.2.1.
- The root project builds with Ada 2022 and 120-column checking.
- The actual sibling `database` typed-table, catalog, transaction, and persistent reopen APIs are used.
- The actual sibling `project_tools` file, process, and release-check APIs are used.
- Deterministic report construction uses `jsonlib`.
- Human output uses `messages` and `terminal_styles`; bounded security patterns use `regexp`.
- The AUnit child crate contains 21 test cases covering the registry/tool graph, coverage boundaries, status and
  evaluator invariants, policy, UTF-8 JSON/schemas, persistent storage/migrations/faults, bounded hostile execution,
  SPARK applicability, native analysis, isolated workspaces, link safety, history/regressions, and stress paths.
- Instrumented production coverage is 3,320/3,687 executable lines (90.04%).

The verification commands are:

```sh
alr exec -- gnatls --version
alr build --validation -- -f
alr test
alr exec -- ./bin/coverage
./bin/check_all
```

Network-dependent Alire resolution is environment-dependent. Existing lockfiles and cached dependencies are used for
offline rebuilds; a clean machine must fetch AUnit and the pinned GNAT toolchain once.
