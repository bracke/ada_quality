# AQ-009 security review

The process, filesystem, policy, evidence, JSON, and persistence boundaries were inspected.

Confirmed controls:

- child tools receive explicit argument vectors and are never invoked through a shell;
- the child environment is rebuilt from a small allowlist;
- GNU `timeout` supplies forced termination and GNAT Expect supplies an independent watchdog;
- output is bounded while streaming, and persisted execution evidence stores digests and counts rather than output;
- source and staged dependency traversal reject symbolic links and escaping local paths;
- cleanup removes links without following them;
- coverage must be complete and match both the current source and selected toolchain fingerprints;
- JSON uses jsonlib and contains no terminal styling;
- database terminal publication is transactional and immutable.

## AQ9-001 — resolved private scratch isolation

`Ada_Quality.Temporary_Directories` atomically allocates process-and-counter-qualified directories and applies mode
0700. Assessment staging and GNATdoc output are children of that directory. Coverage objects, executables, policy
fixtures, and databases are children of a separate private directory.

Tests prove that two workspaces with the same identity coexist without shared files and that cleanup of one leaves the
other intact. Project-root symlinks are rejected before canonicalization. Coverage additionally holds an atomic
workspace lock, so a second driver exits immediately with an explicit conflict rather than sharing instrumentation or
database state.
