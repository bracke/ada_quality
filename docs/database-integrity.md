# Database integrity

The store uses the sibling `database` crate and exactly eight catalog tables. `Entity` has explicit row conversion,
key extraction, and typed database values. Schema metadata is version `3`; an absent database can be created, while
missing or incompatible existing storage fails the integrity path.

Transaction boundaries:

- project insert/update and assessment start are single write transactions;
- no database write transaction remains open while external tools execute;
- terminal run state, 33 results, measurements, findings, all execution records, and publication event commit together;
- any publication exception rolls back the active transaction;
- recovery state and its recovery event commit together and roll back together;
- completed-run aliases append as globally unique validated events without rewriting terminal evidence;
- completed/interrupted/invalid runs cannot be republished.

The integrity fixture injects failures before schema-creation, assessment-start, publication, recovery, and migration
commits, plus invalid UTF-8 during publication. It verifies rollback, reopen/retry, no leaked dependent rows, immutable
terminal evidence, and idempotent recovery.

`database check` performs a bounded single-snapshot scan of every logical table. Its configurable aggregate row and
text budgets are enforced before retaining each row, and ownership indexes avoid repeated whole-table scans. It
rejects malformed or duplicate metadata and project
rows, orphaned children, unknown lifecycle states, contradictory active flags, incomplete or duplicate 33-indicator
sets, malformed typed measurements, findings, and execution payloads, invalid execution/event states, missing or contradictory lifecycle
events, and terminal evidence attached to an unpublished run. The corruption fixtures exercise this command directly.
The writable integrity command and read-only reporting decoder share the canonical metadata, project, assessment,
event, result-state, execution-payload, and lifecycle validators. Execution digests must use the canonical 16-character lowercase
FNV-1a spelling, byte counts are nonnegative 64-bit values, and spawn errors cannot claim a child exit status.
Unsupported evidence formats, malformed or chronologically
inverted timestamps, duplicate or extra run fields, and
inactive timeout/spawn-error execution evidence are therefore rejected consistently by both paths. Result,
measurement, and finding active flags are also checked against their typed states. Canonical indicator spellings,
nonempty single-line fingerprints, lifecycle-appropriate timestamp presence, and per-run
finding-fingerprint uniqueness are also
enforced on both writable and read-only integrity paths.
Terminal result sets reject the in-progress `not-run` and `running` execution states even when their compliance and
measurement fields would otherwise form a valid in-memory state.
Assessments whose structure prevents a toolchain query publish the explicit single-line identity
`toolchain-unavailable`; they never fall back to an empty or structurally invalid fingerprint.

Opening version 1 atomically converts legacy assessment fingerprint payloads; versions 2 and 3 preserve their rows.
All advance metadata to version 5 in the same migration transaction. Migration failure leaves the prior version
intact for retry. Silently rewriting an unknown version is forbidden.
