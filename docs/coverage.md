# Coverage

TST-03 accepts only complete, source-bound `gcov-production-lines-v2` evidence. The driver enumerates units from
`src` before inspecting coverage files and fails if any eligible unit lacks its `<stem>.gcno` instrumentation.
Every unit must also produce either a matching production-source record with a syntactically valid `Lines executed`
or `No executable lines` summary, or gcov's explicit whole-unit `No executable lines` result. A specification with
no executable lines needs no separate record when its unit body has one; a unit with no production record or
explicit no-code result fails completeness.
Gcov's final aggregate line is excluded from per-source parsing. The
self-hosting `ada_quality_coverage` driver is the one explicit exclusion because it owns the active coverage files
and is verification tooling rather than a shipped Alire executable. Evidence records that exclusion. The gate
requires nonzero eligible executable lines and compares exact integers against the policy basis points.
