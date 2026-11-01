# Independent implementation review remediation

The 1 November 2026 source-level review findings were corrected in their owning components without changing the
project architecture.

| Finding | Correction and regression evidence |
|---|---|
| AQ-01 | Coverage inventory now starts from every eligible production unit and requires matching instrumentation; a missing-unit fixture fails completeness. Evidence uses `gcov-production-lines-v2`. |
| AQ-02 | BLD-03 runs a separate project-scoped validation build with warnings as errors; an intentional-warning fixture proves the gate fails. |
| AQ-03 | History defines metric direction per indicator and tests pass-to-fail, fail-to-worse-fail, improvement, deterioration, and evidence loss. |
| AQ-04 | SRC-03 has a precise lexical Ada decision-complexity contract and representative nested, expression, case, loop, and short-circuit fixtures. |
| AQ-05 | DOC-01 evaluates GNATdoc warnings for every public declaration instead of accepting one file-level comment. |
| AQ-06 | Local pins are tokenized outside TOML comments and strings with whitespace and quote variation fixtures; mutable Alire state is not staged. |
| AQ-07 | TST-04 compares successful execution, normalized presentation output, and project-artifact fingerprints across two direct AUnit runs. |
| AQ-08 | SPARK applicability uses exact tokens outside comments and strings across Ada, configuration, and project sources. |
| AQ-09 | Policy input is a strict root-level TOML subset: unsupported sections, keys, values, duplicates, and malformed input are rejected. |
| AQ-10 | Regression reporting distinguishes a clean comparable result from each unavailable-comparison reason. |

The release evidence is regenerated only after these corrections and remains bound to the exact source and selected
toolchain fingerprints.
