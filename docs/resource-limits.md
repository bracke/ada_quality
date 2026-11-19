# Resource limits

| Resource | Limit | Enforcement |
|---|---:|---|
| External process time | policy, maximum 3,600 seconds | monotonic GNAT Expect deadline plus process-group TERM-to-KILL escalation |
| Captured stdout + stderr | policy, maximum 16 MiB | streaming filter; excess discarded and marked truncated |
| Complete-output byte count | signed 64-bit maximum | streaming accounting independent of retained output |
| Internal process buffer | 4 KiB | GNAT Expect `Buffer_Size` |
| Source/staging-tree depth | 128 directories or local-pin levels | traversal or staging fails closed |
| Project/staging entries | 100,000 files or links | traversal or staging fails closed |
| Project discovery entries/depth | 100,000 / 128 | discovery skips links/generated trees and fails closed |
| Individual source input | 64 MiB | rejected before reading file content |
| Aggregate source input | 1 GiB | cumulative pre-read accounting |
| Individual staged dependency input | 256 MiB | rejected before copying file content |
| Aggregate staged dependency input | 4 GiB | cumulative pre-copy accounting across the local-pin graph |
| Reporting projects/runs | 10,000 / 100,000 | snapshot scan limits |
| Reporting results/measurements | 2,000,000 each | independent snapshot scan limits |
| Reporting findings/executions/events | 2,000,000 each | independent snapshot scan limits |
| Aggregate reporting rows | 2,500,000 | cumulative snapshot accounting, including metadata |
| Aggregate reporting text | 256 MiB UTF-8 | cumulative accounting before rows enter the single canonical snapshot; typed assessments decode on demand |
| Integrity-check rows | 2,500,000 by default | cumulative accounting while the eight tables are scanned |
| Integrity-check text | 256 MiB UTF-8 by default | cumulative accounting before rows enter the integrity snapshot |
| Serialized archive JSON | 256 MiB by default | checked before every incremental output append; no archive DOM is built |
| Policy source-line ceiling | maximum 1,000,000 | strict policy parser |
| Policy complexity ceiling | maximum 10,000 | strict policy parser |

Generated `.git`, `.alire`, object, binary, coverage, library, and proof directories are excluded from source identity.
Limits fail closed: an exceeded limit produces incomplete/error semantics, never compliance.
