# Continuous integration

`.github/workflows/ci.yml` runs on pushes to `main`, pull requests, and manual dispatch. The job uses Alire 2.1.0,
the manifest-selected GNAT 15.2.1 toolchain, and read-only GitHub permissions.

Ada Quality depends on sibling crates that are developed as separate repositories. CI checks out `database`,
`project_tools`, `jsonlib`, `terminal_styles`, `messages`, `regexp`, `i18n`, and `cryptolib` beside `ada_quality`.
Every checkout uses an immutable commit ID recorded in the workflow; dependency upgrades are therefore explicit
workflow changes rather than changes inherited from a sibling's moving default branch. CI asks Alire to resolve the
six direct dependencies through those paths, then restores the release manifest before building. The AUnit child
crate receives its own generated lock containing AUnit and the same transitive overrides.
Automatic re-resolution is disabled locally after each generated lock is complete, so restoring the two tracked
manifests does not discard those links. `database` and `messages` resolve their transitive sibling pins to `cryptolib`
and `i18n` respectively. CI builds the child test crate without executing it; the release checker then launches the
binary once from the root Alire environment, where the selected compiler and GPRbuild remain available to
process-level fixtures.

The required gates are:

1. `alr -n build --validation`
2. `alr -n -C tests build`
3. `ADA_QUALITY_INTERNAL_COVERAGE_OUTPUT_DIR=$RUNNER_TEMP/ada-quality-coverage alr -n exec -- ./bin/coverage`
4. `alr -n exec -- ./bin/check_all`
5. `git diff --exit-code`

CI writes its independently measured coverage evidence to a runner-local directory. This enforces the complete
coverage threshold without replacing the reviewed artifacts with environment-specific branch counts. The release
checker still proves that the tracked artifact matches the portable source identity and performs the one regular
AUnit execution; the instrumented suite remains part of the coverage gate. Source-keyed Alire, object, library, and
binary caches make unchanged rebuilds incremental without allowing artifacts from a different source or dependency
revision. The final check rejects tracked mutations. The job has a 45-minute timeout, and a newer run on the same
branch cancels an older in-progress run.

`.github/workflows/release.yml` runs for version tags (or an explicitly selected existing tag). It repeats the
validation and test gates, builds the self-contained package, writes SHA-256 checksums, generates an SPDX JSON SBOM,
attests the archive and SBOM with GitHub's OIDC-backed artifact attestation service, and publishes all assets to the
tag's GitHub release. The tag must exactly match the version in `alire.toml`.
