# Build indicators

BLD-01 runs an Alire build and BLD-02 runs a forced validation build. BLD-03 resolves every root project listed by
the Alire manifest, falling back to the crate-named GPR only when that list is absent. For each root it generates an
extending project that retains the root project's effective Ada switches and appends all-warnings plus
warnings-as-errors, then performs a forced build in the selected Alire environment. Dependency-project compiler
packages are not changed. A standalone fixture verifies both preservation of an inherited compiler switch and
rejection of an intentional target warning. BLD-04 queries the selected GNAT toolchain and requires successful
output that identifies GNAT.
