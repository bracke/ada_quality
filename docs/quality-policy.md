# Quality policy

One strict root-level TOML policy applies to all projects. Supported keys set coverage basis points, source line and complexity limits, process timeout, output limit, and clean-worktree requirement. Sections and unsupported keys are rejected; missing files, duplicate keys, malformed values, and unsafe limits fail loading. Inline TOML comments are accepted. The canonical fingerprint is deterministic and is persisted with every run.
