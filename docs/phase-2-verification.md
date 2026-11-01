# AQ-002 verification

Current reconstruction, 2026-10-29. Tests cover create/close/reopen, lock conflict, duplicate and malformed registration, disabled start, missing references, rollback, 33-row publication, immutable terminal state, interrupted import, recovery, version-1 migration, unsupported schema rejection, and injected creation/start/publication/recovery/migration commit failures. The integrated suite passes.
