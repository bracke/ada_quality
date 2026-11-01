# Build indicators

BLD-01 runs an Alire build and BLD-02 runs a forced validation build. BLD-03 performs a separate forced validation build with `ADA_QUALITY_WARNINGS_AS_ERRORS=true`; the root GPR then appends `-gnatwe` only to the assessed project, so dependency-project warnings neither pass for the assessed project nor create false failures. A compiler fixture verifies that an intentional project warning fails under the same warning-as-error policy. BLD-04 queries the selected GNAT toolchain and requires successful output that identifies GNAT.
