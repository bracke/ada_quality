# Tool registry

`Ada_Quality.Tools` fixes program identities for Alire, GNATls, AUnit, gcov, GNATdoc, GNATprove, Git, and the release checker. It prevents ad-hoc command naming in adapters. Tool executions persist label, resolved command identity, status, exit code, output digest/size, and truncation; the GNAT output digest is the toolchain compatibility fingerprint.
