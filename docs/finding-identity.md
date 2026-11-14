# Finding identity

A fingerprint is indicator, rule, project-relative source path, and redacted message. Line is intentionally excluded,
so unrelated line-number movement does not change the occurrence identity. The source path is retained: identical
rule/message violations in two files are distinct findings and cannot mask one another. A deliberate file rename is
represented as resolution of the old-path occurrence and introduction of the new-path occurrence. A finding absent from the baseline is an
`introduced-finding` regression when no older compatible evidence contains it, or `reintroduced-finding` when it
returns after an absence. This comparison is independent of whether the enclosing indicator was already in violation.
Incomplete current assessments never establish resolution or a clean finding comparison.
