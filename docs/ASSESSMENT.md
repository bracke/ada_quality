# Assessment semantics

The registry in `Ada_Quality.Indicators` is immutable and contains exactly 33 version-1 descriptors. Every full
assessment returns one result for every descriptor, including blocked and not-applicable results.

Native checks inspect manifests, layout, Ada sources, documentation, dependency pins, likely secret material, unsafe
shell patterns, release metadata, and source-tree artifacts. Source checks exclude `.git`, `.alire`, `obj`, `bin`,
`lib`, and `gnatprove` trees.

External checks run Alire build and validation gates, query the selected toolchain, run a test action twice, execute
the standard release checker, and run GNATprove for projects declaring `SPARK_Mode`. Proof uses `--mode=prove`; a
legality-only result is not accepted as proof discharge.

Coverage is intentionally blocked unless a complete instrumented production executable-line inventory is available
and its recorded source fingerprint matches the assessment. Zero eligible lines cannot pass. The pure
`Coverage_Passes` calculation uses widened exact arithmetic, so 89.99% fails, 90.00% passes, and multiplication cannot
overflow at `Natural'Last`.

GNATdoc writes to a dedicated temporary output directory that is removed after the check, so documentation generation
does not alter the project source tree. These conservative outcomes are part of the contract: unsupported evidence
cannot silently become compliance.

Finding fingerprints combine indicator, rule, relative semantic context, and message. Persisted assessments retain
policy and source fingerprints for compatibility checks. The `regressions` command compares the two newest runs per
project and reports indicators whose state changed away from pass.

When policy requires a clean worktree, REL-04 runs Git status before and after the tools and also compares source
fingerprints. Missing repository evidence blocks; dirty or modified source violates.
