# Database migrations

New databases are version 4. Opening version 1 scans legacy assessment rows and converts legacy `source|policy`
payloads into named source/policy/toolchain fields. Versions 1 through 3 then advance to version 4 atomically.
Existing runs remain byte-identical; newly published runs record timestamps and use lossless escaped child payloads.
Version 4 adds validated append-only alias events without changing the eight-table layout. A migration commit fault
leaves the prior version intact for retry. Unknown versions fail closed.
