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

## Checkpoint F — libkrun 1.19.x review, no pin change

Status: current reproducible pin retained.

Both anylinuxfs and vmrunner-sys declare libkrun 1.19.3 and resolve the same exact crates.io
package/checksum from their Cargo locks. The registry reports 1.19.3 as its newest non-yanked
libkrun crate. GitHub release `v1.19.4` exists and contains a macOS virtio-fs security-context fix,
but `cargo info libkrun@1.19.4` fails because the crate was not published.

Changing to a Git/workspace dependency would be a supply-model change rather than a normal crate
update and would require editing the vendored anylinuxfs dependency declarations. That is deferred
instead of being hidden inside this review.

- anylinuxfs `cargo test --locked`: PASS, 41/41;
- vmrunner-sys `cargo build --release --locked --no-default-features`: PASS;
- `cargo metadata --locked`: both consumers resolve `libkrun 1.19.3` from crates.io;
- pin/files changed: none.

No hardware, signing, notarization, push, release, or publication action was performed for this
no-change checkpoint.

## Checkpoint G — nohajc/libkrunfw review, no pin change

Status: current release retained.

The official release feed for the required `nohajc` fork still names `v6.12.62-rev1` as latest.
Its published SHA-256 values for both consumed assets exactly match `sources.lock`:

- Images archive: `1de75a3d4ef2eccd41df10f2eac8435dbaba52371fa42b0b0384fd9cf9a1f3ce`;
- modules archive: `86ed485e4e46ba265261a55e25c92ea15f6118003fcec95a8bafde8ad39f697f`.

A fresh download verified both assets and extracted ARM64 16K/4K kernel images; the module archive
is valid SquashFS. `build/verify-vendor.sh` passed the runtime-kernel pin and existing vendor
checks. No source or pin changed. vmnet-helper is downloaded by the shared fetch script but remains
a separate dependency decision.

No VM boot, drive access, notarization, push, release, or publication was performed for this
no-change checkpoint.

## Checkpoint H — vmnet-helper v0.13.0

Status: local source/build/package validation complete; live networking and hardware acceptance
outstanding.

The vendored prebuilt moved from v0.12.0 (`0caef043005c7d9f03422a9914bc9d3d4637dc84`)
to the official v0.13.0 release (`222c121ba31e49856c9ec6c3a14426b49d77c8fe`). The
release asset is byte-pinned as
`dd4355c053c0f04357285ee50169bfce7d04de3f0f49c0356487b099175ab120`.
No anylinuxfs, gvproxy, libkrun, libkrunfw, Alpine, or guest-package pin changed in this
checkpoint.

The upstream asset is a universal x86_64/arm64 Mach-O. Contrary to the previous project-table
description, it is ad-hoc signed rather than Apple-signed; the signature is valid and includes
`com.apple.security.virtualization`. The project table now records the actual supply chain:
upstream ad-hoc signature at fetch time, followed by ntfsmac's existing local re-sign step during
packaging. The local lock additionally records the source commit reported by the binary, and
`verify-vendor.sh` now fails closed if the fetched binary's version, commit, or any anylinuxfs-used
CLI option drifts.

Validation:

- fresh official-asset download and locked SHA-256: PASS;
- embedded `--version` / source commit, universal architecture, valid upstream ad-hoc signature,
  and virtualization entitlement: PASS;
- compatibility of `--socket`, operation mode, subnet, TSO, and checksum-offload arguments used
  by anylinuxfs: PASS;
- focused lock/fetch Bats gate: PASS, 11/11; preflight and ShellCheck/Bash syntax: PASS;
- vendored-runtime verifier: PASS; anylinuxfs Cargo tests: PASS, 41/41;
- complete Bats gate: PASS, 360/360;
- `build.command gui`: PASS; the complete Rust suite passed 58/58, Standard Swift passed 307/307,
  Legacy Swift passed 307/307 with only the expected SMJob deprecation warnings, and both apps,
  DMGs, and checksum sidecars were produced and verified;
- mounted-artifact gate: PASS for both read-only DMGs; each embedded helper reports v0.13.0 and
  the locked commit, passes deep app signature verification, carries BinaryBears Developer ID plus
  Hardened Runtime, and retains the virtualization entitlement.

The native libkrun VM still returns `start vm error: Invalid argument (errno 22)` before guest
execution. Therefore no live vmnet traffic, NFS transport, VM guest, or real drive was exercised.
No installation, notarization, push, release, or publication was performed.

## Checkpoint I — gvproxy v0.8.9 review, no top-level pin change

Status: current release retained; reachable Go dependency findings move to the next isolated
checkpoint.

The official `containers/gvisor-tap-vsock` release feed still names v0.8.9 as latest and resolves
the existing commit `9cfc86f66679ef0feed0f20ba1df558fe2bef5c6`. anylinuxfs's own
`download-dependencies.sh` independently pins 0.8.9, so there is no top-level version drift. The
source build completed from that exact clean commit with the locked Go 1.26.7 toolchain, and the
binary metadata records module v0.8.9 plus the expected VCS revision.

All upstream unit-test packages passed. The repository's `test-qemu` and `test-vfkit` packages
are integration harnesses rather than self-contained unit suites: a literal `go test ./...`
downloaded their Fedora CoreOS fixture and then stopped because the harness-specific
`../bin/gvproxy` and `vfkit` executables were not staged. They are recorded as not run, not as a
product regression or pass.

`govulncheck 1.7.0` finds five reachable `x/crypto/ssh` findings in the release's direct
`golang.org/x/crypto v0.50.0` dependency. All five report a fix in v0.52.0. The top-level release
pin remains unchanged in this review; the transitive security update is handled next as its own
checkpoint and will not be hidden inside this no-change result.

No VM, real drive, installation, notarization, push, release, or publication action was performed
for this checkpoint.

## Checkpoint J — gvproxy x/crypto v0.55.0 security overlay

Status: local source/build/package validation complete; upstream VM integration harness and native
hardware acceptance outstanding.

The gvproxy source release remains v0.8.9 at commit
`9cfc86f66679ef0feed0f20ba1df558fe2bef5c6`. Only its direct Go security dependency is
updated, from `golang.org/x/crypto v0.50.0` to the current v0.55.0. Go's minimum-version
selection necessarily moves the compatible `x/*` graph in the disposable build tree:

- `x/mod` 0.35.0 → 0.38.0;
- `x/net` 0.53.0 → 0.57.0;
- `x/sync` 0.20.0 → 0.22.0;
- `x/sys` 0.43.0 → 0.47.0;
- `x/text` 0.36.0 → 0.41.0;
- `x/tools` 0.43.0 → 0.48.0.

This is one atomic module-graph update driven by the direct x/crypto pin, not an unreviewed gvproxy
source advance. `build-gvproxy.sh` exports the exact v0.8.9 commit into a new temporary directory,
resolves the exact overlay with Go 1.26.7 and the Go checksum database, regenerates the vendored
graph there, and hard-stops unless the resulting `go.mod`/`go.sum` aggregate equals
`8e39b57de838dd933fc2be46fc2233b2435cbdef2d812b9b62548244257a3b62`. The cached
upstream checkout remains byte-clean.

Validation:

- malformed/unresolved pins and a deliberately wrong overlay hash fail closed: PASS;
- exact source build, gvproxy version v0.8.9, Go 1.26.7, embedded x/crypto v0.55.0: PASS;
- all self-contained upstream unit-test packages: PASS; `test-qemu`/`test-vfkit` remain the
  separately documented unstaged integration harnesses;
- `govulncheck 1.7.0` source and final-binary scans: 0 reachable vulnerabilities, down from five
  on the unmodified release graph; two required-module findings are not called by the binary;
- focused lock/toolchain/gvproxy Bats gates: PASS; complete Bats gate: PASS, 362/362;
- `build.command gui`: PASS; Cargo tests 58/58, Standard Swift 307/307, Legacy Swift 307/307 with
  expected deprecation warnings only, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both read-only DMGs; embedded gvproxy reports v0.8.9, Go 1.26.7,
  and x/crypto v0.55.0, passes the binary vulnerability scan, and carries local BinaryBears
  Developer ID plus Hardened Runtime.

The native libkrun VM again stopped with `EINVAL` before guest execution. No live NFS/vmnet path,
real drive, installation, notarization, push, release, or publication was exercised.

## Checkpoint K — Rust toolchain 1.98.0

Status: local source/build/package validation complete; GitHub Action implementation pin remains
the next isolated checkpoint.

The build previously inherited the developer's rustup `stable` toolchain (Rust 1.96.0 at the
baseline) and CI/release also selected floating `stable`. It now locks
`RUST_TOOLCHAIN_VERSION=1.98.0`, the official stable release dated 2026-08-20. A shared helper
selects that exact version through `RUSTUP_TOOLCHAIN` without changing the user's default;
preflight requires both rustc/cargo and `aarch64-unknown-linux-musl` for the locked toolchain.
The interactive builder offers to install only that version and target. CI/release read the same
lock and pass it explicitly to the existing Rust setup action. The action reference itself is
deliberately unchanged here.

Validation:

- official manifest SHA-256:
  `3f7d139b73bbbd0004ef6e58b430831c68cdad2b1f64ee2eb35d54c09199489a`;
- focused lock/helper/preflight/build-wiring gate: PASS, 11/11;
- direct upstream host tests on the unchanged source tree: PASS, 57/57 (common-utils 8,
  anylinuxfs 41, vmproxy 8);
- real project build: PASS with rustc 1.98.0 / Cargo 1.98.0, including host anylinuxfs,
  Linux/aarch64-musl vmproxy, vmrunner-sys through its required cross-wrapper layout, and the
  patched runtime test suite 58/58;
- complete Bats gate: PASS, 367/367;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307 with only expected
  SMJob deprecation warnings, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; app version 3.1.1, deep/strict
  designated-requirement verification, local BinaryBears Developer ID, and Hardened Runtime.

A direct `cargo build` from the raw `vmrunner-sys` submodule directory was rejected because that
directory lacks the sibling Linux cross-wrapper layout expected by `krun-init-blob`. The actual
project build creates the documented layout and passed; this was a harness error, not a candidate
regression.

The native libkrun VM still returns `EINVAL` before guest execution. No drive was accessed or
mounted. No installation, notarization, push, release, or publication was performed.

## Checkpoint L — dtolnay/rust-toolchain action pin

Status: local workflow/source validation complete; hosted GitHub runner execution is pending.

Only the Rust setup action reference changed. All three CI/release uses moved from the mutable
`dtolnay/rust-toolchain@stable` branch to reviewed full commit
`6c977a6ca4077a0ceb28ffbe03f59d46e9ac8772` (current `master`/`v1`, 2026-08-05).
`RUST_TOOLCHAIN_VERSION` remains 1.98.0 and every compiler, source, package, and runtime pin is
unchanged. Because GitHub does not permit expressions in `uses`, `sources.lock` records the action
commit and regression tests require each literal workflow SHA to match it.

The pinned action's `action.yml` was compared with the previously selected `stable` revision. Its
only input-schema difference is that `toolchain` is required rather than defaulting to `stable`;
ntfsmac already passes the exact lock explicitly, so the executed install path is unchanged. The
full SHA is in the action's `master` history, satisfying the action maintainer's persistence rule
for immutable pins.

- workflow YAML parse: PASS for CI and release;
- focused Rust action/toolchain/lock Bats gate: PASS, 12/12;
- exact Rust 1.98.0 preflight: PASS;
- unchanged common-utils compile/test under the locked toolchain: PASS, 8/8;
- hosted GitHub Actions execution: not run locally and not claimed, because no push was made.

No hardware, signing, notarization, installation, release, or remote/public action was performed.

## Checkpoint M — actions/checkout v7.0.1

Status: local workflow/source validation complete; hosted GitHub runner execution is pending.

Only the root-workflow checkout action changed. Three CI references formerly used floating `v4`,
the release workflow used an older v4 commit, and Pages already used v7.0.1. All five now resolve
to the current v7.0.1 full commit
`3d3c42e5aac5ba805825da76410c181273ba90b1`, also recorded as
`ACTIONS_CHECKOUT_COMMIT` and enforced by tests. Checkout inputs used by ntfsmac (`submodules`,
`fetch-depth`, and `persist-credentials`) remain supported by the reviewed action manifest.

The upgrade changes the action runtime from Node 20 to Node 24. Upstream declares runner 2.327.1
as the minimum from checkout v5 onward; ntfsmac uses GitHub-hosted `macos-26` and
`ubuntu-24.04`, but compatibility still requires a hosted run before it can be claimed. v7 also
adds the upstream unsafe-fork checkout guard; these workflows do not use `pull_request_target` or
`workflow_run`.

- v7.0.1 action manifest SHA-256 reviewed locally:
  `d59219cb79590abdb877deaa14e3b65a00c05318bf5a6f3b989b9162b5d08c35`;
- all root workflow YAML files parse: PASS;
- checkout/action/toolchain/lock Bats gate: PASS, 14/14;
- all five root references are full SHA and equal the lock: PASS;
- hosted checkout, recursive submodule fetch, and release-tag checkout: not run locally and not
  claimed because no push/workflow dispatch was performed.

The `actions/checkout@v4` text inside the pinned anylinuxfs submodule belongs to that upstream
project's own CI and is never executed by ntfsmac's root workflows; changing it would require a
separate upstream source commit, so it is not treated as an effective ntfsmac action pin.

No runtime binary, package, hardware, signing, notarization, release, or remote/public state was
changed.

## Checkpoint N — actions/setup-go v7.0.0

Status: local workflow/module validation complete; hosted GitHub runner execution is pending.

Only the Go setup action changed. CI and release moved from mutable major ref
`actions/setup-go@v5` to current v7.0.0 full commit
`b7ad1dad31e06c5925ef5d2fc7ad053ef454303e`, recorded as
`ACTIONS_SETUP_GO_COMMIT` and enforced by tests. The selected compiler remains exact Go 1.26.7
from `sources.lock`; no Go module or runtime source changed.

v6 introduced the action's Node 24 runtime and minimum runner 2.327.1; v7 retains Node 24, moves
the implementation to ESM, and updates its action/cache dependencies. The reviewed v7 manifest
continues to accept the exact `go-version` input used by ntfsmac.

- v7.0.0 action manifest SHA-256:
  `cbfae748992b96b9a1bfa3f1679d17c898c78375aad8a0d0184820683c82c482`;
- CI/release workflow YAML parse: PASS;
- action/lock/Go-toolchain Bats gate: PASS, 15/15;
- unchanged init-rootfs Go module compile/test under Go 1.26.7: PASS for both packages (no test
  files);
- hosted action download/cache/toolchain resolution: not run locally and not claimed because no
  remote workflow was triggered.

No hardware, signing, notarization, installation, release, or remote/public action was performed.

## Checkpoint O — Alpine 3.24.1 guest base and exact package closure

Status: local source/build/package validation complete; native VM and real-drive acceptance
outstanding.

Only the Alpine guest base and its exact package closure changed. The release moves from 3.23.5
to current stable patch 3.24.1 for linux/arm64, locked to official manifest digest
`sha256:e7a1a92a5bfeee40966aea60f0796b0e7917cc35591542701834f03a68fa3d18`. The package
names and closure sizes are unchanged: 16 OCI-base packages, 54 add-on APKs, 70 installed
packages in total. The regenerated lock hashes are:

- base manifest: `00afb49158f9a22de9da83c5ecac44d29e50c9460f24d21d952bd4af1f43d370`;
- add-on manifest: `99fc0338f8c2768c3c9dc5416fe26adf5195b572a96c49eb7d0ce426e920c1fe`;
- exact APK artifact lock: `6c06f60d19d0b03aca323613838f4cc76bdf3c22a370aa38739d5a5f7087496e`.

The main compatibility changes include musl 1.2.5 to 1.2.6, util-linux 2.41.4 to 2.42.1,
cryptsetup 2.8.1 to 2.8.6, Python 3.12.14 to 3.14.7, SquashFS tools 4.7.4 to 4.7.5, and
the corresponding library/revision updates. The previously isolated ntfs-3g security family
remains exactly 2026.7.7-r0. It is still the only family allowed from `edge/main`; every other
add-on APK resolves from Alpine v3.24 stable repositories.

Reproducibility and compatibility evidence:

- fresh official ARM64 base extraction reproduced the exact 16-package lock;
- all 54 APK artifacts were downloaded once, hashed byte-for-byte, and then mounted read-only
  into an ephemeral ARM64 container with networking disabled;
- `apk --no-network` verified signatures, installed exactly 70 packages, and matched the expected
  database; executable/linkage smoke checks passed for bash, blkid, cryptsetup, lsblk, LVM,
  mount, NFS utilities, Python 3.14.7, SquashFS 4.7.5, and ntfs-3g 2026.7.7;
- focused Alpine/runtime/diagnostic gates: PASS, 76/76;
- real project build: PASS with 58/58 Rust tests; complete Bats gate: PASS, 372/372;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307 with expected
  deprecation warnings only, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; app version 3.1.1, deep/strict
  Developer ID verification, Hardened Runtime, and the exact Alpine 3.24.1 digest/cache/package
  contract present in each bundle.

Docker Desktop was started only for the isolated no-network container checks and stopped again
afterward. No host disk was exposed to a container. The native libkrun VM still returns `EINVAL`
before guest execution, so no live guest NFS/vmnet path, disk mount, or hardware result is
claimed. No installation, notarization, push, release, or publication was performed.

## Checkpoint P — Go toolchain 1.27.0

Status: local source/build/package validation complete; hosted GitHub runner execution and native
hardware acceptance outstanding.

Only the exact Go compiler pin changed, from 1.26.7 to the current stable 1.27.0 release. The
official darwin/arm64 archive metadata reports SHA-256
`90493b3bbd5e10f91d12153198bf1994fd756399b4fec93b49b0c6e2acdeeb3e`; local builds obtain
the authenticated toolchain through `GOTOOLCHAIN=go1.27.0` and the existing checksum-database
path. No Go module, gvproxy source, security-overlay version, or overlay hash changed.

Validation:

- exact-toolchain preflight and focused Go/action wiring gates: PASS, 9/9;
- unchanged init-rootfs module compile/test: PASS for both packages (no test files);
- exact gvproxy v0.8.9 source build with x/crypto v0.55.0: PASS; the locked module-overlay hash
  remained byte-identical and the output reports Go 1.27.0;
- `govulncheck 1.7.0` under the candidate toolchain: gvproxy has 0 reachable vulnerabilities;
  init-rootfs retains the already recorded GO-2026-5932 OpenPGP finding, for which the database
  provides no fixed version;
- real project build: PASS with 58/58 Rust tests; complete Bats gate: PASS, 372/372;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307 with expected
  deprecation warnings only, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; deep/strict Developer ID and
  Hardened Runtime verification passed, and both embedded Go binaries report Go 1.27.0.

The native libkrun VM still returns the existing pre-guest `EINVAL`; no real drive was accessed or
mounted. Hosted `actions/setup-go`, installation, notarization, push, release, and publication
were not exercised.

## Checkpoint Q — anyhow 1.0.104 Cargo security overlay

Status: local source/build/package validation complete; native hardware acceptance outstanding.

Only `anyhow` changed, from 1.0.102 to 1.0.104, in the three pinned anylinuxfs workspaces that
resolve it: common-utils, anylinuxfs, and vmproxy. The vendored anylinuxfs submodule remains
byte-clean. A new fail-closed helper applies the exact update only to disposable build copies and
then verifies the complete resulting Cargo.lock files against these SHA-256 locks:

- anylinuxfs: `7f9e86699198a6909de3e28bd3b049df99bda0a0ec5747c15baea9af9fba3624`;
- common-utils: `55236dcb0d669545d39c9978e9d98750a248baa734529d13d385fd0ea745cd03`;
- vmproxy: `efe9f05b13f9152fdcd0518bcf516aee1bc7bb7ea2364fb84724197baa21c0ff`;
- unchanged vmrunner-sys control lock:
  `4a082a8c6963bd05c9dc109fa7dd6871bf4d31220106ee76aba5d286382ce45c`.

The update clears RUSTSEC-2026-0190 from the affected workspaces. The deliberately separate
crossbeam-epoch, quick-xml, lru, and bincode findings remain visible at this checkpoint and are
not hidden or combined with this update.

Validation:

- overlay/lock focused gates: PASS, 9/9; the tests also prove that a wrong complete-lock hash
  hard-stops and that the pinned upstream submodule is left unchanged;
- upstream crate tests after overlay: PASS, common-utils 8/8, anylinuxfs 41/41, vmproxy 9/9;
- post-overlay `cargo audit`: common-utils and vmproxy have zero vulnerabilities and zero
  warnings; anylinuxfs no longer reports the anyhow advisory and retains only the separately
  tracked crossbeam-epoch/quick-xml vulnerabilities plus bincode/lru warnings;
- real project build: PASS with 58/58 Rust tests; complete Bats gate: PASS, 375/375;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307 with expected
  deprecation warnings only, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; deep/strict Developer ID and
  Hardened Runtime verification passed.

The native libkrun VM still returns the existing pre-guest `EINVAL`; no real drive was accessed or
mounted. No installation, notarization, push, release, publication, or remote workflow was
performed.

## Checkpoint R — crossbeam-epoch 0.9.20 security update

Status: local source/build/package validation complete; native hardware acceptance outstanding.

Only `crossbeam-epoch` changed, from 0.9.18 to 0.9.20, in the anylinuxfs Cargo graph. The existing
disposable-copy overlay now resolves that exact version and verifies the complete anylinuxfs
Cargo.lock SHA-256 as
`5b78d0605ef0f495f3104f45d2710dd2f4217c7c5fdbcbf76f70933282963ad4`. The common-utils,
vmproxy, and vmrunner-sys lock hashes remain byte-identical, and the pinned upstream submodule
remains clean.

Validation:

- focused overlay/lock gates: PASS, 9/9; shell static analysis passed;
- real project build: PASS, including the upstream 8 common-utils, 41 anylinuxfs, and 9 vmproxy
  tests (58/58 total) with the project's required static-libblkid and Linux cross-build setup;
- `cargo-audit 0.22.2`: RUSTSEC-2026-0204 is absent after the update; only the separately queued
  two quick-xml vulnerabilities plus the bincode and lru warnings remain;
- complete Bats gate: PASS, 375/375;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307 with expected
  deprecation warnings only, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; app version 3.1.1, deep/strict
  Developer ID verification for Team SQY8T23X8N, and Hardened Runtime passed.

The native libkrun VM still returns the existing pre-guest `EINVAL`; no real drive was accessed or
mounted. No installation, notarization, push, release, publication, or remote workflow was
performed.

## Checkpoint S — plist 1.10.0 / quick-xml 0.41.0 security closure

Status: local source/build/package validation complete; native hardware acceptance outstanding.

Only the direct anylinuxfs `plist` dependency and its XML parser changed: resolved plist 1.8.0 to
1.10.0 and quick-xml 0.38.4 to 0.41.0. plist 1.10.0 requires quick-xml `^0.41`, so the otherwise
newer quick-xml 0.42.0 was intentionally rejected as incompatible; 0.41.0 is the exact compatible
release that satisfies the fixed-version boundary for both XML advisories. The complete
post-overlay anylinuxfs Cargo.lock SHA-256 is
`f4ef1a47f41be32e90b3ee1f0cd195e3d125df513df7b6df9ccd4a235eb06922`; every other
workspace lock and the upstream submodule remain unchanged.

Validation:

- focused overlay/lock gates: PASS, 9/9; shell static analysis passed;
- real project build: PASS with exact plist 1.10.0 and quick-xml 0.41.0, including 58/58 upstream
  Rust tests (8 common-utils, 41 anylinuxfs, 9 vmproxy);
- `cargo-audit 0.22.2`: zero vulnerabilities; RUSTSEC-2026-0194 and RUSTSEC-2026-0195 are absent;
  only the separately queued lru warning and non-drop-in bincode maintenance warning remain;
- complete Bats gate: PASS, 375/375;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307 with expected
  deprecation warnings only, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; app version 3.1.1, deep/strict
  Developer ID verification for Team SQY8T23X8N, and Hardened Runtime passed.

The native libkrun VM still returns the existing pre-guest `EINVAL`; no real drive was accessed or
mounted. No installation, notarization, push, release, publication, or remote workflow was
performed.

## Checkpoint T — lru 0.18.3 security update

Status: local source/build/package validation complete; native hardware acceptance outstanding.

Only `lru` changed, to exact 0.18.3, in the two libkrun-derived Cargo graphs: anylinuxfs moved
from 0.17.0 and vmrunner-sys from 0.18.0. The complete post-overlay lockfile SHA-256 values are
`27ba0a27915d80ab1e3ea22ab878a4c5f0ff35416e4fd79f101c160354e8d996` for anylinuxfs and
`621de7110d06ab7a06b8900d098bf8819b2ef95298fb5a57436746137d5f50c4` for vmrunner-sys.
The common-utils/vmproxy locks and pinned upstream submodule remain unchanged.

Validation:

- focused overlay/lock gates: PASS, 9/9; both affected graphs resolve 0.18.3, wrong lock hashes
  hard-stop, and shell static analysis passed;
- real project build: PASS; vmrunner-sys compiled cleanly and the upstream Rust suites passed
  58/58 (8 common-utils, 41 anylinuxfs, 9 vmproxy);
- `cargo-audit 0.22.2`: zero vulnerabilities and no lru warning in either affected graph; only
  the independently reviewed bincode 2.0.1 unmaintained warning remains;
- complete Bats gate: PASS, 375/375;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307 with expected
  deprecation warnings only, both apps/DMGs/checksum sidecars verified;
- mounted-artifact gate: PASS for both DMGs attached read-only; app version 3.1.1, deep/strict
  Developer ID verification for Team SQY8T23X8N, and Hardened Runtime passed.

The native libkrun VM still returns the existing pre-guest `EINVAL`; no real drive was accessed or
mounted. No installation, notarization, push, release, publication, or remote workflow was
performed.

## Checkpoint U — bincode maintenance review, no pin change

Status: reviewed; no compatible dependency update exists.

The remaining RUSTSEC-2025-0141 result is an informational `unmaintained` advisory, not a known
vulnerability, and the advisory declares no patched version. Both affected graphs resolve bincode
2.0.1 through the same chain: imago 0.2.3, krun-devices 0.1.0-1.19.3, and libkrun 1.19.3. The
current imago 0.2.4 release was also inspected and still declares `bincode = "2"`.

A disposable exact-version probe of bincode 3.0.0 failed safely because imago requires `^2`; the
Cargo.lock remained byte-identical to the accepted post-lru hash. Downgrading to the advisory's
historically complete 1.3.3 release is likewise API- and serialization-format-incompatible with
imago's bincode 2 encode/decode implementation. Replacing the serialization library would require
an upstream imago/libkrun design and disk-format compatibility project, not a pin refresh.

No source or dependency graph changed, so no second build result is claimed for this review. The
immediately preceding lru checkpoint's fresh `cargo-audit 0.22.2` scans remain the evidence: zero
vulnerabilities and exactly this one allowed warning in both graphs. No warning was suppressed.
No hardware, drive, installation, signing, notarization, push, release, publication, or remote
action was performed for this no-change checkpoint.

## Checkpoint V — GitHub Pages action pins, no version change

Status: latest upstream tags verified; central lock coverage added; hosted execution outstanding.

The three Pages actions were reviewed independently against their official tag refs and were
already current and immutable in `pages.yml`:

- actions/configure-pages v6.0.0 at `45bfe0192ca1faeb007ade9deae92b16b8254a0d`;
- actions/upload-pages-artifact v5.0.0 at `fc324d3547104276b827a68afc52ff2a11cc49c9`;
- actions/deploy-pages v5.0.0 at `cd2ce8fcbc39b97be8ca5fce6e763baed58fa128`.

No workflow ref changed. The missing reproducibility control was closed by recording all three
commits in `sources.lock` and adding one exact workflow-vs-lock test per action. The combined
lock/action focused gate passed 13/13, and every root workflow parsed as YAML. No hosted workflow
was triggered, so Pages artifact upload, OIDC deployment, and runner compatibility remain remote
gates. No local runtime, hardware, signing, notarization, push, release, or publication action was
performed.

## Checkpoint W — libkrun registry checksum coverage, no version change

Status: current published crate retained; central lock corrected to match the actual supply path.

The fresh registry/repository review still finds 1.19.3 as the newest published libkrun crate.
GitHub tag v1.19.4 remains unavailable on crates.io, so the earlier no-change version decision is
unchanged. The inventory did find a misleading historical key: `LIBKRUN_COMMIT=SEE_CARGO_LOCK`
described a git commit even though both consumers use the crates.io archive.

That placeholder is replaced by exact archive SHA-256
`f414a63a9e7f9134c71581eca90ef5dfdf55693d9c602ba2a81794a0ebee716d`. A focused lock test
now verifies version 1.19.3, registry source, and this checksum in both anylinuxfs and vmrunner-sys
Cargo.lock files. The lock gate passed 7/7. No dependency version or compiled graph changed, so no
additional build, hardware, signing, notarization, push, release, publication, or remote result is
claimed for this metadata correction.

## Checkpoint X — Homebrew build-toolchain review, no repository pin change

Status: local baseline verified; mutable fresh-runner versions reported separately.

These are build-only formula names, not shipped runtime dependencies. The official formula catalog
and the installed/tested environment were compared without upgrading the user's global Homebrew
installation:

| Formula | Current catalog | Locally tested |
|---|---:|---:|
| shellcheck | 0.11.0 | 0.11.0 |
| bats-core | 1.14.0 | 1.14.0 |
| llvm / lld | 23.1.0 | 22.1.8 |
| umoci | 0.6.0 | 0.6.0 |
| xz | 5.8.3 | 5.8.3 |
| util-linux | 2.42.2 | 2.42.2 |
| gettext | 1.0 | 1.0 |
| pkgconf (`pkg-config`) | 3.0.6 | 3.0.4 |

The exact local preflight passed, including static libblkid/libuuid and libintl archives. The
shipped anylinuxfs binary is statically linked against these build inputs, so no Homebrew dylib is
a runtime dependency. Root workflows intentionally install formula names on fresh hosted runners;
therefore LLVM/LLD 23.1.0 and pkgconf 3.0.6 compatibility is a remote CI gate, not a local result.
Changing the global Homebrew installation solely for this repository would exceed the worktree
scope and was not done. No hardware, signing, notarization, push, release, or publication action
was performed for this review.

## Checkpoint Y — final consolidated local gate

Status: the dependency-refresh branch is locally complete; hardware, notarization, and remote
acceptance remain explicitly separate.

The effective dependency inventory was reviewed to closure after the isolated checkpoints:

- Alpine is locked to the official ARM64 3.24.1 image digest, with exact base, add-on, and APK
  artifact locks; ntfs-3g 2026.7.7-r0 remains the only documented `edge/main` exception;
- anylinuxfs is pinned to the reviewed v0.19.0 source plus the separately validated gRPC 1.82.1
  and Cargo security overlays;
- libkrun remains at the newest published crate, 1.19.3, with its crates.io checksum enforced;
  libkrunfw remains at the current reviewed v6.12.62-rev1 release;
- vmnet-helper is updated to v0.13.0; gvproxy remains at current v0.8.9 with the isolated
  x/crypto v0.55.0 security overlay;
- the build toolchains are exact Go 1.27.0 and Rust 1.98.0; the relevant GitHub Actions are
  immutable full-SHA pins; Homebrew inputs were inventoried separately as mutable CI tooling;
- Cargo overlays resolve anyhow 1.0.104, crossbeam-epoch 0.9.20, plist 1.10.0 with compatible
  quick-xml 0.41.0, and lru 0.18.3. Bincode 2.0.1 remains visible and unsuppressed because its
  maintenance advisory provides no patched release and the owning imago graph requires major 2.

Final evidence at the branch tip:

- complete Bats gate: PASS, 379/379;
- `build.command gui`: PASS; Standard Swift 307/307 and Legacy Swift 307/307, with only the
  documented Legacy API warnings and the macOS 26.6.2 Popover render-test skip;
- upstream Rust suites: PASS, 58/58 during the final build;
- `cargo-audit 0.22.2`: zero vulnerabilities in all four effective Cargo graphs; common-utils and
  vmproxy are fully clean, while anylinuxfs and vmrunner-sys report only the reviewed bincode
  informational maintenance warning;
- `govulncheck 1.7.0` built and run with Go 1.27.0: the exact disposable gvproxy overlay is clean;
  init-rootfs retains the already isolated reachable GO-2026-5932 OpenPGP finding, for which the
  vulnerability database provides no fixed version;
- both final DMGs passed SHA-256 verification, were attached read-only, and contained bundle
  version 3.1.1. Both apps passed deep/strict Developer ID verification for Team SQY8T23X8N and
  report Hardened Runtime 26.5.0;
- both mounted apps passed the embedded Alpine runtime-contract gate. Their gvproxy metadata
  contains x/crypto v0.55.0, and anylinuxfs has no dynamic libblkid/libmount/libuuid dependency.

The most recent native libkrun attempt still stopped before guest execution with `EINVAL`, so no
hardware or real-drive claim is made. No real disk was accessed or mounted, Docker was used only
for the isolated package closure and stopped afterward, and no installation was performed.
Notarization was not run. No hosted workflow, push, release, publication, or other remote mutation
was performed. The GitHub issue #24 work remains outside this branch and worktree.

## Validation categories

- Local source/build/tests: checkpoint A passed 350/350 Bats; checkpoints B, C, and D passed
  355/355; checkpoints E and H passed 360/360; checkpoint J passed 362/362. Checkpoints C through
  E, H, J, K, O, P, Q, R, S, and T also passed 307/307 in each Swift variant and mounted-DMG
  verification for both outputs. Checkpoint K passed 367/367 Bats; checkpoints O and P passed
  372/372; checkpoints Q through T passed 375/375. The final consolidated branch-tip gate passed
  379/379 Bats, 58/58 upstream Rust tests, and 307/307 Swift tests in each app variant.
  `PopoverStateRenderTests` compiled but remained skipped by the documented macOS 26.6.2 guard.
- Hardware: no real-drive test; local VM guest setup blocked as documented above.
- Signing: standalone runtime gates used ad-hoc signatures; checkpoints C through E, H, and J
  packaging also verified the locally available BinaryBears Developer ID on both app variants;
  checkpoints O through T repeated that gate. Required hypervisor/virtualization entitlements
  passed.
- Notarization: not run.
- Remote/public state: untouched; no push or release.
