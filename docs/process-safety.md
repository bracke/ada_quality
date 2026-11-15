# Process safety

GNAT Expect supplies a monotonic deadline and five-second TERM-to-KILL cleanup. Each tool runs in a dedicated POSIX session, and escalation targets the complete process group. Spawn failure and timeout are blocked evidence; signal and nonzero termination cannot pass. Tests cover a TERM-resistant descendant, a missing command, timeout, a legitimate exit code 124, internal-buffer flood, complete-output digesting across truncated prefixes, stderr, signal termination, hostile directories, and shell metacharacters passed literally.
