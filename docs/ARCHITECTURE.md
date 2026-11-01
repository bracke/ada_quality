# Architecture

Ada Quality is a single-process Ada 2022 CLI. The command layer loads one central policy, reads the enabled project
registry in stable database order, and assesses projects sequentially. `Ada_Quality.Checks` owns the fixed 33-result
assessment pipeline; `Ada_Quality.Execution` owns bounded, timed external command execution; and
`Ada_Quality.Storage` owns typed persistence and transaction boundaries.

The domain model carries execution and compliance as separate enumerations. A successful tool invocation is not by
itself compliance evidence, and a blocked, failed, errored, or missing measurement always has unknown compliance.
Not-applicable results require an explicit applicability reason.

External programs are located before execution and receive an argument vector, never a shell command string. GNU
`timeout` enforces the policy deadline and GNAT Expect supplies a second watchdog. A streaming filter bounds merged
stdout/stderr while the child runs and records truncation. External tools run without an open database transaction.

The source fingerprint covers ordinary project files while excluding generated build, VCS, coverage, and proof
directories. Traversal never follows symbolic links but fingerprints their relative paths. The identity is captured
before tools run and checked again before publication. Coverage carries the same identity, and stale evidence blocks.

The initial specifications and AQ phase plans remain under the repository root and `phases/` as requirements and
traceability inputs.
