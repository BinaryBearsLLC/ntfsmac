# Dependency refresh evidence — 2026-08-30

This ledger records the controlled dependency refresh on
`maintenance/dependency-refresh-2026-08`. Each dependency is changed and validated in its own
checkpoint. GitHub issue #24 remains isolated in its original task and is not included here.

## Repository boundary

- Worktree: `/Users/andrea/.codex/worktrees/7409/ntfsmac`
- Starting commit: `416cb2e1281270e3b7cb67fa1ecf4ca4db3dbf82` (`dev`, `origin/dev`, `v3.1.1`)
- Starting state: clean detached worktree; the dedicated branch was created before edits
- anylinuxfs baseline submodule: clean at `8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3`
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

## Checkpoint B — ntfs-3g 2026.7.7-r0 security update

Status: implementation and local source gates complete.

Only `ntfs-3g`, `ntfs-3g-libs`, and `ntfs-3g-progs` changed, from `2026.2.25-r0` to
`2026.7.7-r0`. Stable Alpine v3.23/v3.24 did not yet carry the patched build, so the three APKs
are byte-pinned to `edge/main`; runtime validation rejects edge for every other package and the
guest never enables an edge repository.

Provenance and compatibility evidence:

- Tuxera source SHA-256:
  `d67b769025d32860549d35c2147e45024d172f81c540d750390ce3602c059dab`;
- Alpine aports commit: `905147fb282a60cd622b45c7421db8a116cf80ab`;
- all three APKs are aarch64, share the same origin/build commit, contain an Alpine RSA signature
  envelope, and match their recorded SHA-256;
- driver and utilities now require `libntfs-3g.so.90`; the libraries package provides SONAME 90;
- `ntfs-3g.probe` and `ntfsinfo` remain packaged.

Validation:

- focused Alpine/APK/diagnostic Bats gate: PASS, 46/46;
- rootfs/runtime Bats gate: PASS, 26/26;
- complete Bats gate: PASS, 355/355;
- focused modern and Legacy `DiagnoseRunnerTests`: PASS, 21/21 each; Legacy emitted only the
  expected SMJobBless deprecation warnings;
- real arm64 container, Alpine OCI digest pin, `--network none`, APK cache read-only:
  `apk --no-network` PASS, exact 70-package database PASS, `ntfs-3g --version` = 2026.7.7,
  `ntfsinfo --version` = 2026.7.7, SONAME/link resolution PASS;
- no volume was mounted and no real disk was accessed.

Native hardware gate: the project's libkrun VM still fails before guest setup with
`start vm error: Invalid argument (errno 22)`. Therefore the Docker-isolated guest execution is a
local compatibility pass, not a claim that the packaged native VM or a real NTFS drive passed.

## Checkpoint C — anylinuxfs v0.19.0

Status: local source/build validation complete; hardware acceptance outstanding.

The submodule moved from `8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3` to the official v0.19.0
release commit `28d308bb9ed15611118fa51d998b988b3ee62459`. `ANYLINUXFS_VERSION` and
`VMPROXY_VERSION` moved together from 0.18.0 to 0.19.0. No other top-level pin changed.

- read-only preflight: four commits, twelve manifest/lock files, no implementation source,
  Alpine manifest, download contract, libkrun pin, mount/NFS/vmnet path, or local patch marker;
- focused policy/lock/submodule gate: PASS, 12/12; build preflight: PASS;
- real build: PASS for arm64 anylinuxfs, static Linux/aarch64 vmproxy, init-rootfs, and
  vmrunner-sys; `anylinuxfs --version` reports 0.19.0;
- Cargo tests: PASS, 58/58 across common-utils (8), anylinuxfs (41), and vmproxy (9);
- Go compilation: PASS for init-rootfs on Darwin and freebsd-bootstrap cross-compiled for
  FreeBSD/arm64; the latter is intentionally not a Darwin binary;
- local artifact checks: arm64 architectures PASS, static libblkid PASS, hypervisor entitlement
  present, ad-hoc signature present, quarantine absent;
- advisory comparison: `cargo-audit 0.22.2` and `govulncheck 1.7.0` report the same findings on
  the old pin and v0.19.0. This is no regression, but not a clean security scan. The separately
  available upstream gRPC fix, Go 1.26.6 toolchain fix, and Rust transitive findings are kept out
  of this checkpoint.
- complete Bats gate: PASS, 355/355;
- `build.command gui`: PASS on the exact candidate; Standard Swift 307/307 and Legacy Swift
  307/307 (expected SMJob deprecation warnings only), both apps and both DMGs built, both DMG
  checksums verified, and local Developer ID signatures verified. `PopoverStateRenderTests`
  compiled but remained skipped by the documented macOS 26.6.2 guard.

Native VM startup again returned `EINVAL` before guest setup. No disk was mounted or accessed.
No notarization, installation, push, or publication was performed.

## Checkpoint D — init-rootfs gRPC 1.82.1

Status: local source/build validation complete; hardware acceptance outstanding.

The anylinuxfs submodule moved one upstream commit from the accepted v0.19.0 release commit
`28d308bb9ed15611118fa51d998b988b3ee62459` to
`0a4472bd7507c1f9a57894547c1af7ea4382d99f`. The exact delta changes only
`init-rootfs/go.mod` and `init-rootfs/go.sum`, updating `google.golang.org/grpc` from `1.81.1`
to `1.82.1`. `ANYLINUXFS_VERSION`, `VMPROXY_VERSION`, libkrun, Alpine, and every other top-level
pin are unchanged.

- read-only update audit: PASS; one commit, two dependency files, no implementation-source,
  Alpine-list, download-contract, mount/NFS/vmnet-path, or local-patch change;
- focused policy/lock/submodule gate: PASS, 12/12; build preflight: PASS;
- `go test ./...` for `init-rootfs`: PASS;
- complete runtime build: PASS; Cargo tests: PASS, 58/58;
- advisory comparison with `govulncheck 1.7.0` on Go 1.26.5: six reachable findings before,
  five after; gRPC `GO-2026-6061` is no longer reported. Four standard-library findings fixed in
  Go 1.26.6 and one transitive OpenPGP finding without a published fix remain;
- complete Bats gate: PASS, 355/355;
- `build.command gui`: PASS on the exact candidate; Standard Swift 307/307 and Legacy Swift
  307/307, both apps/DMGs built, both sidecar checksums verified, and local Developer ID
  signatures verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; each mounted app reports version
  3.1.1 and passes deep/strict designated-requirement verification.

The native libkrun VM still returns `start vm error: Invalid argument (errno 22)` before guest
execution. No disk was mounted or accessed. No installation, notarization, push, release, or
publication was performed.

## Checkpoint E — Go toolchain 1.26.7

Status: local source/build validation complete; Go 1.27 major-version evaluation remains a
separate checkpoint.

The build previously inherited Go 1.26.5 from the developer host and selected floating `stable`
in CI/release. It now locks `GO_TOOLCHAIN_VERSION=go1.26.7` in `sources.lock`. A shared helper
selects that exact version for the `init-rootfs` and gvproxy builds through `GOTOOLCHAIN`; preflight
verifies the selected version, and both workflows resolve the same lock before `actions/setup-go`.
The host-global Homebrew Go installation was not changed.

- official provenance: Go 1.26.7 is the latest patch release of the existing 1.26 line as of this
  checkpoint; 1.26.6 contains the relevant security fixes and 1.26.7 adds a `net/http` fix;
- focused helper/lock/preflight gate: PASS, 14/14; shellcheck and Bash syntax checks: PASS;
- complete runtime build: PASS; Cargo tests: PASS, 58/58;
- output metadata: both arm64 Mach-O Go binaries, `gvproxy` and `init-rootfs`, report `go1.26.7`;
  local signature verification: PASS;
- `govulncheck 1.7.0`, built and run with Go 1.26.7: one reachable finding, down from five after
  checkpoint D. All four Go standard-library findings are absent. The remaining finding is
  transitive `x/crypto/openpgp` (`GO-2026-5932`), with no published fix;
- complete Bats gate: PASS, 360/360;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307, both apps/DMGs and
  sidecar checksums verified, local Developer ID signatures verified;
- mounted-artifact gate: PASS for both read-only DMGs; app version/signature pass, and all four
  embedded `gvproxy`/`init-rootfs` binaries report `go1.26.7`.

The native VM remains blocked before guest execution by the existing `EINVAL`. No drive was
mounted or accessed. No installation, notarization, push, release, or publication was performed.

## Validation categories

- Local source/build/tests: checkpoint A passed 350/350 Bats; checkpoints B, C, and D passed
  355/355; checkpoint E passed 360/360. Checkpoints C through E also passed 307/307 in each Swift
  variant and mounted-DMG verification for both outputs. `PopoverStateRenderTests` compiled but
  remained skipped by the documented macOS 26.6.2 guard.
- Hardware: no real-drive test; local VM guest setup blocked as documented above.
- Signing: standalone runtime gates used ad-hoc signatures; checkpoint C through E packaging also
  verified the locally available BinaryBears Developer ID on both app variants. Required
  hypervisor entitlements passed.
- Notarization: not run.
- Remote/public state: untouched; no push or release.
