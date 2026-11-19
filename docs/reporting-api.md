# Read-only reporting API

`Ada_Quality.Reporting` is the supported read path for CLI project queries, history, findings, regressions, and archive
JSON. It gives consumers a strongly typed, snapshot-consistent view without exposing tables or payload encodings.

## Session

`Open (Session, Path, Limits)`:

1. rejects an empty path, a missing path, and anything that is not a regular file, and never creates a file;
2. opens the database with `Database.Open_Read_Only`: `O_RDONLY`, a nonblocking shared process lock, no recovery,
   no migration, and no writes;
3. requires exactly the eight logical tables and exactly one fully canonical schema-version metadata row;
4. reads projects, runs, results, measurements, findings, executions, and events inside one read transaction, enforcing
   `Load_Limits`; per-table limits are supplemented by aggregate row and UTF-8 text budgets;
5. decodes each terminal assessment for validation, retains one canonical raw snapshot, and validates each result set and lifecycle-event sequence;
6. commits the transaction and closes the database before returning.

Every later query is a pure function of that in-memory snapshot. Failures raise `Reporting_Error` (path or open),
`Busy_Error` (a writer holds the lock), `Schema_Error` (missing tables or unsupported version), `Integrity_Error`
(pending write-ahead log, unknown states, orphaned rows, duplicate or missing results, malformed evidence), or
`Limit_Error`.

## Queries

| Function | Result |
| -------- | ------ |
| `Projects` | Registry entries in ascending ID order, tombstones on request. |
| `Runs` | Run metadata in every lifecycle state with fingerprints, optional UTC `Started_At` and `Finished_At`, and evidence format. |
| `Read_Assessment` | A completed assessment with exactly 33 results in registry order, typed measurements and findings, and typed executions. |
| `Supported_Schema_Version` | The validated schema version. |
| `Snapshot_Identity` | FNV-1a digest of versioned, length-framed fields from every loaded row. |
| `History_Items`, `Read_History_Evidence`, `All_Measurements` | Rows in the shapes `Ada_Quality.History` consumes. |
| `Results`, `Measurements`, `Findings`, `Events` | Indexed validated detail rows for one run. |
| `Executions` | Indexed, decoded execution records with tool, redacted command, status, exit, digest, size, and truncation fields. |
| `Compare_Project` | One shared baseline selection and regression result for CLI and archive consumers. |
| `Compare_Assessments` | Exact baseline/current comparison without automatic baseline substitution. |

Project-filtered `History_Items` queries use a compact position index and do not duplicate records or rescan unrelated
runs. The metadata row participates in `Snapshot_Identity`. Archive rendering streams constant-reference details one
row at a time without returned-vector copies and
emits JSON incrementally, checking a caller-selectable serialized-output limit before every append (256 MiB by
default).

`Open` applies the same indicator identity, uniqueness, completeness, enumeration, canonical-number, payload, and
`Ada_Quality.Types.Is_Valid` checks to every completed or invalid run. Defaults are never substituted for missing
evidence. It also rejects duplicate finding fingerprints, malformed structured execution evidence, and timestamps
that contradict or run backward within the assessment lifecycle.
`Read_Assessment` decodes one typed record on demand from the already validated canonical snapshot, so sessions do not
retain a second full typed copy of every completed run. Per-run queries use the snapshot's run index rather than
rescanning complete detail tables, and project comparison uses constant references internally.

## Schema version 3

Schema 3 is reached by an explicit migration from versions 1 and 2 inside `Storage.Open`; the migration changes only
the metadata row, so existing evidence stays byte-identical. From version 3 on:

- `Start_Assessment` records `started_at`; `Publish`, `Interrupt_Assessment`, and `Recover` record `finished_at`
  (UTC, `YYYY-MM-DDTHH:MM:SSZ`);
- `Publish` marks the run `evidence_format=3` and writes results as escaped `applicable`, `summary`, `evidence`
  fields and findings as escaped `indicator`, `rule`, `message`, `path`, `line` fields.
- Assessment publication requires nonempty single-line source, policy, and toolchain identities. A structurally
  blocked toolchain query uses the explicit `toolchain-unavailable` identity rather than an empty fingerprint. Execution rows use
  one canonical `command`, `exit_code`, `output_digest`, `output_bytes`, and `truncated` payload shared by both
  integrity readers. Reporting decodes this private payload into public typed fields.
- New measurement states append indicator-contract and measurement-method versions to the value kind. Reporting
  decodes the kind independently and preserves the complete semantic identity for historical trend and regression
  filtering.

Runs without the marker are legacy evidence: results split summary and evidence at the first line feed, applicability
follows the not-applicable execution state, finding locations are absent, and the finding indicator comes from the
fingerprint prefix. No timestamp is ever inferred for a legacy run.

The entity layout, codecs, lifecycle transition classifier, and lifecycle cardinality validator live in the private
package `Ada_Quality.Persistence`, shared by `Storage` and `Reporting`. The writable integrity command and read-only
reporting path therefore accept exactly the same metadata and event vocabulary.

## Schema versions 4 and 5

Schema 4 is reached by an atomic metadata migration from versions 1 through 3. It adds canonical append-only alias
events for completed assessments. Reporting validates global alias uniqueness and resolves either a positive numeric
identity or an alias without changing comparison chronology or evidence.

Schema 5 atomically converts each raw project path into a canonical path-and-tags payload. Reporting exposes the
sorted tag list while keeping the eight-table catalog and every assessment row unchanged.

`Ada_Quality.Indicators.Measurement_Unit` names the unit of each indicator's numeric measurement (`none` for
Boolean indicators).

## Test support

`Storage.Testing.Use_Legacy_Evidence (Store, ...)` publishes schema-2 encodings, and `Storage.Testing.Corrupt` damages a
disposable copy. Fault and encoding controls belong to one store instance, so concurrent fixtures cannot affect one
another or place test controls on the production storage API.
