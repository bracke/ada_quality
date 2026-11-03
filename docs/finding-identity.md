# Finding identity

A fingerprint is indicator, rule, relative semantic path context, and redacted message. Line is intentionally excluded.
Historical matching also compares a semantic key that removes the path component, allowing a finding to retain
identity across a file rename when its indicator/rule/message remain stable. A finding absent from the baseline is an
`introduced-finding` regression when no older compatible evidence contains it, or `reintroduced-finding` when it
returns after an absence. This comparison is independent of whether the enclosing indicator was already in violation.
Incomplete current assessments never establish resolution or a clean finding comparison.
