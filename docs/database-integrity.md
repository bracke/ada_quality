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
- completed/interrupted/invalid runs cannot be republished.

The integrity fixture injects failures before schema-creation, assessment-start, publication, recovery, and migration
commits, plus invalid UTF-8 during publication. It verifies rollback, reopen/retry, no leaked dependent rows, immutable
terminal evidence, and idempotent recovery.

Opening version 1 atomically converts legacy assessment fingerprint payloads; opening version 2 preserves its rows.
Both advance metadata to version 3 in the same migration transaction. Migration failure leaves the prior version
intact for retry. Silently rewriting an unknown version is forbidden.
