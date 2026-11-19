# Ada Quality

[![CI](https://github.com/bracke/ada_quality/actions/workflows/ci.yml/badge.svg)](https://github.com/bracke/ada_quality/actions/workflows/ci.yml)

`ada-quality` is an Ada 2022 command-line assessor for registered local Alire projects. It records immutable,
versioned assessments in the sibling `database` engine and reports all 33 indicators defined in
[`quality-indicator-catalog.md`](quality-indicator-catalog.md).

The implementation separates tool execution from compliance. Missing, malformed, timed-out, or incomplete evidence
is blocked and never converted into a pass. Projects may be assessed concurrently with a bounded worker count;
database publication remains serialized and deterministic. External commands receive explicit argument vectors,
output is bounded, and the source fingerprint is checked after each full assessment.

## Build and test

```sh
alr build
(cd tests && alr build && alr exec -- ./bin/ada_quality_tests)
alr exec -- ./bin/coverage
alr exec -- ./bin/check_all
```

GNAT 15.2.1 is pinned through Alire. Local development and CI resolve the sibling crates into Alire's generated
workspace lock; the release manifest itself contains no local path pins.

GitHub Actions recreates the sibling-crate layout and runs the validation build, AUnit suite, complete coverage gate,
and release checker on pushes to `main` and on pull requests. See [`docs/continuous-integration.md`](docs/continuous-integration.md).

## Quick start

```sh
./bin/ada-quality database init
./bin/ada-quality project add /absolute/path/to/an/alire/crate
./bin/ada-quality project tag 1 ci
./bin/ada-quality doctor --project 1
./bin/ada-quality check --tag ci --dry-run --json
./bin/ada-quality check --all
./bin/ada-quality check --all --jobs 4 --reuse-unchanged
./bin/ada-quality check --all --reuse-unchanged --json --output reused.json
./bin/ada-quality history
./bin/ada-quality status --json
./bin/ada-quality assessment show 1 --format sarif
./bin/ada-quality assessment diff 1 2 --format json
./bin/ada-quality history --project 1 --status completed --limit 20 --json
./bin/ada-quality trend --project 1 --indicator TST-03 --json
./bin/ada-quality trend --project 1 --all --format csv
./bin/ada-quality scan --project 1 --changed-file src/example.adb
./bin/ada-quality scan --project 1 --files-from changed-files.txt
./bin/ada-quality scan --project 1 --git-diff origin/main
./bin/ada-quality scan --project 1 --staged --unstaged --untracked --output scan.txt
./bin/ada-quality explain SRC-03
./bin/ada-quality indicator list --category source --format json
./bin/ada-quality regressions --project 1 --fail-on-regression
./bin/ada-quality assessment alias release-1 1
./bin/ada-quality project discover /absolute/path/to/projects
./bin/ada-quality project sync /absolute/path/to/projects --remove-missing
./bin/ada-quality policy init --profile ci
./bin/ada-quality policy profiles
./bin/ada-quality policy effective --project 1 --profile ci
./bin/ada-quality database stats
./bin/ada-quality database archive history.export --before 2026-01-01T00:00:00Z --keep 10
./bin/ada-quality database archive --dry-run --before 2026-01-01T00:00:00Z --keep 10
./bin/ada-quality database merge other-quality.export
./bin/ada-quality waiver audit --project 1
./bin/ada-quality report --format json
./bin/ada-quality report --format html --output quality-report.html
```

The default database is `.ada-quality.db`; `ADA_QUALITY_DATABASE` or `--database` selects another path. The default
central policy is `quality-policy.toml`; `ADA_QUALITY_POLICY` or `--policy` selects another file.

Read commands accept `--output FILE`; collection views also accept `--limit N` and `--offset N`. Project tags can
select checks, status views, and reports. Structured source waivers require an owner, expiry date, and justification,
remain visible in findings, and stop suppressing violations after expiry.

See [`docs/CLI.md`](docs/CLI.md), [`docs/ASSESSMENT.md`](docs/ASSESSMENT.md), and
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for operational details. Development and disclosure guidance is in
[`CONTRIBUTING.md`](CONTRIBUTING.md) and [`SECURITY.md`](SECURITY.md).

`make install` installs the binary, manpage, JSON schemas, and generated Bash, Zsh, and Fish completions.
`make package` creates a self-contained binary archive under `dist/`.
