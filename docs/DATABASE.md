# Database

The persistent store uses the sibling Ada `database` crate. Schema version 3 contains exactly eight logical typed
tables and has explicit atomic migrations from versions 1 and 2:

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

Opening a persistent database acquires the storage engine's process lock. `database check` verifies the open handle,
the eight-table catalog, and schema metadata version.
