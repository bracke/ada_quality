# Process execution

`Ada_Quality.Execution` resolves an executable, passes an explicit argument vector, runs in a selected directory,
clears the environment, restores an allowlist, starts a dedicated POSIX session, merges bounded stdout/stderr, and
wraps execution with an enforced timeout and kill-after interval. TERM and KILL target the complete process group, so
launcher descendants cannot survive a deadline. Arguments never pass through a command shell. Spawn failure, timeout, nonzero exit,
truncation, and signal termination remain distinct evidence. Exit-status-only indicators may pass after a successful
command even when its presentation output was truncated. Indicators that inspect diagnostics or compare output require
complete capture; truncation blocks BLD-04, DOC-01, DOC-02, TST-04, and REL-04. Persisted command evidence retains the
resolved executable and option/argument shape while replacing positional and attached option values with placeholders.
A streaming FNV-1a digest and 64-bit total byte count cover complete combined stdout and stderr even when retained
diagnostic text is truncated. Timeout classification comes from the monitor deadline, never from a child exit-code convention.
A process-wide gate serializes GNAT Expect spawn, monitor, and close operations when multiple tasks call the API.
