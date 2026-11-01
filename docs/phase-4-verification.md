# AQ-004 verification

Current reconstruction, 2026-10-29. Fake/standard process fixtures cover timeout, spawn failure, signal, stderr, output bounds, hostile arguments, environment isolation, and cleanup. Workspace fixtures cover copied sources, excluded outputs, recursive pins, links, and traversal escape. The integrated E2E path invokes real Alire/GNAT/AUnit/GNATdoc in the staged project.
