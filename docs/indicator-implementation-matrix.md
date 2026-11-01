# Indicator implementation matrix

The immutable registry contains 33 IDs. STR-01..05, SRC-01..06, DOC-01/DOC-03, DEP-02, SEC-01..03, and REL-02/03 are native. BLD-01..04, TST-01/02/04, DEP-01/03, and DOC-02 use bounded external adapters. TST-03 consumes source-bound complete gcov evidence; REL-01 runs the staged checker; REL-04 checks original Git state and fingerprints; PRF-01 runs GNATprove only for declared SPARK units. Every prerequisite failure yields blocked or not-applicable evidence, never pass.
