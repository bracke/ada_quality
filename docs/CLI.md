# CLI reference

```
ada-quality project add PATH
ada-quality project list
ada-quality project show ID
ada-quality project enable|disable|remove ID
ada-quality check --all | --project ID [--json]
ada-quality status
ada-quality findings
ada-quality regressions
ada-quality history
ada-quality report --format json
ada-quality policy validate|show
ada-quality database init|check|recover
```

Global options are `--database PATH`, `--policy PATH`, `--no-color`, and `--color never`. Environment variables
`ADA_QUALITY_DATABASE` and `ADA_QUALITY_POLICY` provide defaults. JSON never contains ANSI styling.

Exit status meanings are:

- `0`: completed without violations;
- `1`: completed with quality violations;
- `2`: arguments or policy are invalid;
- `3`: assessment is incomplete, invalid, timed out, or hit a tool/system execution error;
- `4`: database, schema, locking, or integrity failure.

Incomplete evidence takes precedence over an ordinary quality-violation exit because the result cannot be treated as
a complete quality decision.
