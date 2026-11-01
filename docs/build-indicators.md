# Build indicators

BLD-01 runs an Alire build, BLD-02 a forced validation build, BLD-03 applies the compiler warning gate to that validation result, and BLD-04 queries the selected GNAT toolchain. BLD-04 requires successful output that identifies GNAT; exit zero without that content is blocked.
