# AQ-009 remediation plan

Status: **complete**, verified 2026-11-01.

## Before parallel or shared-host execution

1. [x] Replace project-ID and fixed `/tmp` names with one private per-invocation directory created atomically with owner-only
   permissions. Derive assessment staging, GNATdoc output, and coverage database paths from it.
2. [x] Add a regression test that starts two assessments with the same project ID in distinct databases and proves their
   workspaces and documentation outputs cannot collide.
3. [x] Add an explicit inter-process coverage lock with a clear diagnostic and verify overlapping invocation rejection.

## Before relying on a narrow coverage ratchet

1. [x] Add deterministic branch tests until stable production coverage is at least 92% (measured 92.04%).
2. [x] Run the coverage gate repeatedly in clean disposable workspaces and fail a new stability test when covered-line
   counts vary for the same source fingerprint and toolchain.
3. [x] Record and enforce the toolchain fingerprint in the coverage artifact.

## Documentation warning remediation

1. [x] Separate project GNATdoc output from transitive dependency projects with portable GPR configuration.
2. [x] Document every project-owned public entity, enumeration literal, record field, parameter, and return value.
3. [x] Verify `gnatdoc --warnings` exits zero with an empty diagnostic log.

AQ9-001, AQ9-002, and AQ9-003 are closed. No remediation item remains.
