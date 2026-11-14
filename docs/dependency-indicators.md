# Dependency indicators

DEP-01 and DEP-03 have separate evidence contracts. DEP-01 reuses the staged
Alire build and passes only when Alire resolves the project and the resolved
project builds. DEP-03 then parses the generated `alire/alire.lock`
structurally. It requires a solved solution and exactly one matching lock entry
for every top-level `[[depends-on]]` declaration, including the declared
version constraint. Additional lock entries may represent transitive
dependencies and are not rejected. A missing, duplicate, or mismatched direct
requirement is a violation; missing or malformed lock evidence blocks DEP-03.
This lets resolution succeed while a stale or inconsistent manifest/lock pair
fails consistency independently.

DEP-02 is a native release-policy check and remains a violation when the
development manifest contains local paths, even though the isolation layer
safely stages them.

Manifest `project-files` and `executables` discovery is also structural:
only arrays assigned before the first TOML table are treated as top-level
Alire declarations. Same-named keys inside tables are ignored and declaration
order is preserved.
