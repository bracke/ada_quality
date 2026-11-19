# Database migrations

New databases are version 5. Opening version 1 scans legacy assessment rows and converts legacy `source|policy`
payloads into named source/policy/toolchain fields. Versions 1 through 4 then advance to version 5 atomically.
Existing runs remain byte-identical; newly published runs record timestamps and use lossless escaped child payloads.
Version 4 adds validated append-only alias events without changing the eight-table layout. A migration commit fault
leaves the prior version intact for retry. Version 5 converts raw project paths to canonical path-and-tag payloads;
existing projects receive an empty tag set. Unknown versions fail closed.
