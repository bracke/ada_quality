# Read-only reporting API

`Ada_Quality.Reporting` gives reporting consumers, such as `ada_quality_summary`, a strongly typed, snapshot-consistent
view of persisted assessments without exposing tables or payload encodings.

## Session

`Open (Session, Path, Limits)`:

1. rejects an empty path, a missing path, and anything that is not a regular file, and never creates a file;
2. opens the database with `Database.Open_Read_Only`: `O_RDONLY`, a nonblocking shared process lock, no recovery,
   no migration, and no writes;
3. requires exactly the eight logical tables and schema version 3;
4. reads projects, runs, results, measurements, and findings inside one read transaction, enforcing
   `Load_Limits`;
5. commits the transaction and closes the database before returning.

Every later query is a pure function of that in-memory snapshot. Failures raise `Reporting_Error` (path or open),
`Busy_Error` (a writer holds the lock), `Schema_Error` (missing tables or unsupported version), `Integrity_Error`
(pending write-ahead log, unknown states, orphaned rows, duplicate or missing results, malformed evidence), or
`Limit_Error`.

## Queries

| Function | Result |
| -------- | ------ |
| `Projects` | Registry entries in ascending ID order, tombstones on request. |
| `Runs` | Run metadata in every lifecycle state with fingerprints, optional UTC `Started_At` and `Finished_At`, and evidence format. |
| `Read_Assessment` | A completed assessment with exactly 33 results in registry order, typed measurements, and findings. |
| `Supported_Schema_Version` | The validated schema version. |
| `Snapshot_Identity` | FNV-1a digest of every loaded row. |
| `History_Items`, `Read_History_Evidence`, `All_Measurements` | Rows in the shapes `Ada_Quality.History` consumes. |

`Read_Assessment` validates indicator identities, uniqueness, completeness, enumeration spellings, canonical numbers,
payload canonicality, and `Ada_Quality.Types.Is_Valid`. Defaults are never substituted for missing evidence.

## Schema version 3

Schema 3 is reached by an explicit migration from versions 1 and 2 inside `Storage.Open`; the migration changes only
the metadata row, so existing evidence stays byte-identical. From version 3 on:

- `Start_Assessment` records `started_at`; `Publish`, `Interrupt_Assessment`, and `Recover` record `finished_at`
  (UTC, `YYYY-MM-DDTHH:MM:SSZ`);
- `Publish` marks the run `evidence_format=3` and writes results as escaped `applicable`, `summary`, `evidence`
  fields and findings as escaped `indicator`, `rule`, `message`, `path`, `line` fields.

Runs without the marker are legacy evidence: results split summary and evidence at the first line feed, applicability
follows the not-applicable execution state, finding locations are absent, and the finding indicator comes from the
fingerprint prefix. No timestamp is ever inferred for a legacy run.

The entity layout and every codec live in the private package `Ada_Quality.Persistence`, shared by `Storage` and
`Reporting`.

`Ada_Quality.Indicators.Measurement_Unit` names the unit of each indicator's numeric measurement (`none` for
Boolean indicators).

## Test support

`Storage.Testing_Use_Legacy_Evidence` publishes schema-2 encodings, and `Storage.Testing_Corrupt` damages a disposable
copy, so consumers can test legacy decoding and integrity failures without weakening publication validation.
