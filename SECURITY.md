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
