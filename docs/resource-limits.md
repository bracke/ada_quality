# Resource limits

| Resource | Limit | Enforcement |
|---|---:|---|
| External process time | policy, maximum 3,600 seconds | GNU timeout plus five-second kill escalation and watchdog |
| Captured stdout + stderr | policy, maximum 16 MiB | streaming filter; excess discarded and marked truncated |
| Internal process buffer | 4 KiB | GNAT Expect `Buffer_Size` |
| Source-tree depth | 128 directories | traversal raises incomplete assessment error |
| Project entries | 100,000 files or links | traversal raises incomplete assessment error |
| Individual fingerprint input | 64 MiB | rejected before reading file content |
| Aggregate fingerprint input | 1 GiB | cumulative pre-read accounting |
| Policy source-line ceiling | maximum 1,000,000 | strict policy parser |
| Policy complexity ceiling | maximum 10,000 | strict policy parser |

Generated `.git`, `.alire`, object, binary, coverage, library, and proof directories are excluded from source identity.
Limits fail closed: an exceeded limit produces incomplete/error semantics, never compliance.
