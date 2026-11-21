# Security policy

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Report it privately
to `bent@bracke.dk` with the affected version, reproduction steps, impact, and
any suggested mitigation. Avoid including real credentials or sensitive data.

The maintainer will acknowledge a report, investigate it, and coordinate a fix
and disclosure timeline. No response-time guarantee is currently offered.

## Supported versions

Security fixes are made on the current main branch and the latest published
release. Older releases may require upgrading to receive a fix.

## Scope

The database parser, project traversal, command execution boundary, report
renderers, and handling of untrusted repository contents are in scope.

## Artifact signing keys

Keep generated private signing keys outside repositories and shared artifact
directories. `database keygen` creates private keys with owner-only permissions
and refuses to overwrite existing key files. Verification is meaningful only
when the public key was obtained through a trusted channel.

`database trust add` records a public key under its SHA-256-derived Ed25519 identity. `database verify
--trust-store DIR` resolves the identity embedded in signed metadata and then performs full cryptographic
verification; inspection alone never establishes trust. Review `database trust list` and revoke obsolete identities
with `database trust remove`. Release archives additionally carry checksums, an SPDX SBOM, and provenance.
