# Dependency refresh evidence — 2026-08-30

This ledger records the controlled dependency refresh on
`maintenance/dependency-refresh-2026-08`. Each dependency is changed and validated in its own
checkpoint. GitHub issue #24 remains isolated in its original task and is not included here.

## Repository boundary

- Worktree: `/Users/andrea/.codex/worktrees/7409/ntfsmac`
- Starting commit: `416cb2e1281270e3b7cb67fa1ecf4ca4db3dbf82` (`dev`, `origin/dev`, `v3.1.1`)
- Starting state: clean detached worktree; the dedicated branch was created before edits
- anylinuxfs submodule: clean at `8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3`
- Publication boundary: no push, release, deployment, or remote mutation is authorized

## Baseline before dependency work

| Gate | Result |
|---|---|
| `./build/preflight.sh` | PASS |
| `./tests/run-all.sh` | PASS, 336/336 |
| modern Swift suite | PASS, 307/307 |
| Legacy Swift suite | PASS, 307/307; expected SMJobBless deprecation warnings only |
| AppKit render suite | Not executed on macOS 26.6.2; skipped by the documented hang guard |
| real drives / destructive media tests | Not run |

The baseline used the real Rust, Go, Swift, signing, packaging-fixture, and vendored-runtime paths.

## Checkpoint A — Alpine package reproducibility, no version update

Status: implementation and local source gates complete.

The previous direct-package list was not a transitive lock: `apk add` resolved dependencies from
the live v3.23 indexes. This checkpoint adds:

- an exact 16-package base manifest tied to the immutable Alpine OCI digest;
- an exact 54-package add-on closure;
- a 54-entry APK artifact manifest with channel plus SHA-256;
- runtime revision 4 with all aggregate hashes in its cache identity and marker;
- local, SHA-verified APK installation with `apk --no-network`;
- fail-closed rejection of custom packages, malformed entries, changed hashes, and incomplete
  runtime markers.

No component version changed. In particular, all three `ntfs-3g` packages remain
`2026.2.25-r0`; the security update is the next isolated checkpoint.

Evidence collected:

- all 54 recorded APKs were fetched from official Alpine paths and matched SHA-256;
- targeted static/runtime/diagnostic gates: PASS, 70/70;
- rootfs build gate after exact-manifest regression coverage: PASS, 7/7;
- complete Bats gate after fixture correction and exact-manifest hardening: PASS, 350/350;
- modern Swift gate: PASS, 307/307;
- Legacy Swift gate: PASS, 307/307, with expected SMJobBless deprecation warnings only;
- generated `vm-setup.sh` contains the exact version and artifact manifests, no `apk --update`,
  no floating repository install, and no malformed Go `fmt` output;
- real `init-rootfs` Rust/Go build and ad-hoc hypervisor entitlement: PASS;
- an initial full-suite run exposed only stale synthetic test locks/markers; those fixtures were
  updated and the affected targeted suites passed.

Known gate: the local VM launch returns `start vm error: Invalid argument (errno 22)` before guest
setup. The exact installation command and resulting installed package database are therefore not
claimed as hardware-validated yet. The build reports this explicitly instead of treating it as an
installed-package pass.

## Validation categories

- Local source/build/tests: checkpoint A passed 350/350 Bats plus 307/307 in each Swift variant.
  `PopoverStateRenderTests` compiled but remained skipped by the documented macOS 26.6.2 guard.
- Hardware: no real-drive test; local VM guest setup blocked as documented above.
- Signing: ad-hoc local signatures and required hypervisor entitlement only.
- Notarization: not run.
- Remote/public state: untouched; no push or release.
