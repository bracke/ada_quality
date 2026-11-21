# Architecture

Ada Quality is a single-process Ada 2022 CLI. The command layer loads one central policy, reads the enabled project
registry in stable database order, and coordinates a bounded set of assessment workers. Run creation, publication,
and batch output remain serialized in project order. `Ada_Quality.Checks` owns the fixed 33-result
assessment pipeline; `Ada_Quality.Execution` owns bounded, timed external command execution; and
`Ada_Quality.Storage` owns typed persistence and transaction boundaries.

The checks package keeps its public facade and main body small. Private child packages own manifest validation and
Ada-aware source-safety lexing, giving those policies independently testable dependency boundaries. Focused subunits
remain only for assessment coordination and source-tree operations that require the parent's private implementation
context. CLI command, subcommand, option-scope, help, and completion data live in
`Ada_Quality.CLI_Metadata`; validation and all three shell generators consume that same typed table.
The same table generates per-command accepted-option help, while the public router and each substantial command
handler live in focused subunits instead of one monolithic CLI body. Project, assessment, regression, and report
workflows have their own command units; the central router performs validation, store selection, and dispatch only.
`Ada_Quality.CLI_Arguments` captures the process arguments once as an immutable value, while the public CLI entry point
also accepts an explicit argument set for deterministic embedding and tests. Explicit requests are held in task-local
context, so nested and concurrent callers cannot overwrite one another. Cursor-paginated handlers translate that
snapshot into typed request records before querying domain services. `Ada_Quality.CLI_Cursors` owns the versioned cursor
codec and query binding, `Ada_Quality.CLI_Pagination` owns snapshot revisions and page metadata, and
`Ada_Quality.CLI_Changed_Files` owns bounded stdin parsing. `Ada_Quality.Pagination` provides both vector slicing and a
streaming page collector that retains only the requested page while still reporting the complete match count. Reverse
pages append during collection and reverse once at completion, preserving linear complexity.
Presentation-neutral command result types live in `Ada_Quality.Command_Models`. Focused
`JSON_Assessments`, `JSON_Reports`, and `JSON_Administration` packages own serialization for their domains;
`Ada_Quality.JSON` is only the stable compatibility facade.
`Ada_Quality.History_Data` owns persistence-neutral history DTOs, so history analysis and read-only reporting do not
depend on writable storage. Store-scoped test controls live under the explicit `Ada_Quality.Storage.Testing` child.
Retention candidate planning lives behind the private `Ada_Quality.Storage.Retention` child. Production callers use
the capability-oriented `Storage.Registry`, `Storage.Assessments`, `Storage.Transfer`, and `Storage.Integrity`
boundaries. Registry, assessment publication/query, transfer, and schema-version implementations live with their
owning capability packages. The parent retains the store handle, shared DTOs, store lifecycle, and private transaction
helpers used by its children; production operations exist only at the focused capability APIs.
`Ada_Quality.Schema_Catalog` is the single
inventory consumed by both release validation and schema syntax tests.

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

Security-sensitive artifact and lock descriptors are opened through the small `ada_quality_posix_shim.c` boundary. All
direct libc imports, including process signalling and private temporary-directory creation, are declared by the
typed `Ada_Quality.POSIX` boundary rather than scattered through domain units. The
shim obtains flags and file-kind definitions from the host headers, applies close-on-exec explicitly, traverses
staging directories through descriptors, and keeps platform ABI constants and procfs paths out of Ada code.
`Ada_Quality.POSIX` also owns descriptor invalidation: checked closes report failure while exception cleanup uses the
idempotent best-effort close, preventing double-close and keeping raw descriptor lifetime rules out of signing code.
Key and signature metadata is read once from no-follow descriptors, classified after opening, and rejected above the
dedicated metadata-size limit; staged signature sidecars use the same bound. Artifact kind and content are likewise
bound to one descriptor before hashing, including backup manifests opened relative to their directory descriptor.
Private seeds are decoded directly from a bounded mutable buffer, which is wiped together with every encoded scratch
buffer. Other whole-file project metadata uses the shared bounded reader rather than unchecked raw-file allocation.

`Storage.Integrity.Check` scans all eight logical tables once in one read transaction, applies aggregate row and text limits,
and builds ordered ownership indexes before validating schema metadata, lifecycle topology, terminal cardinality,
typed measurements, findings, executions, and events. Reporting snapshots apply per-table plus aggregate row and text
limits, index projects and per-project run positions while decoding, and independently validate all terminal
assessments before exposing typed evidence. Visitors stream projects and histories from those indexes without building
intermediate vectors. Archive rendering walks details per run and streams bounded JSON without constructing an
archive DOM. History comparisons and metric trends build fingerprint and run/indicator indexes, and a shared reporting
comparison service supplies both CLI and archive renderers. CLI
read commands open only this immutable read snapshot; mutation commands alone open `Storage`.
Multi-source merge planning and application live in a dedicated storage subunit so routine persistence operations
do not share the merge algorithm's temporary indexes and conflict-resolution machinery.

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
