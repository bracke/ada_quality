# Tool registry

`Ada_Quality.Tools` fixes program identities for Alire, GNATls, AUnit, gcov, GNATdoc, GNATprove, Git, and the release checker. It prevents ad-hoc command naming in adapters. Tool executions persist label, resolved executable plus a redacted argument-shape summary, status, exit code, output digest/size, and truncation. A successful, complete GNAT identity query supplies the toolchain compatibility fingerprint; failed, truncated, or structurally blocked queries use the explicit unavailable identity.
