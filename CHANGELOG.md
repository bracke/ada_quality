# Changelog

All notable changes are recorded here. This project follows semantic versioning.

## Unreleased

- Bound all whole-file project metadata and changed-file list input, hash
  artifacts through one no-follow descriptor, and keep encoded private seeds
  out of immutable strings while securely wiping mutable key buffers.
- Generated complete accepted-option help from CLI metadata and split the
  command router and remaining handlers into focused subunits.
- Fixed tag-selected JSON checks to emit one batch document and guaranteed that
  started assessments are interrupted if scheduling or publication unwinds.
- Bounded every staged artifact entry, removed partial staging trees on failure,
  and moved secure descriptor operations behind a header-derived POSIX shim.
- Applied JSON Schema sibling constraints beside `$ref`, resolved safe
  external reference fragments, and bounded reference depth in contract tests.
- Changed CLI validation to reject options outside their command scope, bound
  pagination cursors to their originating queries, and made JSON contract
  validation fail closed on unsupported schema keywords.
- Centralized CLI validation/help/completion metadata, separated command DTOs
  from JSON rendering, bounded descriptor-based key/signature reads, and made
  application/package versions derive from Alire's generated crate version.
- Prevented below-threshold or source-changing coverage runs from publishing
  evidence, and made the instrumented release-check probe capture diagnostics.
- Fixed batch doctor JSON so global checks are reported and counted once, and
  split database and policy command routers into focused handlers.
- Added structured JSON errors and JSON parity for policy, project, regression, and database administration commands.
- Added portfolio doctor/waiver thresholds, snapshot-bound cursors, and per-project policy impact analysis.
- Added atomic multi-source merge planning and key-ID-based artifact trust stores with inspect/list/revoke workflows.
- Added tag-driven release packaging with checksums, SPDX SBOMs, provenance attestations, and release assets.
- Added JSON reuse reports, file output parity, policy management, and dynamic shell completion.
- Added verified archive-before-prune retention and staged, unstaged, and untracked Git scan modes.
- Added diagnostics and no-write check plans, expiring owned waivers, project tags, retention previews, paged output,
  and verified database merging.
- Added Ed25519 signing and trusted-key verification for physical backups and logical exports.

- Added historical metric trends and JSON trend output.
- Added SARIF and JUnit exports for stored assessments.
- Added changed-source preflight scanning and indicator explanations.
- Added project relocation with stable identities and retained history.
- Added verified physical backup, restore, and native logical export commands.
- Added portfolio status reports and a regression-only CI gate.
- Added changed-file list input, indicator catalog discovery, and bounded local project discovery.
- Added database resource statistics and append-only human-readable assessment aliases.
- Added bounded parallel and unchanged-assessment reuse workflows.
- Added named policy profiles and partial per-project policy overlays.
- Added filtered findings JSON/SARIF, Git-derived changed-file scans, and registry synchronization.
- Added logical database import, standalone HTML reports, richer completions, and install/package tooling.

## 0.1.0

- Initial 33-indicator assessment engine, persistent registry, immutable history,
  regression reporting, JSON archives, and release verification.
