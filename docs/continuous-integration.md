# Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main`, pull requests, and manual dispatch. The job uses Alire 2.1.0,
the manifest-selected GNAT 15.2.1 toolchain, and read-only GitHub permissions.

Ada Quality depends on sibling crates that are developed as separate repositories. CI checks out `database`,
`project_tools`, `jsonlib`, `terminal_styles`, `messages`, `regexp`, `i18n`, and `cryptolib` beside `ada_quality`.
It asks Alire to resolve the six direct dependencies through those paths, then restores the release manifest before
building. The AUnit child crate receives its own generated lock containing AUnit and the same transitive overrides.
Automatic re-resolution is disabled locally after each generated lock is complete, so restoring the two tracked
manifests does not discard those links. `database` and `messages` resolve their transitive sibling pins to `cryptolib`
and `i18n` respectively. If the AUnit action fails, CI prints Alire's otherwise private local-test log.

The required gates are:

1. `alr -n build --validation -- -f`
2. `alr -n test`
3. `alr -n exec -- ./bin/coverage`
4. `./bin/check_all`
5. `git diff --exit-code`

The final check proves that generated coverage and stability evidence already matches the reviewed source and selected
toolchain. The job has a 45-minute timeout, and a newer run on the same branch cancels an older in-progress run.
