# JSON schemas

`assessment.schema.json` constrains report identity, fingerprints, terminal state, exactly 33 results, measurements, findings, and executions. `archive.schema.json` requires all eight persisted logical collections plus derived regressions with project/baseline/current IDs. Both declare JSON Schema draft 2020-12 and disallow unknown top-level members.
