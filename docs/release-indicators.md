# Release indicator contracts

REL-02 compares the `licenses` SPDX expression in the canonical `alire.toml` with `LICENSE` or `LICENSE.md`.
Expressions may use parentheses and the SPDX `AND`, `OR`, and `WITH` operators. The evidence recognizer currently
supports the license identifiers used by the standardized project set: `MIT`, `Apache-2.0`, `BSD-3-Clause`, and
`CC0-1.0`, plus `LLVM-exception`. A matching explicit SPDX declaration or recognized canonical license contents
passes. A known conflicting license is a violation, missing declaration/file evidence is a violation, and malformed,
unknown, or otherwise unverifiable evidence is blocked; none of those conditions can pass.

REL-03 defines `alire.toml` itself as the release manifest; Ada Quality does not require a second `manifest.json`.
The release contract requires nonempty `name`, `version`, `description`, and `licenses` strings plus nonempty
`authors` and `maintainers` arrays. This is deliberately stronger and more release-oriented than STR-01's basic crate
identity check.
