# Reproducibility

Stable project IDs are processed in sorted order and one at a time. Source inventories and database queries are
sorted. Policy and toolchain fingerprints define comparison compatibility. Tool output is bounded and digested.
TST-04 snapshots the staged project after the test build, restores that same baseline before the second execution,
and requires both executions to have equal normalized output and equal project-state fingerprints. Only
lines whose normalized text begins with an elapsed-time, duration, timestamp, or `time:` presentation label are
omitted from output comparison; assertions that merely mention those words remain exact. The state fingerprint
combines source files with conventional `bin`, `obj`, coverage, library, and proof artifact trees, so runtime
artifact changes are visible. JSON member order is deterministic.
