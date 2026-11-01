# AQ-009 database integrity review

`Ada_Quality.Storage` was reviewed around schema creation and migration, project mutations, assessment start and
publication, interruption, recovery, reads, and integrity checking.

Verified controls:

- eight typed tables are registered and reopened through stored schema metadata;
- schema version 1 migrates atomically to version 2 and unknown versions fail closed;
- assessment start writes its running record and start event in one transaction;
- terminal publication validates 33 unique results and commits results, measurements, findings, executions, and the
  publication event atomically;
- interruption and recovery update state and write their event in the same transaction;
- write-boundary exception handlers roll back active transactions before propagating failure;
- commit fault points exercise schema creation, migration, assessment start, publication, interruption, and recovery;
- direct CLI integrity checks passed both before and after the fresh full assessment.

The AUnit storage and integrity cases passed, including reopen, rollback/retry, unknown-version rejection, immutable
terminal data, and idempotent recovery assertions. The review database exported one completed assessment without
partial rows.

The interruption-commit fixture verifies rollback before a successful retry, and repeated interruption remains
idempotent. Coverage and assessment scratch databases are private to an invocation; the persistent project database
continues to enforce its existing single-writer lock.
