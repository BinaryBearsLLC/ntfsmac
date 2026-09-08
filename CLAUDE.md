# Development instructions

AGENTS.md points here so there is only one set of agent instructions.
Start with [CONTRIBUTING.md](CONTRIBUTING.md). Read the relevant guide before editing:
[architecture](docs/dev/PLAN.md), [GUI behavior](docs/dev/GUI-PLAN.md),
[tests](docs/dev/TESTING.md), [dependencies](docs/dev/ANYLINUXFS_UPDATE_POLICY.md),
or [releases](docs/RELEASE.md).

## Preserve these boundaries

- Apple Silicon only; the 3.1.3 target is macOS 14+. Guard newer APIs and check every
  shipped host executable's minimum OS. Compilation is not older-OS runtime validation.
- App-initiated privileged operations use the reviewed XPC helper. Never add raw
  `sudo`, mount, PF or route mutations to SwiftUI code.
- Validate partition identifiers against `^disk[0-9]+s[0-9]+$` before execution,
  independently in the client and helper. Never infer NTFS from partition-map type.
- Keep ntfs-3g as default, NTFS3 explicitly experimental, NFS `soft`, and the current
  vmnet transport. Do not introduce SMB, loopback transport or unsafe RW overrides.
- Missing evidence stays unknown. A healthy diagnostic is not proof of runtime boot,
  data integrity, effective isolation, or hardware compatibility.
- Standard uses SMAppService. Retain Legacy source for migration tests, not distribution.
- Preserve existing UI design, one-time notices, and Command-click Diagnose export.
  Do not add duplicate Settings controls or automatic diagnostic uploads.

## Dependencies and signing

Use only the sources, exact commits and hashes in `build/sources.lock` and the
associated manifests. Audit one dependency change at a time; verify transitive
requirements before trimming. Do not fetch init-freebsd or build FreeBSD guest binaries.
Retained feature decisions and package justifications are in `build/AUDIT.md`.

Local/contributor builds may be ad-hoc. Official builds use the dedicated BinaryBears
Developer ID/notarization path. Never weaken signature requirements or change
entitlements to make a test pass. Credentials stay outside Git and logs.

## Working safely

- Preserve unrelated local changes. Use small, reviewable commits and update the
  relevant existing guide instead of creating another session diary.
- Run CLI/runtime checks before packaging the GUI. Do not run packaging tests and
  real packaging concurrently: both generate the embedded CLI manifest.
- Report automated, native hardware, VM, signing/notarization and remote results separately.
- Real-disk formatting/corruption tests require explicit device-specific authorization
  and fresh identity checks. Do not touch other attached media.
- Ask before destructive Git operations, unapproved privilege/signing changes, or
  publication not explicitly requested by the owner. Never rewrite published history.

## Repository roles

`origin` is BinaryBearsLLC/ntfsmac; `upstream` is khr898/ntfsmac. Keep `main` as the
upstream mirror and BinaryBears integration on `dev`. Preserve `3.1.2` as rollback;
3.1.3 work belongs on `Update/3.1.3` until approved integration. Upstream proposals
are separate and must not include fork-only branding or product policy.
