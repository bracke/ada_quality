# Contributing

Contributions should be small, reviewable, and backed by tests. Open an issue
before making a large behavioral or persistence-format change.

## Development workflow

Use the pinned Alire toolchain and run the complete local checks:

```sh
alr build
(cd tests && alr build && alr exec -- ./bin/ada_quality_tests)
alr exec -- ./bin/coverage
alr exec -- ./bin/check_all
```

Keep public APIs documented, add regression tests for changed behavior, and do
not weaken fail-closed handling of missing or incomplete evidence. Update the
CLI reference and changelog when user-visible behavior changes.

Commits should explain why a change is needed. Pull requests should summarize
the design, validation performed, and any compatibility or migration impact.
