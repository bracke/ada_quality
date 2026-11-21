# Database

The persistent store uses the sibling Ada `database` crate. Schema version 5 contains exactly eight logical typed
tables and has explicit atomic migrations from versions 1 through 4:

1. `projects`
2. `assessment_runs`
3. `indicator_results`
4. `measurements`
5. `findings`
6. `tool_executions`
7. `assessment_events`
8. `schema_metadata`

Every table uses an explicit `Entity` Ada record and explicit `To_Row`, `From_Row`, key extraction, and key-value
mapping. Rows use integer primary and parent identifiers, typed text fields, and a Boolean activity flag. Project
removal is soft so historical assessments retain their parent identity.

Assessment publication requires 33 unique valid results and inserts the run state, results, measurements, findings,
execution summary, and publication event in one write transaction. The caller performs all external work before
opening that transaction. Terminal assessment rows are never updated. Recovery changes an abandoned `running` row
and inserts its recovery event in one transaction; repeated recovery is idempotent.

Version 3 records run timestamps and uses escaped, named fields for result and finding evidence. This preserves
newlines and source locations without changing the eight-table catalog. Migrated legacy rows remain readable and
are explicitly distinguishable from lossless version-3 evidence.

Version 4 adds globally unique canonical assessment aliases as append-only events owned by completed runs. Alias
events are counted separately from the required started/terminal lifecycle pair and never rewrite terminal evidence.

Version 5 stores sorted project tags beside each canonical path. Migration preserves project identities and all
assessment evidence while assigning an empty tag set to existing projects.

Measurement state records include the value kind, indicator-contract version, and measurement-method version. This
is an evidence-format extension within schema 3 rather than a table-layout change; existing rows retain explicit
legacy v1/v1 interpretation for trend compatibility.

Opening a persistent database acquires the storage engine's process lock. `database check` verifies the open handle,
the eight-table catalog, and schema metadata version.

Logical export/import is symmetric: `database import SOURCE --database DESTINATION` creates a new database from the
native export format and performs a complete integrity check before reporting success. Existing destinations are
never overwritten. Transactional compaction is likewise checked before and after vacuuming.

Physical backups and logical exports may be authenticated with Ed25519. A physical-backup signature covers its
verified checksum manifest; a logical-export signature covers a domain-separated streaming SHA-256 digest of every
export byte. Verification requires either an explicitly supplied public key or a local trust store populated with
`database trust add`; restore/import can require either form before creating their destination database. Signature
inspection reports the algorithm, digest, artifact kind, and stable key identity without claiming verification.

`database archive DEST --before UTC [--keep N]` first creates and verifies a complete logical export. It then
transactionally removes terminal assessments older than UTC, retaining at least the newest N terminal assessments
per project and every running assessment. Owned evidence and aliases are removed with their archived assessment;
the resulting live database is checked and compacted, and the archive remains importable.

`database archive --dry-run --before UTC [--keep N] [--json]` lists the exact assessments that would be removed without
creating an archive or changing the database. `database merge SOURCE...` accepts one or more databases or native exports,
matches projects by canonical path, deduplicates completed runs by fingerprints, remaps identities, and preserves
nonconflicting assessment aliases. `--dry-run` reports additions, reuse, aliases, and conflicts without changing
allocator or database state. A real merge applies projects, tags, assessments, evidence, events, and aliases in one
write transaction across every source, so any conflict or insertion failure rolls back the complete merge.
