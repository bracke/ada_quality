# Process execution

`Ada_Quality.Execution` resolves an executable, passes an explicit argument vector, runs in a selected directory,
clears the environment, restores an allowlist, merges bounded stdout/stderr, and wraps execution with an enforced
timeout and kill-after interval. Arguments never pass through a command shell. Spawn failure, timeout, nonzero exit,
truncation, and signal termination remain distinct evidence. Exit-status-only indicators may pass after a successful
command even when its presentation output was truncated. Indicators that inspect diagnostics or compare output require
complete capture; truncation blocks BLD-04, DOC-01, DOC-02, TST-04, and REL-04.
