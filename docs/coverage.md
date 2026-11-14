# Coverage

TST-03 accepts only complete, source-bound `gcov-production-lines-v3` evidence. The driver enumerates units from
`src` before inspecting coverage files and fails if any eligible unit lacks its `<stem>.gcno` instrumentation.
For each body and specification named by the source inventory, `gcov-dump` independently establishes whether the
compiler notes contain executable lines. Every source present in those notes must then have a matching gcov record
with a syntactically valid `Lines executed` or `No executable lines` summary. A source absent from the compiler notes
is explicitly classified as a zero-executable-line source; it cannot stand in for a noted source whose gcov record
is missing or malformed.
Gcov's final aggregate line is excluded from per-source parsing. The
self-hosting `ada_quality_coverage` driver is the one explicit exclusion because it owns the active coverage files
and is verification tooling rather than a shipped Alire executable. Evidence records that exclusion. The gate
requires nonzero eligible executable lines and compares exact integers against the policy basis points.
