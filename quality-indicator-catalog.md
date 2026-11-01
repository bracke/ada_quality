# Quality Indicator Catalog v1.0

All projects use one central policy; every indicator has stable ID/version, prerequisites, applicability, measurement/evidence contract, pass/fail/blocked semantics and AUnit fixtures.

| ID | Indicator |
|---|---|
| STR-01 | Alire manifest |
| STR-02 | GPR structure |
| STR-03 | Standard layout |
| STR-04 | Test subcrate |
| STR-05 | Release tooling |
| BLD-01 | Compilation |
| BLD-02 | Validation build |
| BLD-03 | Compiler warnings |
| BLD-04 | Toolchain |
| TST-01 | AUnit execution |
| TST-02 | Test registration |
| TST-03 | Line coverage >=90% |
| TST-04 | Test determinism |
| SRC-01 | Formatting |
| SRC-02 | Naming |
| SRC-03 | Defined Ada decision complexity |
| SRC-04 | Source hygiene |
| SRC-05 | Exception handling |
| SRC-06 | Source size |
| DOC-01 | Public API documentation |
| DOC-02 | GNATdoc generation |
| DOC-03 | Required documentation |
| DEP-01 | Dependency resolution |
| DEP-02 | Local pins |
| DEP-03 | Dependency consistency |
| SEC-01 | Embedded secrets |
| SEC-02 | Process execution safety |
| SEC-03 | Artifact hygiene |
| REL-01 | Release checker |
| REL-02 | License consistency |
| REL-03 | Release manifest |
| REL-04 | Clean staging |
| PRF-01 | SPARK proof verification |

**33 indicators total.**

Implementation mapping: STR via Project_Tools.Alire_Manifests/Files/Tree_Checks and verified GPR tooling; BLD via Alire/GNAT; TST via AUnit, Project_Tools.AUnit_Checks and Project_Tools.Gcov; SRC via Ada-aware lexical/semantic analysis and Project_Tools.Ada_Source; DOC via GNATdoc and documentation inventory; DEP via Alire/manifest checks; SEC via bounded scanning and source analysis; REL via standard checker and clean staging; PRF via GNATprove.

Coverage independently enumerates every production unit, reconciles each unit with instrumented output, and uses exact overflow-safe count comparison; zero eligible lines or a missing instrumented unit cannot pass. 90%=9000 basis points. GNATprove legality is not proof discharge. Release checker presence alone is not execution evidence. Never infer success from missing/partial evidence.

Tests: valid, invalid, boundary, malformed, missing prerequisite, tool failure and deterministic output for each applicable indicator.
