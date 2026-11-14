# Indicator implementation matrix

The immutable registry contains 33 IDs. STR-01..05, SRC-01..06,
DOC-01/DOC-03, DEP-02/03, SEC-01..03, and REL-02/03 are native. DEP-03
structurally reconciles each top-level direct requirement with the solved Alire
lock state after DEP-01 resolution succeeds. REL-02 compares parsed SPDX
metadata with recognized license contents; REL-03 validates the canonical
Alire release metadata contract. BLD-01..04, TST-01/02/04, DEP-01, and DOC-02
use bounded external adapters. TST-03 consumes source-bound complete gcov
evidence; REL-01 runs the staged checker; REL-04 checks original Git state and
fingerprints; PRF-01 runs GNATprove only for declared SPARK units. Declared
SPARK without a usable GPR is blocked. Every prerequisite failure yields
blocked or not-applicable evidence, never pass.
