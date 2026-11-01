# Process safety

GNU timeout supplies the deadline and five-second kill-after cleanup. A controller watchdog prevents indefinite capture. Spawn failure and timeout are blocked evidence; signal and nonzero termination cannot pass. Tests cover a missing command, timeout, internal-buffer flood, stderr, signal termination, hostile directories, and shell metacharacters passed literally.
