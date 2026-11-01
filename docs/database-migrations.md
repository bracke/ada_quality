# Database migrations

New databases are version 3. Opening version 1 scans legacy assessment rows and converts legacy `source|policy`
payloads into named source/policy/toolchain fields. Versions 1 and 2 then advance to version 3 atomically. Existing
runs remain legacy evidence; newly published runs record timestamps and use lossless escaped child payloads. A
migration commit fault leaves the prior version intact for retry. Unknown versions fail closed.
