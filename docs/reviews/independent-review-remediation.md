# Independent implementation review remediation

The 1 November 2026 source-level review findings were corrected in their owning components without changing the
project architecture.

| Finding | Correction and regression evidence |
|---|---|
| AQ-01 | Coverage inventory starts from every eligible production unit and requires matching instrumentation plus a complete, parsed gcov summary for every body and specification. Missing-unit, header-only, malformed-summary, and missing-source fixtures fail completeness. Evidence uses `gcov-production-lines-v2`. |
| AQ-02 | BLD-03 resolves the manifest's root GPR files and builds generated extending projects that preserve inherited switches while adding target-scoped `-gnatwa -gnatwe`; a standalone fixture proves switch preservation and warning rejection. |
| AQ-03 | History defines metric direction per indicator and tests pass-to-fail, fail-to-worse-fail, improvement, deterioration, and evidence loss. |
| AQ-04 | SRC-03 has a precise lexical Ada decision-complexity contract and representative nested, expression, case, loop, and short-circuit fixtures. |
| AQ-05 | DOC-01 evaluates GNATdoc warnings for every public declaration instead of accepting one file-level comment. |
| AQ-06 | Local dependencies are read only from Alire pin and lockfile-link sections; comments, multiline strings, and unrelated `path` keys are ignored, while quoted keys and Unicode escapes are decoded. Mutable Alire state is not staged. |
| AQ-07 | TST-04 snapshots one post-build baseline, restores it with file attributes intact before the second run, and compares successful execution, narrowly normalized output, source state, and streamed artifact fingerprints. |
| AQ-08 | SPARK applicability uses exact tokens outside comments and strings across Ada, configuration, and project sources. |
| AQ-09 | Policy input is a strict root-level TOML subset: unsupported sections, keys, values, duplicates, and malformed input are rejected. |
| AQ-10 | Regression reporting requires completed, identified runs before policy-change comparison and distinguishes a clean result from every unavailable-comparison reason. |

Reporting history and trend adapters additionally perform the same canonical 33-indicator evidence validation as
single-assessment reads, so malformed persisted evidence cannot silently suppress a comparison.

Release evidence must be regenerated after the final correction so that it is bound to the exact source and selected
toolchain fingerprints.
