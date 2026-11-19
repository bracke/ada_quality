# Architecture

Ada Quality is a single-process Ada 2022 CLI. The command layer loads one central policy, reads the enabled project
registry in stable database order, and coordinates a bounded set of assessment workers. Run creation, publication,
and batch output remain serialized in project order. `Ada_Quality.Checks` owns the fixed 33-result
assessment pipeline; `Ada_Quality.Execution` owns bounded, timed external command execution; and
`Ada_Quality.Storage` owns typed persistence and transaction boundaries.

The checks package keeps its public facade and main body small. Private child packages own manifest validation and
Ada-aware source-safety lexing, giving those policies independently testable dependency boundaries. Focused subunits
remain only for assessment coordination and source-tree operations that require the parent's private implementation
context.
`Ada_Quality.History_Data` owns persistence-neutral history DTOs, so history analysis and read-only reporting do not
depend on writable storage. Store-scoped test controls live under the explicit `Ada_Quality.Storage.Testing` child.

The domain model carries execution and compliance as separate enumerations. A successful tool invocation is not by
itself compliance evidence, and a blocked, failed, errored, or missing measurement always has unknown compliance.
Not-applicable results require an explicit applicability reason.

External programs are located before execution and receive an argument vector, never a shell command string. GNU
GNAT Expect enforces a monotonic policy deadline and escalates from TERM to KILL after five seconds. A streaming filter bounds merged
stdout/stderr while the child runs and records truncation. Capture state is local to each invocation, and GNU `env`
selects the child working directory without mutating the parent process directory. A protected gate serializes the
GNAT runtime's spawn/monitor/close boundary across concurrent callers. Persisted command evidence contains
the resolved executable and a redacted, single-line argument-shape summary. External tools run without an open database
transaction.

`Storage.Check` scans all eight logical tables once in one read transaction, applies aggregate row and text limits,
and builds ordered ownership indexes before validating schema metadata, lifecycle topology, terminal cardinality,
typed measurements, findings, executions, and events. Reporting snapshots apply per-table plus aggregate row and text
limits, index project histories by payload position, and independently validate all terminal assessments before
exposing typed evidence. Archive rendering walks details per run and streams bounded JSON without constructing an
archive DOM. History comparisons and metric trends build fingerprint and run/indicator indexes, and a shared reporting
comparison service supplies both CLI and archive renderers. CLI
read commands open only this immutable read snapshot; mutation commands alone open `Storage`.

Persistence owns the canonical assessment identifiers, timestamp ordering, metadata/project/assessment/event row
validators, private execution payload codec, and lifecycle transition/cardinality rules used by both write-side
audits and read-only snapshots. History retains compatibility
with legacy delimiter-based and pre-context finding fingerprints through one-to-one matching; ambiguous many-to-one matches remain
unconfirmed instead of hiding newly introduced findings.

The indicator registry is the source of contract cardinality, measurement units, gate classification, and numeric
trend direction. Terminal publication and read-side validation reject `not-run` and `running` indicator evidence.
History comparisons require an available confirmed toolchain identity; the explicit unavailable identity cannot form
a baseline.

The source fingerprint covers ordinary project files while excluding generated build, VCS, coverage, and proof
directories. Versioned length-framed records preserve kind, relative-path, and content boundaries. Traversal never
follows symbolic links but fingerprints their relative paths. The identity is captured
before tools run and checked again before publication. Coverage carries the same identity, and stale evidence blocks.

The initial specifications and AQ phase plans remain under the repository root and `phases/` as requirements and
traceability inputs.
