# External execution

The adapter resolves commands, preserves explicit argv boundaries, applies a selected working directory, starts a nonblocking child, streams combined output through a fixed buffer, and returns status, exit code, bounded output, truncation, and a non-secret command identity. Assessment persistence records every actual invocation separately.
