# Ada Quality

`ada-quality` is an Ada 2022 command-line assessor for registered local Alire projects. It records immutable,
versioned assessments in the sibling `database` engine and reports all 33 indicators defined in
[`quality-indicator-catalog.md`](quality-indicator-catalog.md).

The implementation separates tool execution from compliance. Missing, malformed, timed-out, or incomplete evidence
is blocked and never converted into a pass. Projects are assessed sequentially, external commands receive explicit
argument vectors, output is bounded, and the source fingerprint is checked after each full assessment.

## Build and test

```sh
alr build
(cd tests && alr build && ./bin/ada_quality_tests)
alr exec -- ./bin/coverage
./bin/check_all
```

GNAT 15.2.1 is pinned through Alire. The committed lockfile retains the resolved sibling-crate workspace links;
the release manifest itself contains no local path pins.

## Quick start

```sh
./bin/ada-quality database init
./bin/ada-quality project add /absolute/path/to/an/alire/crate
./bin/ada-quality check --all
./bin/ada-quality history
./bin/ada-quality report --format json
```

The default database is `.ada-quality.db`; `ADA_QUALITY_DATABASE` or `--database` selects another path. The default
central policy is `quality-policy.toml`; `ADA_QUALITY_POLICY` or `--policy` selects another file.

See [`docs/CLI.md`](docs/CLI.md), [`docs/ASSESSMENT.md`](docs/ASSESSMENT.md), and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for operational details.
