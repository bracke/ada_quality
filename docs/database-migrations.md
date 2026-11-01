# Database migrations

New databases are version 2. Opening version 1 scans legacy assessment rows, converts legacy `source|policy` payloads into named source/policy/toolchain fields, updates metadata, and commits atomically. A migration commit fault leaves version 1 intact for retry. Unknown versions fail closed.
