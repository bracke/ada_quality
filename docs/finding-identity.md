# Finding identity

A fingerprint is a versioned, length-framed sequence of indicator, rule, project-relative source path, and redacted
message. Length framing makes delimiter characters inside any field unambiguous. Line is intentionally excluded,
so unrelated line-number movement does not change the occurrence identity. The source path is retained: identical
rule/message violations in two files are distinct findings and cannot mask one another. A deliberate file rename is
represented as resolution of the old-path occurrence and introduction of the new-path occurrence. A finding absent from the baseline is an
`introduced-finding` regression when no older compatible evidence contains it, or `reintroduced-finding` when it
returns after an absence. This comparison is independent of whether the enclosing indicator was already in violation.
Incomplete current assessments never establish resolution or a clean finding comparison.
History comparison maps a valid version-2 identity to its legacy delimiter-based alias only while matching older
persisted evidence. Exact version-2 identities remain the primary keys, and one legacy key cannot satisfy multiple
current findings.

`Ada_Quality.Finding_Identity` is the single codec used by checks, publication validation, integrity readers, and
history compatibility. Version-2 identities must decode to the same indicator, rule, path, and message as their
structured finding payload; contradictory evidence is rejected before publication and while reading a database.
New lossless evidence accepts only canonical version-2 identities. Delimiter-based identities remain confined to
legacy persisted evidence and one-way history compatibility, so delimiter ambiguity cannot enter new publications.
