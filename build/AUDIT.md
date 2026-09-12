# build/AUDIT.md — `v-audit` (PLAN.md §6)

Every package/feature decision below is backed by evidence read from the real
`vendor/src/anylinuxfs` submodule at commit `0a4472bd7507c1f9a57894547c1af7ea4382d99f`
(`ANYLINUXFS_COMMIT` in `build/sources.lock`) — never guessed. File:line citations are given
for every non-obvious call. Scope test: {ntfs-3g mount, rpc.nfsd export, blkid device
detection} per PLAN.md §6 `v-audit`.

## Beta 3: self-contained runtime and locked util-linux repair (2026-09-12)

The complete native build reproduced HTTP 404 for the locked Alpine
`libblkid-2.42.1-r0.apk`, including inside a newly initialized guest. A libblkid-only
replacement then exposed an unavailable `lsblk-2.42.1-r0.apk`; cached responses from
other clients were not reliable evidence of cold-install availability. The owner
authorized the minimum coherent dependency repair.

- Move the seven guest APKs from the same `util-linux` source to `2.42.3-r1`:
  `blkid`, `libblkid`, `libmount`, `libsmartcols`, `libuuid`, `lsblk`, `mount`.
  The other 47 add-on APKs and 16 base packages remain pinned. No packages are added
  or removed; anylinuxfs and the independently built host static libblkid stay pinned.
- Artifacts come from `https://dl-cdn.alpinelinux.org/alpine/v3.24/main/aarch64/`.
  Exact per-artifact SHA-256 values are in `alpine-apks.lock`; the aggregate hashes
  are in `sources.lock`. All seven APKs were downloaded and their aarch64/origin/version
  metadata checked against Alpine's `util-linux` build, commit
  `d98c55af59055e6ca60fbe36e171546918709965`.
- Every package retains its existing runtime dependency and SONAME-provides set.
  The old/new libblkid ELF libraries expose the same 125 global/weak definitions.
  Command-provides and optional `install_if` package versions advance with the family.
- The changed aggregate hashes create a separate runtime cache identity automatically;
  previous caches remain available. This update covers only the shipped guest family,
  not the host static library or unshipped util-linux tools.
- Native signature-checked installation, exact 70-package verification, source gates
  and GUI/CLI hardware acceptance are recorded in the current testing guide.

The owner subsequently required an entirely self-contained installer. The verified
OCI base, all 54 locked APKs, and the NFS entrypoint source now live directly in
`vendor/runtime` (ordinary Git files, no LFS or remote indirection). The entrypoint
is pinned at `8ddf22ad566c35ba9b2ab667989c1a311681c25d`; its bytes match the previously
installed script. `SHA256SUMS` covers all payload files, anchored by
`OFFLINE_RUNTIME_SHA256` in `sources.lock` and embedded in the initializer binary.
Build verification also checks the complete OCI digest graph and APK lock closure.

Initialization imports the local OCI, verifies/copies the local APKs, uses Alpine's
signature validation and `apk --no-network`, and copies the local entrypoint.
Missing or altered assets fail before cache replacement; there is no network fallback.
Revision 5 includes the offline payload hash in the cache path and marker. The DMG
uses UDZO with zlib level 9; the app contains the compressed OCI/APKs rather than a
large expanded guest rootfs. Compiler/source acquisition remains a developer build
step and is separate from the end-user runtime.

The filesystem-label follow-up adds `probe-filesystem` only to a disposable anylinuxfs
build copy. It uses the existing static libblkid `DevInfo::pv` safeprobe on one validated
partition and returns its filesystem/label as JSON. It does not call `run_list`, whose
container-volume discovery can initialize a VM or assemble volume metadata. No source pin,
library dependency, filesystem driver or runtime payload changes for this addition.

## Per-session live security transaction (2026-08-11)

- Replaced the unevaluated shared `ntfsmac` anchor model with one child below the macOS default
  evaluated path: direct child `com.apple/ntfsmac-<validated-device>`. The transaction checks the
  live root ruleset for `anchor "com.apple/*"`, enables PF with a reference token, loads the child,
  and reads it back before reporting `enforced`.
- PF rules are scoped to the measured `bridgeN` plus exact vmnet `/30`; only client-initiated
  TCP/UDP NFS and mountd traffic is passed statefully. No bare/global PF flush exists.
- VPN handling repairs both full-tunnel defaults and split-tunnel endpoint captures, owns at most
  one exact host route per session, and never changes/deletes a default or unrelated route. A route
  already resolving through the measured bridge is recorded as `notRequired`, not fabricated as
  an applied bypass.
- Root-owned mode-0700 state is atomically written per device with a dedicated child anchor, PF
  token, optional owned route, and fixed reason-coded state. Targeted/idempotent teardown and
  bounded stale-session reconciliation preserve concurrent active mounts, retain incomplete
  cleanup state for safe retry, and fail closed when runtime status is unavailable.
- The old raw XPC `applyPfRules` method was removed: GUI/helper mount and unmount now enter the
  same CLI transaction, eliminating a callable anchor-load operation with no lifecycle owner.
- Mutating helper calls are serialized across XPC connections. Normal uninstall reconciles only
  stale security sessions and stops if cleanup is unknown; destructive all-session teardown is
  reserved for explicit `--force`, so removal cannot silently orphan a PF token or route.
- Option A is explicit. anylinuxfs creates vmnet and then waits for NFS within one command, so the
  wrapper supervises that process, identifies only the newly created validated vmnet `/30`, and
  loads its measured route/PF policy before the backend NFS readiness check can complete. Final
  success still requires a real soft NFS mount plus matching status. Backend or final-proof
  failure releases the early PF token and owned route; unproven release persists retryable state.
- Automated evidence includes PF evaluated-path failure, owned route add/delete, malformed input,
  unverified `soft`, missing/wedged status, concurrent mounts, isolated teardown, packaged template
  staging, pre-NFS sequencing, abort cleanup, privacy-safe live-gate pass/fail, an unparseable PF
  enable token, unsafe state entries, and a route replaced by another interface before teardown.
  The latter three remain fail-closed and never become successful cleanup claims.
- The packaged 2.1 candidate passed one real NTFS/VPN-on transaction on Apple Silicon macOS
  26.6.1: exact private bridge routing, soft NFS, intended NFS/mountd reachability, rejection of
  unrelated bridge ports, a 32 MiB read-back hash match, and clean app/Finder/external teardown.
  The root-only state/PF gate was run by the maintainer but its stdout was not captured in the
  agent transcript, so this audit relies only on the separately captured transport/effect proof.
  VPN-off and concurrent-drive results remain release gates, not inferred claims.
- `install.sh` now replaces every runtime file through a fresh same-directory inode and atomic
  rename before validating Mach-O signatures. This avoids stale-vnode signature failures caused
  by in-place replacement of a running signed helper/runtime while preserving ad-hoc signing,
  entitlements, quarantine, Gatekeeper, and SIP policy.

## anylinuxfs update-policy dry-run (2026-08-08)

The repeatable workflow is documented in
`docs/dev/ANYLINUXFS_UPDATE_POLICY.md` and enforced by
`build/audit-anylinuxfs-update.sh`. The preflight is deliberately read-only: it requires a clean
submodule at `ANYLINUXFS_COMMIT`, accepts only an explicitly fetched descendant from the exact
`nohajc/anylinuxfs` remote, reports the commit/file delta, and tests ntfsmac's source
transformations against a disposable archive. A pass leaves the decision pending; it cannot
change the submodule or `sources.lock`.

Dry-run evidence for upstream `v0.19.0`:

- Candidate `28d308bb9ed15611118fa51d998b988b3ee62459` is four commits after the current
  `8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3` pin. The current pin itself is already 26
  commits after upstream `v0.18.0`, so the v0.19.0 release notes describe more behavior than the
  actual BinaryBears pin-to-candidate delta.
- The official `anylinuxfs-0.19.0` release was published 2026-07-20. The remaining four commits
  bump package versions to `0.19.0`, update `serde_with`, update Go `x/crypto` and its related
  `x/*` modules, and refresh twelve Cargo/Go manifest or lock files.
- The exact four-commit delta changes no Rust/Go implementation source, Alpine package manifest,
  dependency-download script, mount/NFS/vmnet path, or local patch marker. Both immutable-Alpine
  transformations apply successfully to the candidate archive.
- This is **not an accepted pin change**. Dependency-advisory review, candidate build/package
  gates, and real-hardware validation remain outstanding, so `sources.lock` and the submodule stay
  on the audited `0.18.0`/`8aa9ccd` state.

## anylinuxfs v0.19.0 local pin validation (2026-08-30)

The earlier dry-run was resumed on the dedicated local dependency-refresh branch. The exact
four-commit delta and upstream identity were rechecked before moving the submodule. The local pin
now advances from `8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3` to the official `v0.19.0` commit
`28d308bb9ed15611118fa51d998b988b3ee62459`; `ANYLINUXFS_VERSION` and
`VMPROXY_VERSION` advance together from `0.18.0` to `0.19.0`. The previous commit remains the
rollback target.

- The delta remains limited to twelve Cargo/Go manifests and lockfiles. It changes no executable
  source, Alpine list, download contract, runtime patch marker, libkrun resolution, or supported
  filesystem scope. `local_patch_compatibility=pass` and `repository_mutated=false`.
- `build/build-all.sh` built the arm64 host CLI, arm64 Linux static `vmproxy`, `init-rootfs`, and
  `vmrunner-sys`; Cargo tests passed 8 `common-utils` + 41 `anylinuxfs` + 9 `vmproxy`. Both Go
  modules compile for their intended targets (`init-rootfs` on Darwin and `freebsd-bootstrap`
  with `GOOS=freebsd GOARCH=arm64`). The Darwin build has the hypervisor entitlement, an ad-hoc
  signature, no quarantine xattr, and no dynamic libblkid/libuuid dependency.
- The complete Bats gate passed 355/355. A clean `build.command gui` run, with the candidate
  gitlink staged so setup could not restore the old committed submodule, passed 307/307 Swift
  tests for both Standard and Legacy, built both apps and DMGs, verified both DMG checksums, and
  verified local Developer ID signatures. The first packaging attempt was interrupted when it
  exposed that pre-commit gitlink condition and is not counted as candidate evidence.
- `cargo-audit 0.22.2` and `govulncheck 1.7.0` found the same actionable findings in the previous
  pin and in v0.19.0: three Rust vulnerabilities in the anylinuxfs lock, plus reachable Go
  findings in the Go 1.26.5 standard library, gRPC 1.81.1, and the transitive OpenPGP package.
  The update therefore introduces no advisory-count regression, but it is not represented as a
  clean scan. The upstream one-commit gRPC fix and toolchain/transitive findings are separate
  dependency checkpoints rather than being folded into this version update.
- Native VM startup still stops before guest execution with
  `start vm error: Invalid argument (errno 22)`. No disk was mounted or accessed. The pin is
  locally validated for continued dependency work only; hardware acceptance and release approval
  remain outstanding. No notarization, installation, push, or publication was performed.

## anylinuxfs gRPC 1.82.1 security follow-up (2026-08-30)

This checkpoint advances only the anylinuxfs submodule from the accepted `v0.19.0` commit
`28d308bb9ed15611118fa51d998b988b3ee62459` to its direct upstream descendant
`0a4472bd7507c1f9a57894547c1af7ea4382d99f`. The single upstream commit changes only
`init-rootfs/go.mod` and `init-rootfs/go.sum`, updating `google.golang.org/grpc` from `1.81.1`
to `1.82.1`; package versions and every other top-level source/runtime pin remain unchanged. The
v0.19.0 commit is the rollback target.

- The read-only anylinuxfs audit reports one commit and two dependency files. It finds no Rust or
  Go implementation-source change, Alpine package-list change, dependency-download-contract
  change, mount/NFS/vmnet-path change, or local-patch incompatibility.
- `go test ./...` passes for `init-rootfs`. `build/build-all.sh` rebuilds the complete local
  runtime and passes all 58 Cargo tests; the complete Bats gate passes 355/355. Native VM startup
  reaches the same pre-guest `EINVAL` limitation and no disk is accessed.
- `govulncheck 1.7.0` on Go 1.26.5 decreases from six reachable findings to five. The prior gRPC
  finding (`GO-2026-6061`) is absent after the update. Four standard-library findings fixed by
  Go 1.26.6 and the transitive `x/crypto/openpgp` finding with no published fix remain separate
  checkpoints; this result is not represented as a clean scan.
- A clean `build.command gui` run on the exact staged gitlink passes 307/307 Swift tests for both
  Standard and Legacy, builds both app/DMG variants, verifies the two SHA-256 sidecars and local
  Developer ID signatures, and passes a second check against both read-only mounted DMGs. The
  mounted bundles report version 3.1.1 and satisfy their designated requirements.
- No real-drive/hardware test, installation, notarization, push, release, or publication was
  performed.

## Go 1.26.7 locked toolchain update (2026-08-30)

The local and CI build toolchain advances from the previously unpinned host Go 1.26.5 to the
exact `go1.26.7` patch release. The [official Go release history](https://go.dev/doc/devel/release)
records security fixes in 1.26.6 and an additional `net/http` fix in 1.26.7. Go 1.27.0 is a
separate major-version compatibility candidate and is not folded into this patch-line checkpoint.

- `GO_TOOLCHAIN_VERSION` is now a required `sources.lock` pin. Local Go build entrypoints use
  `GOTOOLCHAIN=<exact-version>` through one shared helper; the host Homebrew installation remains
  untouched. Per the [official toolchain documentation](https://go.dev/doc/toolchain), a selected
  downloaded toolchain is distributed as a Go module and authenticated by the checksum database.
- Both GitHub workflows resolve the same lock value before `actions/setup-go`; the previous
  floating `stable` selector is gone. The preflight verifies the exact selected patch version and
  fails closed on a missing, malformed, or mismatched lock.
- The complete runtime build passes all 58 Cargo tests and produces arm64 `gvproxy` and
  `init-rootfs` Mach-O binaries whose embedded build metadata reports `go1.26.7`. Both pass local
  signature verification. The complete Bats gate passes 360/360, including five new exact-pin and
  anti-drift tests.
- `govulncheck 1.7.0`, itself built and run with Go 1.26.7 against the pinned `init-rootfs`
  module, reports one reachable finding instead of the five seen after the gRPC checkpoint. The
  four standard-library findings are absent; only `GO-2026-5932` remains for the transitive,
  unmaintained `x/crypto/openpgp` package, for which the database publishes no fix.
- `build.command gui` passes 307/307 Swift tests for Standard and Legacy, builds and locally signs
  both app/DMG variants, and verifies their SHA-256 sidecars. Both DMGs then pass a read-only mount,
  deep/strict app-signature check, version 3.1.1 check, and embedded Go metadata check for both
  `gvproxy` and `init-rootfs`.
- Native VM startup retains the pre-guest `EINVAL` limitation. No disk is accessed; no real-drive
  test, installation, notarization, push, release, or publication is performed.

## libkrun 1.19.x availability review (2026-08-30)

No libkrun pin changes in this checkpoint. Both anylinuxfs consumers declare `libkrun = "1.19.3"`
and both Cargo lockfiles resolve the same crates.io `libkrun 1.19.3` package and checksum
`f414a63a9e7f9134c71581eca90ef5dfdf55693d9c602ba2a81794a0ebee716d`.

- The official crates.io API and `cargo info` report 1.19.3 as the newest published, non-yanked
  crate. `cargo info libkrun@1.19.4` fails because that package version is not in the registry.
- The official libkrun repository does have a `v1.19.4` GitHub release. Its two-commit delta from
  `v1.19.3` includes the version-family bump plus a macOS virtio-fs security-context fix, but its
  workspace crates were not published to crates.io. The protected `stable-1.19.x` branch is newer
  still and is not an immutable package source.
- Switching the vendored anylinuxfs manifests to an unpublished Git dependency would change the
  supply model and require coordinating the full libkrun workspace family. That is not treated as
  a routine pin update and is not introduced implicitly.
- Dedicated validation with the unchanged registry lock passes 41/41 anylinuxfs tests and a
  release `vmrunner-sys` build without its default FreeBSD feature. `cargo metadata --locked`
  confirms `libkrun 1.19.3` from crates.io in both consumers.

Decision: retain 1.19.3 as the newest reproducible published crate. Re-evaluate when 1.19.4 or a
newer compatible 1.19.x crate is published. No hardware, signing, notarization, or remote gate is
claimed from this no-change review.

## nohajc/libkrunfw release review (2026-08-30)

No libkrunfw pin changes in this checkpoint. The official GitHub releases API for the required
`nohajc/libkrunfw` fork reports `v6.12.62-rev1` as its latest non-draft, non-prerelease release,
so the existing source and runtime contract are current.

- GitHub's published digest for `linux-aarch64-Images-v6.12.62-anylinuxfs.tar.gz` is
  `1de75a3d4ef2eccd41df10f2eac8435dbaba52371fa42b0b0384fd9cf9a1f3ce`, exactly matching
  `LIBKRUNFW_IMAGES_SHA256`.
- GitHub's published digest for `modules.squashfs` is
  `86ed485e4e46ba265261a55e25c92ea15f6118003fcec95a8bafde8ad39f697f`, exactly matching
  `LIBKRUNFW_MODULES_SHA256`.
- A fresh `build/fetch-prebuilt.sh` download verifies both hashes and produces the expected ARM64
  16K and 4K kernel images plus the SquashFS module archive. `build/verify-vendor.sh` passes the
  runtime kernel pin and existing architecture/quarantine/signature checks.

Decision: retain `v6.12.62-rev1`; there is no newer fork release to apply. The fetch helper also
downloads the separately pinned vmnet-helper by design, but that component is not evaluated or
accepted by this checkpoint. No VM boot, real-drive, notarization, or remote action is claimed.

## Runtime Alpine pin and cache migration (P0.1, 2026-08-05)

- `ALPINE_TAG`, the linux/arm64 `ALPINE_DIGEST`, and `ANYLINUXFS_COMMIT` remain the only inputs.
  `cli/lib/runtime-alpine.sh` derives one immutable `docker.io/library/alpine@<digest>` pull
  reference, a tag-aware versioned cache directory, and a rootfs marker from them. The tag is kept
  separately because containers/image rejects Docker references that combine a tag and digest.
- The pinned anylinuxfs submodule is not edited. `build/lib/patch-runtime-alpine.sh` transforms only
  scratch build copies of Rust/config/Go sources and hard-stops if the audited markers drift.
- The init-rootfs patch preserves the full digest reference for the registry pull while using a
  deterministic digest-derived local OCI tag. `build/init-rootfs.sh` still independently checks
  Docker Hub's arm64 manifest digest before building or pulling.
- The same patch gives containers/image application-owned registry, registry-drop-in, short-name,
  and empty authentication inputs. The pinned public pull therefore never reads the user's
  containers or Docker configuration, and ntfsmac never changes those files.
- Runtime caches migrate side-by-side. Legacy, mismatched, invalid, and interrupted directories are
  retained; no install, Diagnose, or Settings action downloads or removes a rootfs. A mount either
  reuses a complete matching cache or initializes the pinned cache after preserving incompatible
  state.
- `build/verify-runtime-alpine.sh` inspects both shipped binaries and the exact staged package tree.
  Packaging fails before hashing/signing if a floating reference survives or the approved
  reference, versioned base directory, or marker is absent.

## ext2/3/4 mount support (added 2026-08-01) — no package, no vendored source

Scope expansion from NTFS-only to NTFS + ext2/3/4. Recorded here because it is a feature
decision, not because it changed the package list — it didn't.

- **No Alpine package added.** ext mount is kernel-side: the guest's `mount` invokes the
  built-in ext4 driver directly. No `e2fsprogs`/`xfsprogs`/`btrfs-progs`-style userspace tool
  is needed for mount (those are repair/resize tools, not mount deps — same reasoning the
  `btrfs-progs`/`zfs` CUT rows above use). The trimmed package list is unchanged.
- **No vendored source added (L9 unaffected).** The ext4 driver ships built into the
  vendored libkrunfw kernel image, not as a fetched artifact.
- **Kernel-module verification (real, not assumed):** `modules.squashfs`
  (`LIBKRUNFW_IMAGES_ASSET`, sha256 in `sources.lock`) was inspected with `unsquashfs`.
  `modules.builtin` inside it lists `kernel/fs/ext4/ext4.ko`, `kernel/fs/jbd2/jbd2.ko`, and
  `kernel/fs/mbcache.ko` as **built-in** — the ext4 driver (which mounts ext2/3/4) is in the
  kernel `Image`, not a loadable module. Gate passed; no new libkrunfw build needed.
- **No XPC/signing change (§0.3 unaffected).** ext uses blkid auto-detect + kernel mount —
  no `--fs-driver`, no passphrase, no helper/bundle-id touch. L1 (ntfs-3g default) is
  untouched: `--fs-driver` remains an NTFS-only option.
- **Wiring:** `cli/lib/list-drives.sh` and `gui/Drives/DriveScanner.swift` switched from
  `anylinuxfs list --microsoft` to bare `anylinuxfs list` + a client-side allow-set
  `{ntfs, exfat, BitLocker, ext2, ext3, ext4}` (mirrors `WINDOWS_FS_TYPES` + ext). Out-of-
  scope Linux FS (btrfs/xfs/zfs/LUKS/LVM) returned by bare `list` are dropped client-side.
  Note: the kernel image also has `xfs.ko`/`btrfs.ko`/`f2fs.ko`/`ntfs3.ko` built-in and
  `zfs.ko`/`spl.ko` loadable, but those are deliberately NOT wired into the allow-set — ext
  is the approved scope.

## Alpine packages — `init-rootfs/default-alpine-packages.txt` (13 packages)

| Package | Decision | Evidence |
|---|---|---|
| `bash` | **KEEP** | `anylinuxfs/src/vm_image.rs:34` — `root_path.join("bin/bash")` is one of the files checked for rootfs validity (`required_files_exist`). Guest commands are run via `/bin/bash -c <cmd>` (`anylinuxfs/src/main.rs:731`). Hard requirement, not optional. |
| `blkid` | **KEEP** (settled, L-rule) | Disk identification — required by PLAN.md itself ("blkid-based device detection"). Also a shared-lib dependency (`libblkid.so.1`) of `lsblk`, `mount`, `nfs-utils`, `ntfs-3g-progs` per the real Alpine v3.23 aarch64 APKINDEX. |
| `btrfs-progs` | **CUT** | No source reference anywhere in `anylinuxfs`/`vmproxy`/`init-rootfs` beyond its own package-list entry. Not a transitive dependency of any kept package (APKINDEX: depends only on shared libs, all already satisfied elsewhere or unused once cut). BTRFS is a filesystem type ntfsmac doesn't support. |
| `cryptsetup` | **KEEP — reversed 2026-07-10** | Used for LUKS/BitLocker volume decryption: `vmproxy/src/main.rs:714` ("Decrypt LUKS/BitLocker volumes using cryptsetup"), `:752` (`Command::new("/sbin/cryptsetup")`). Originally cut (PLAN.md's XPC surface doesn't yet expose a passphrase param), but the maintainer wants encrypted-NTFS/BitLocker mount support preserved rather than silently dropped — feature cuts should not trade away user-facing capability. Kept in the trimmed list; wiring the passphrase param through the XPC surface is a Phase 2/3 task, not this audit's. |
| `lsblk` | **KEEP** | `anylinuxfs/src/diskutil/mod.rs:1146` runs `/bin/lsblk -O --json` inside the guest as the core of `get_lsblk_info`, used by both disk listing and mount device resolution. Confirmed hard dependency, not guessable from the package name alone. |
| `lvm2` | **KEEP** — corrected 2026-07-12, see below | Originally cut on the strength of one call site (`vgchange -ay`, confirmed harmless). Missed a second: `vmproxy/src/main.rs:1106-1120` — guest-side `vmproxy`'s own boot sequence unconditionally runs `mount_tmpfs()` over a fixed dir list including `/etc/lvm/archive` and `/etc/lvm/backup`, and `mount_tmpfs()` (`main.rs:633-640`) hard-`bail!`s on the first dir that doesn't exist. Those two dirs only exist because lvm2's Alpine postinstall script creates them — cutting the package removed the dirs, which crashed `vmproxy` on **every** VM boot (`Failed to mount tmpfs on /etc/lvm/archive` → guest exits 1 → host sees "libkrun VM exited with status: 1" → NFS server never comes up → mount fails). Confirmed against a real failing mount log, not assumed. Restored to keep the guest's fixed init-mount list intact; this is the sanctioned patch channel (swap the package list, never hand-edit the vendored submodule) already used for every other trim in this table. |
| `mdadm` | **CUT** | `anylinuxfs/src/diskutil/mod.rs:1150-1153` — `/sbin/mdadm --assemble --scan` only runs `if assemble_raid` (an explicit opt-in CLI flag for RAID arrays). ntfsmac's scope never sets this flag (no RAID support planned). Safe cut — the code path is never reached. |
| `mount` | **KEEP** | Used extensively and unconditionally: `/bin/mount` direct invocation (`vmproxy/src/main.rs:974`), `mount -t nfs -o ...` (`anylinuxfs/src/cmd_mount.rs:1056`, `anylinuxfs/src/fsutil.rs:322`), `mount -t tmpfs` for `/tmp`/`/run` setup in every guest script (`diskutil/mod.rs:1143-1144`, `main.rs:680`). Core requirement. |
| `nfs-utils` | **KEEP** (settled, L-rule) | Provides `rpc.nfsd`, explicitly required for the NFS export step of the mount flow (PLAN.md §2.2 step 5). Real APKINDEX shows it transitively pulls `rpcbind` and `python3` — both resolved automatically by `apk add nfs-utils`, no manual addition needed to the trimmed list. |
| `ntfs-3g` | **KEEP** (settled, L-rule) | Default driver (L1). Provides `mount.ntfs-3g`, `mount.ntfs`, `lowntfs-3g` — the actual FUSE mount binaries invoked for the default driver path. |
| `ntfs-3g-progs` | **KEEP** (added after packaged BB-P1-07) | Provides `/usr/bin/ntfs-3g.probe` and `/usr/bin/ntfsinfo`, the upstream read-only checks used before an opt-in read/write NTFS3 mount. Real hardware proved that `ntfs-3g.probe --readwrite` returns success for Windows' scheduled-check/dirty flag even though the kernel NTFS3 driver rejects it; on the same fixture normal read-only `ntfsinfo --mft` returned nonzero and forced read-only inspection reported `Volume Flags: ... DIRTY`. `build-all.sh` patches only the disposable vmproxy build copy to require both checks before NTFS3. Neither repairs nor writes the volume; any nonzero or unavailable result fails closed. Other repair tools in the package remain uninvoked. |
| `squashfs-tools` | **KEEP** — caught by audit, not assumption | Initially looked like a cut candidate (squashfs mounting is a kernel driver capability, not a userspace-tool need). Real evidence overturned that: `init-rootfs/main.go:345` embeds `unsquashfs -mem 32M -d $MOD_PATH modules.squashfs` into the **guest's own first-boot `vm-setup.sh`** (written via `writeSetupScript`, `main.go:325-350`), which unpacks the kernel-modules squashfs archive into `/lib/modules/$(uname -r)` at guest first boot. `unsquashfs` (from `squashfs-tools`) must be present in the guest image for this step to succeed. This is exactly the kind of transitive requirement PLAN.md warns not to cut on name alone. |
| `zfs` | **CUT** | No source reference beyond its own package-list line. ZFS is a filesystem type ntfsmac doesn't support. Its Alpine package deps (`libzfs`, `libnvpair`, etc.) are exclusive to it — nothing else in the trimmed set needs them. |

**Net result: 13 → 10 packages.** `bash blkid cryptsetup lsblk lvm2 mount nfs-utils ntfs-3g ntfs-3g-progs squashfs-tools`

The original package-contract change incremented ntfsmac's Alpine runtime cache from v1 to v2 for
`ntfs-3g.probe`. The measured dirty-flag false negative now increments it again to v3 (`...-r3`),
whose completeness contract requires both `ntfs-3g.probe` and `ntfsinfo`. Existing v1/v2 caches
remain beside the new directory for rollback but cannot be mistaken for the completed preflight.
written to `build/alpine-packages.trimmed.txt`.

## Cargo feature flags (real, read from the actual `Cargo.toml` files)

- `anylinuxfs/Cargo.toml`, `vmproxy/Cargo.toml`, `vmrunner-sys/Cargo.toml` — all three declare
  `default = ["freebsd"]` / `freebsd = []` (an empty marker feature; the actual `#[cfg(feature =
  "freebsd")]` gates live in the Rust source, e.g. `anylinuxfs/src/vm_image.rs:10`).
- Per PLAN.md's settled decision: **`-F freebsd` is marked test-drop.** Empirical
  "does it compile clean without the flag" verification is `v-anylinuxfs-build`'s job (tier
  `large`, has its own build+test step) — this audit only confirms the flag exists exactly as
  PLAN.md described and identifies where it's used, so that unit isn't guessing either.
- No other Cargo feature, dependency, or Alpine package beyond the settled cuts
  (`freebsd-bootstrap`, `vmproxy-bsd`, `-F freebsd`) is added or removed by this audit.

## Correction to CLAUDE.md's vendored-source table

`anylinuxfs/Cargo.toml` pins `libkrun = { version = "1.19.3", features = ["blk", "net"] }` — a
normal **crates.io** semver dependency, not a direct git dependency. `CLAUDE.md`'s table says
"Cargo.lock exact commit — not hand-edited," which assumes a git dependency; in reality the pin
that matters is the crates.io package version + Cargo.lock's checksum for that exact published
crate (still not hand-edited — same spirit, different mechanism). `build/sources.lock` now records
that archive checksum explicitly as `LIBKRUN_CRATE_SHA256`, and a regression test compares it with
both consumer lockfiles. This is a real discrepancy from the assumption in CLAUDE.md, not an
invented fact; the reproducibility control follows the actual registry supply path.

## `init-freebsd` / `gvproxy-darwin` — confirms settled cuts are real, not just theoretical

`vendor/src/anylinuxfs/download-dependencies.sh` (upstream's own fetch script) does fetch
`init-freebsd` from `nohajc/libkrun` releases and a prebuilt `gvproxy-darwin` binary on macOS
hosts. This confirms the settled PLAN.md cuts are meaningful (upstream's default build includes
both) — ntfsmac's `v-fetch-prebuilt` must **not** replicate the `init-freebsd` fetch, and
`v-gvproxy` deliberately builds from source instead of using the prebuilt `gvproxy-darwin`
binary. Neither is a deviation from PLAN.md; both are the plan working as intended.

## `v-alpine-rootfs` build environment findings (2026-07-10)

Building `vmrunner-sys` (Rust, a `v-alpine-rootfs` dependency via the patched
`init-rootfs` Go tool) surfaced two real, repo-location-specific build bugs — not
upstream bugs, environment ones. Both are load-bearing for **any** future Cargo build
that pulls in `libkrun` from this repo (this will resurface in `v-anylinuxfs-build`,
which also depends on `libkrun` directly):

1. **Path-with-spaces breaks `krun-init-blob`'s build script.** When this repo lives
   on a path containing spaces (e.g. a network-mounted "Windows Shared Folder" volume),
   `krun-init-blob`'s `build.rs` (pulled in transitively via `libkrun`)
   whitespace-splits the resolved `CC_LINUX` compiler path (the common
   `CC="ccache gcc"`-style convention of treating the env var as
   compiler-plus-flags), so a space in the path truncates it:
   `failed to execute <repo>: No such file or directory` (truncated at the first
   space). Confirmed by building the identical vendored sources from a space-free
   path, which compiles clean.
   **Fix applied:** `build/init-rootfs.sh` builds the patched `vmrunner-sys`/`init-rootfs`
   copy from a space-free cache dir outside the repo (`$TMPDIR/ntfsmac-build/...`), not
   under `$REPO_ROOT/build/.cache/`. **Recommend `v-anylinuxfs-build` do the same** for
   building the `anylinuxfs` crate itself, to avoid re-discovering this.
2. **This repo's volume doesn't support the fsync/ioctl calls `go.podman.io/image`'s
   blob-copy step makes.** Real failure pulling the Alpine OCI image with output
   pointed at `vendor/rootfs/` (on this "Windows Shared Folder" network-mounted
   volume): `sync .../oci-put-blob...: inappropriate ioctl for device`. This is the
   same class of issue as an earlier `git add` failure on a large file in this
   volume (session history) — this volume doesn't fully support POSIX semantics some tools
   assume. Plain writes (curl downloads, tar extraction, `go build`/`cargo build`
   output — see `vendor/kernel/`, `vendor/bin/`) work fine; it's specifically this
   fsync pattern that doesn't. **Fix applied:** the real Alpine pull/unpack also
   happens in the space-free off-volume cache dir, not `vendor/rootfs/` directly.
   **This means `build/init-rootfs.sh` cannot literally satisfy PLAN.md's "output
   under `vendor/rootfs/`" wording on this volume** — flagged here; the script
   prints the real output path (`NTFSMAC_ROOTFS_HOME=...`) instead.
3. **New toolchain dependency: `lld`.** `cc_linux` (the vendored cross-compiler
   wrapper anylinuxfs already ships, used unmodified) invokes
   `/opt/homebrew/opt/llvm/bin/clang -fuse-ld=lld`; Homebrew's `llvm` formula does not
   bundle the `lld` linker — it's a separate formula. Installed via
   `brew install lld` (build-toolchain tap, consistent with Phase V's "zero brew taps
   beyond build-toolchain ones" exit criterion). Not yet added to `build/preflight.sh`
   — should be, since a fresh machine will hit the exact same failure.
4. **Real, confirmed empirical result:** `vmrunner-sys` compiles clean **without**
   `-F freebsd` (once the above two issues are worked around) — consistent with
   PLAN.md's settled "-F freebsd is test-drop" decision, now verified for this crate
   specifically (previously only asserted, not built).
5. **Real DAG gap found:** the vendored `init-rootfs` tool's full flow (pull → unpack →
   generate `vm-setup.sh` → embed `vmproxy` binary + `modules.squashfs` into the
   rootfs → boot a VM to actually run `apk add`) tries to copy `vmproxy` from a
   `libexec/` dir — but `vmproxy` is a `v-anylinuxfs-build` artifact, which PLAN.md's
   DAG (§5) places **after** `v-alpine-rootfs` (V-1 → V-2), not before. So
   `v-alpine-rootfs`, as literally scoped, cannot reach the VM-boot / real-apk-install
   step on a first pass. **What `build/init-rootfs.sh` verifies for real:** Alpine
   pulled at the digest-verified pin, unpacked, and `vm-setup.sh` generated with
   **exactly** our trimmed package list (`apk --update --no-cache add bash blkid
   cryptsetup lsblk mount nfs-utils ntfs-3g squashfs-tools` — confirmed byte-for-byte
   via a real run). This satisfies `v-alpine-rootfs`'s literal acceptance wording (the
   package manifest). **What's deferred:** vmproxy embedding + actual VM boot +
   real `apk add` execution — re-run `build/init-rootfs.sh` after `v-anylinuxfs-build`
   lands (it stages `vendor/bin/vmproxy` automatically if present) to complete and
   verify that part; `modules.squashfs` staging (from `v-fetch-prebuilt`'s output) is
   already wired and confirmed working.

## Integration note for `v-alpine-rootfs` (next unit, not resolved here)

`init-rootfs/main.go` embeds `default-alpine-packages.txt` via `//go:embed` at Go compile time
(`main.go:293`) and generates a first-boot `apk add` script from it (`writeSetupScript`,
`main.go:325`). `build/alpine-packages.trimmed.txt` (this unit's output) is the trimmed
replacement list, but *how* it gets substituted — patching anylinuxfs's embedded file before
building `init-rootfs`'s Go binary, vs. `build/init-rootfs.sh` building the rootfs directly via
`umoci` + our own `apk add` step bypassing anylinuxfs's Go tool — is `v-alpine-rootfs`'s decision
to make, not this audit's.

## Host-side static libblkid — Homebrew static-archive staging (tosbaha #1 fix, 2026-08-01)

**Problem (real, from the issue tracker):** the macOS-host `anylinuxfs` binary dynamically
linked `/opt/homebrew/*/libblkid.1.dylib` because `libblkid-rs`/`libblkid-rs-sys` (Cargo dep
at `anylinuxfs/Cargo.toml:12`) resolves libblkid via pkg-config, and the submodule's
`anylinuxfs/.cargo/config.toml` hardcodes
`PKG_CONFIG_PATH=/opt/homebrew/opt/util-linux/lib/pkgconfig`. On any machine without
`brew install util-linux`, the binary aborted at launch (`Library not loaded: libblkid.1.dylib`,
DYLD Namespace code 1) — broke both the CLI and the GUI (the GUI shells out to the same
`/usr/local/ntfsmac/bin/anylinuxfs`).

**Decision (maintainer):** static-link `libblkid` into `anylinuxfs` so the shipped binary has no
libblkid dylib in its `otool -L` output. **Use Homebrew's already-built static archives —
NOT a vanilla util-linux from-source build.** Homebrew's `util-linux` is the build known to
work on macOS (a vanilla tarball build is the risky path we deliberately do not take; an
earlier plan to build util-linux 2.40.4 from source with upstream PR #4173 was rejected on
this basis). `build-libblkid-static.sh` stages Homebrew's `libblkid.a` + `libuuid.a` (Homebrew
ships both) into a dylib-free stage dir, authors `blkid.pc`/`uuid.pc` pointing at it, and
`build-all.sh` points the anylinuxfs cargo build there. With only `.a` in the stage,
`-lblkid`/`-luuid` resolve to the static archives for certain. Rejected alternatives:
- **Document `brew install util-linux`** — violates the CLAUDE.md non-negotiable that
  `vendor/bin/anylinuxfs list` works with zero brew taps beyond build-toolchain ones at runtime.
- **Bundle a Homebrew util-linux dylib + rpath/sign fixes** — a prebuilt dylib plus
  per-target rpath/install_name wiring in `install.sh` and `package-app.sh`. Static is
  cleaner on the distribution side (nothing to bundle).

**Transitive deps (found by a real static-link proof, not guessed):** `libblkid.a` references
`_libintl_gettext` (GNU gettext — not in libSystem), so Homebrew `gettext`'s `libintl.a` is
staged too and `intl` is added to `blkid.pc`'s `Requires.private`. `libintl.a` in turn
references `_iconv`/`_iconv_open` (→ `libiconv.2.dylib`, a **system** lib in `/usr/lib`) and
`_CFArrayGetCount` (→ CoreFoundation, a **system** framework). `intl.pc` declares
`Libs.private: -liconv -framework CoreFoundation`. Net runtime deps added are all
OS-provided (libSystem, libiconv, CoreFoundation — present on every macOS); **no Homebrew
dylib is needed at runtime.** `libuuid` needs `-lpthread` (libSystem provides it), declared
in `uuid.pc`'s `Libs.private`. The proof: a tiny C program linked via
`pkg-config --static --libs blkid` builds clean, runs (`blkid_get_cache` succeeds), and
`otool -L` shows only the three system libs — no `libblkid`/`libuuid`/`libintl` dylib.

**Build dep (not a runtime dep):** `util-linux` and `gettext` are Homebrew **build-toolchain**
deps. `build/sources.lock` records `UTIL_LINUX_BREW_FORMULA=util-linux` (no tarball/sha256 —
we consume Homebrew's install, not a fetched artifact). `build/preflight.sh` asserts both
formulas are installed AND ship the static archives (`libblkid.a`/`libuuid.a`/`libintl.a`),
since the whole fix depends on the `.a` being present, not just the dylib.

**Wiring (`build/build-all.sh`):** `build-libblkid-static.sh` runs before
`build_anylinuxfs`; the latter exports `PKG_CONFIG_PATH=<stage>/lib/pkgconfig` +
`PKG_CONFIG_ALL_STATIC=1` around `cargo build --release` (Cargo `[env]` default `force=false`
→ shell env wins over the submodule's homebrew path), AND neutralizes the homebrew
`PKG_CONFIG_PATH` line in the CACHE_DIR copy of `.cargo/config.toml` (belt-and-suspenders:
if the env override ever stopped winning, the build still couldn't fall back to the dylib).
The submodule itself is never edited — same rule as `patch_vmproxy_mount_tmpfs`. The stage
defaults to a **space-free** path under `$TMPDIR` (not the repo) for the same reason
`build-all.sh` copies anylinuxfs to a space-free `CACHE_DIR`: this repo's path-with-spaces
makes pkg-config backslash-escape the `-I`/`-L` paths, which the pkg-config Rust crate
mis-parses.

**Acceptance:** `tests/build/build-all.bats` asserts (1) the wiring is present (fast, grep)
and (2) `otool -L vendor/bin/anylinuxfs` has no `libblkid` entry (slow, real build).
`tests/build/util-linux.bats` runs the stager for real (it only copies Homebrew's `.a` +
headers + authors `.pc` — fast, no source build) and asserts the stage is dylib-free, the
`.pc` chain pulls `uuid`+`intl` statically, and `pkg-config --static --libs blkid` resolves
to the staged archives.

## Reproducible Alpine package contract (dependency refresh, 2026-08-30)

The immutable Alpine OCI digest fixed the 16-package base filesystem, but the first-boot command
previously ran an unconstrained `apk --update --no-cache add` for only the ten reviewed direct
packages. That allowed Alpine's live repository indexes to choose a different 54-package
transitive closure without changing `sources.lock` or the OCI digest.

The runtime contract is now revision 4 and has three independently hashed inputs:

- `build/alpine-base-packages.lock`: the exact 16-package manifest owned by the OCI digest;
- `build/alpine-packages.lock`: the exact 54-package ntfsmac add-on closure;
- `build/alpine-apks.lock`: the source channel and SHA-256 of each of those 54 APK files.

The scratch-built `init-rootfs` embeds the exact manifests, rejects per-user custom packages, and
downloads only the locked APK URLs. Each download is SHA-256 checked before it is renamed into the
guest cache. Installation then uses the local official APKs with `apk --no-network`; it does not
refresh repository indexes, enable Alpine edge globally, or use `--allow-untrusted`. The three
aggregate hashes are embedded in both runtime binaries and the rootfs marker. A version-only or
byte-level artifact change therefore receives a distinct cache identity and cannot reuse an older
rootfs silently.

The base package list is deliberately not reinstalled from current repositories: four package
versions in the digest-owned Alpine 3.23.5 base were already absent from the live v3.23 indexes
during this audit. Re-fetching that base would make an otherwise immutable OCI pin unreproducible.
Instead, the unpacked base database is compared with the digest-owned manifest.

Local evidence for this infrastructure-only checkpoint: all 54 APK files were downloaded from the
recorded official Alpine channels and matched their recorded SHA-256; the real Rust/Go rootfs build
generated the locked setup script and produced an arm64 `init-rootfs` with the hypervisor
entitlement. No dependency version changed in this checkpoint (`ntfs-3g` remains 2026.2.25-r0).
The local Hypervisor.framework setup still returns `Invalid argument (errno 22)` before guest
setup, so execution of `apk --no-network add` and the installed 54-package database remain an
explicit hardware gate rather than a claimed pass.

The lock is byte-identifying and fail-closed, but the APKs are not vendored: a future CDN removal
will stop the build rather than float to another artifact. Long-term offline availability would
require publishing an approved internal artifact mirror, which is outside this local-only task.

## ntfs-3g 2026.7.7 security update (2026-08-30)

Tuxera's 2026.7.7 security release fixes CVE-2026-42616, CVE-2026-42617,
CVE-2026-42618, CVE-2026-46569, CVE-2026-46570, CVE-2026-46571,
CVE-2026-46572, CVE-2026-56135, and CVE-2026-56136. The upstream source archive was downloaded
from Tuxera and matched SHA-256
`d67b769025d32860549d35c2147e45024d172f81c540d750390ce3602c059dab`; its SHA-512 also matched
Alpine aports commit `905147fb282a60cd622b45c7421db8a116cf80ab`.

Alpine v3.23 and v3.24 still published 2026.2.25-r0 during this update, while Alpine edge
published the fixed `2026.7.7-r0` build. Enabling edge or mixing repository indexes globally was
rejected. Only the three coherent ntfs-3g APKs use `edge/main`; `build/init-rootfs.sh` hard-stops
if any other package attempts to use edge. Their locked SHA-256 values are:

- `ntfs-3g`: `8dac8919f88a891495102c891057f3d674f3dee90b25d4a9ac0efa5573854598`;
- `ntfs-3g-libs`: `ef2aa221c49233e7bb72ef65b3529eb3909c4b35946c6350329fb344284fa69b`;
- `ntfs-3g-progs`: `4ef0c100465bbbd86e7e791dbeaadd216f622f07d2379f12ad5df14f44c60d41`.

The family moves coherently from `libntfs-3g.so.89` to `libntfs-3g.so.90`: the driver and
utilities require `.90`, and the libraries package provides SONAME `libntfs-3g.so.90`. The
required `ntfs-3g.probe` and `ntfsinfo` tools remain present. No other package, OCI image,
anylinuxfs source, kernel, networking helper, or build-tool dependency changed in this checkpoint.

Local non-destructive container validation used the exact digest-pinned aarch64 Alpine base with
networking disabled and mounted the locked APK cache read-only. `apk --no-network` installed all
54 add-on APKs with signature checks active; the resulting database matched the exact 70-package
base-plus-add-on manifest. `ntfs-3g --version` and `ntfsinfo --version` both reported 2026.7.7,
and `scanelf` resolved the driver, probe, and inspector to `libntfs-3g.so.90`. No filesystem was
mounted. The native libkrun path remains a separate hardware gate because it still fails before
guest setup with `start vm error: Invalid argument (errno 22)`.

## vmnet-helper v0.13.0 dependency update (2026-08-30)

The official `nirs/vmnet-helper` release asset moved from v0.12.0 to v0.13.0. The exact consumed
asset is locked by version, embedded source commit, and SHA-256 in `build/sources.lock`:

- version: `v0.13.0`;
- commit: `222c121ba31e49856c9ec6c3a14426b49d77c8fe`;
- `vmnet-helper.tar.gz` SHA-256:
  `dd4355c053c0f04357285ee50169bfce7d04de3f0f49c0356487b099175ab120`.

A fresh fetch matched the asset hash and produced a universal x86_64/arm64 binary whose own
`--version` output matches both locked identifiers. The upstream binary is validly **ad-hoc**
signed, not Apple-signed as the older source table stated, and carries
`com.apple.security.virtualization`. ntfsmac's existing package build then replaces that signature
with the local BinaryBears Developer ID, Hardened Runtime, and the same required entitlement.

The v0.13.0 CLI still accepts every argument passed by anylinuxfs's Darwin network backend:
`--socket`, `--operation-mode`, `--start-address`, `--end-address`, `--subnet-mask`,
`--enable-tso`, and `--enable-checksum-offload`. `build/verify-vendor.sh` now enforces the locked
version and commit plus that interface contract so a valid but incompatible future asset cannot
pass integration silently.

Local validation passed 41/41 anylinuxfs tests, 360/360 Bats tests, 58/58 Cargo tests in the full
build, and 307/307 Swift tests in each Standard and Legacy variant. Both read-only-mounted DMGs
contained the locked helper with a valid Developer ID signature and virtualization entitlement.
No live VM/network/drive gate passed: libkrun still exits with `EINVAL` before guest setup. No
notarization or remote action was performed.

## gvproxy v0.8.9 release review (2026-08-30)

The official release feed still identifies v0.8.9 / commit
`9cfc86f66679ef0feed0f20ba1df558fe2bef5c6` as current. This matches both
`build/sources.lock` and anylinuxfs's independent 0.8.9 download pin, so no top-level gvproxy pin
changed. A fresh source build with locked Go 1.26.7 passed, the binary metadata contains the exact
module version and clean VCS revision, and all self-contained upstream unit-test packages passed.

The upstream `test-qemu` and `test-vfkit` packages require a separately staged integration
environment (`../bin/gvproxy`, QEMU/vfkit, and VM fixtures). A literal `go test ./...` stopped on
those missing harness prerequisites; those two suites are therefore unverified rather than
reported as passing.

The release itself is not security-clean: `govulncheck 1.7.0` reports five reachable SSH findings
in direct dependency `golang.org/x/crypto v0.50.0`, fixed in v0.52.0. That dependency update is a
separate checkpoint; it is not mixed into this release review.

## gvproxy x/crypto v0.55.0 security overlay (2026-08-30)

The v0.8.9 source pin is retained. Its direct `golang.org/x/crypto` dependency moves from v0.50.0
to current v0.55.0 in a disposable build-tree overlay. Minimum-version selection also updates the
compatible Go `x/mod`, `x/net`, `x/sync`, `x/sys`, `x/text`, and `x/tools` graph; no gvproxy
implementation source changes.

The overlay does not mutate the cached upstream checkout. `git archive` exports exact commit
`9cfc86f66679ef0feed0f20ba1df558fe2bef5c6`; locked Go 1.26.7 resolves the exact direct
module, regenerates its vendored graph, and the build hard-stops unless the resulting `go.mod` plus
`go.sum` aggregate matches
`8e39b57de838dd933fc2be46fc2233b2435cbdef2d812b9b62548244257a3b62`. The produced
binary is also inspected to ensure it actually embeds x/crypto v0.55.0.

Self-contained upstream unit tests pass. Both source and binary `govulncheck 1.7.0` scans report
zero reachable vulnerabilities, compared with five on v0.50.0. The two upstream QEMU/vfkit
integration harnesses remain unverified because their separately staged executables and VM harness
were not present. Full local validation passed 362/362 Bats, 58/58 Cargo, and 307/307 Swift tests
per variant. Both read-only-mounted DMGs contain gvproxy v0.8.9 built by Go 1.26.7 with x/crypto
v0.55.0, a clean binary vulnerability scan, Developer ID signature, and Hardened Runtime.

Native VM startup still fails before guest execution with `EINVAL`; no drive, notarization, or
remote action was performed.

## Rust 1.98.0 exact toolchain contract (dependency refresh, 2026-08-30)

Rust was previously an implicit build input: local builds used whichever rustup `stable` happened
to select, and CI/release also requested `stable`. `build/sources.lock` now records exact
`RUST_TOOLCHAIN_VERSION=1.98.0`. `build/lib/rust-toolchain.sh` validates the patch-version shape,
selects it with rustup without changing the user's default, and fails closed when unavailable.
Both Rust-bearing build entrypoints activate it before Cargo runs; preflight additionally requires
the Linux/aarch64-musl target for that exact toolchain. The interactive builder and both workflows
resolve the same lock instead of independently choosing a compiler.

The official 2026-08-20 stable channel manifest identifies rustc 1.98.0 and matched SHA-256
`3f7d139b73bbbd0004ef6e58b430831c68cdad2b1f64ee2eb35d54c09199489a` when reviewed. The
GitHub Action reference remains a separate supply-chain component and is intentionally unchanged
in this checkpoint.

Local evidence: exact-toolchain preflight passed; the unchanged upstream tree passed 57 host Rust
tests; the real project build passed host and Linux/aarch64 cross-compilation plus 58 patched-tree
tests; the full Bats suite passed 367/367. Both Standard and Legacy GUI builds passed 307/307 Swift
tests, produced checksum-valid DMGs, and passed read-only mounted-app Developer ID/Hardened Runtime
verification. The native VM still exits with the existing pre-guest `EINVAL`, so no hardware,
guest, or real-drive result is claimed.

## Immutable Rust setup action (dependency refresh, 2026-08-30)

The three CI/release references to `dtolnay/rust-toolchain@stable` are now immutable full-SHA
references to `6c977a6ca4077a0ceb28ffbe03f59d46e9ac8772`, current `master`/`v1` at review time.
GitHub requires a literal revision in `uses`, so the same value is duplicated in the workflows and
recorded as `RUST_TOOLCHAIN_ACTION_COMMIT`; Bats enforces equality. The action implementation at
that commit is in `master` history and accepts the explicit Rust 1.98.0 input already established
in the preceding checkpoint.

Local workflow parsing, 12 focused lock/toolchain tests, exact-toolchain preflight, and 8 unchanged
common-utils tests passed. A hosted-runner result requires a remote workflow run and remains
unverified because this task has not pushed or otherwise mutated GitHub.

## actions/checkout v7.0.1 full-SHA update (dependency refresh, 2026-08-30)

All five root-workflow checkout references now use immutable commit
`3d3c42e5aac5ba805825da76410c181273ba90b1` (v7.0.1), recorded in
`ACTIONS_CHECKOUT_COMMIT`. This replaces three floating v4 refs and one older pinned v4 ref; the
Pages workflow already used the accepted commit. The reviewed manifest retains every input used
by ntfsmac and moves the JavaScript runtime from Node 20 to Node 24. Upstream requires runner
2.327.1 or newer for this runtime generation.

All root YAML files parsed and 14 focused action/toolchain/lock tests passed. The GitHub-hosted
runner and recursive submodule behavior remain a remote gate: no workflow was triggered. The
checkout ref in the vendored anylinuxfs project's own workflow is inert for ntfsmac and was not
altered inside the pinned upstream submodule.

## actions/setup-go v7.0.0 full-SHA update (dependency refresh, 2026-08-30)

CI and release now use immutable setup-go commit
`b7ad1dad31e06c5925ef5d2fc7ad053ef454303e` (v7.0.0), recorded in
`ACTIONS_SETUP_GO_COMMIT`, instead of floating major ref v5. Go itself remains exactly 1.26.7.
The reviewed action manifest retains the `go-version` input; v7 uses Node 24 and ESM and requires
the runner generation introduced for setup-go v6 (runner 2.327.1 or newer).

Both workflow files parsed, 15 focused action/lock/Go-toolchain tests passed, and the unchanged
init-rootfs module compiled under locked Go 1.26.7. No hosted workflow was dispatched, so action
execution and cache behavior remain remote gates.

## Alpine 3.24.1 exact guest closure (dependency refresh, 2026-08-31)

The guest base moves from Alpine 3.23.5 to current stable patch 3.24.1 for linux/arm64, identified
by official manifest digest
`sha256:e7a1a92a5bfeee40966aea60f0796b0e7917cc35591542701834f03a68fa3d18`. The closure
shape remains deliberately unchanged: 16 base packages plus 54 add-on APKs, or 70 installed
packages. The corresponding base, add-on, and APK-artifact lock SHA-256 values are
`00afb49158f9a22de9da83c5ecac44d29e50c9460f24d21d952bd4af1f43d370`,
`99fc0338f8c2768c3c9dc5416fe26adf5195b572a96c49eb7d0ce426e920c1fe`, and
`6c06f60d19d0b03aca323613838f4cc76bdf3c22a370aa38739d5a5f7087496e`.

All ordinary add-ons resolve from Alpine v3.24 stable repositories. The three coherent ntfs-3g
packages remain the sole `edge/main` exception and remain at the separately reviewed security
version 2026.7.7-r0. Major compatibility movements include musl 1.2.6, util-linux 2.42.1,
cryptsetup 2.8.6, Python 3.14.7, and SquashFS tools 4.7.5.

A fresh official ARM64 image extraction reproduced the base lock. All 54 add-on APK files were
downloaded and hashed, then installed from a read-only cache with `apk --no-network` inside an
ephemeral ARM64 container. Package signature checks remained active, the database matched all 70
exact package entries, and executable/linkage smoke checks passed for the disk, crypto, LVM, NFS,
Python, SquashFS, and NTFS tools used by the guest. Docker Desktop was stopped after this isolated
check and no host disk was exposed.

Focused runtime tests passed 76/76, the project build passed 58/58 Rust tests, and the complete
Bats suite passed 372/372. Standard and Legacy GUI builds each passed 307/307 Swift tests and
produced checksum-valid DMGs. Both DMGs were mounted read-only and passed app version, deep/strict
Developer ID, Hardened Runtime, and embedded Alpine-contract verification. The native libkrun
path still fails before guest execution with `EINVAL`; no real drive, installation, notarization,
or remote action was performed.

## Go 1.27.0 exact toolchain update (dependency refresh, 2026-08-31)

The build-toolchain pin moves from Go 1.26.7 to current stable Go 1.27.0. The official
darwin/arm64 archive metadata reported SHA-256
`90493b3bbd5e10f91d12153198bf1994fd756399b4fec93b49b0c6e2acdeeb3e`; the project continues
to resolve the exact toolchain through authenticated `GOTOOLCHAIN` downloads without changing
the host-global installation. No Go module or runtime-source pin changed.

The unchanged init-rootfs module compiled under 1.27.0. The exact gvproxy v0.8.9 export rebuilt
with the existing x/crypto v0.55.0 overlay, and the locked `go.mod`/`go.sum` aggregate hash did not
change. Both shipped Go binaries report Go 1.27.0. A `govulncheck 1.7.0` scan executed under the
candidate toolchain reported zero reachable gvproxy vulnerabilities. Init-rootfs retains the
known GO-2026-5932 OpenPGP finding inherited through the image stack; the vulnerability database
offers no fixed version, so there is no actionable package bump to mix into this compiler update.

Exact preflight and 9 focused toolchain/action tests passed, followed by 58/58 Rust tests in the
real project build and 372/372 Bats tests. Both GUI variants passed 307/307 Swift tests and emitted
checksum-valid DMGs. Read-only-mounted Standard and Legacy apps passed deep/strict BinaryBears
Developer ID and Hardened Runtime verification, and their embedded gvproxy/init-rootfs binaries
both report Go 1.27.0. The native VM still stops before guest execution with `EINVAL`; no hardware,
drive, notarization, or remote action was performed.

## anyhow 1.0.104 exact Cargo overlay (dependency refresh, 2026-08-31)

The three pinned anylinuxfs workspaces that resolve anyhow now build with exact version 1.0.104,
removing RUSTSEC-2026-0190. The vendored submodule is not modified: a fail-closed build helper
updates disposable common-utils, anylinuxfs, and vmproxy copies and verifies the complete resulting
Cargo.lock SHA-256 values from `sources.lock`. The unchanged vmrunner-sys lock is also checked as a
control. This preserves the reviewed source commit while making the security graph deterministic.

Nine focused overlay/lock tests passed, including submodule-cleanliness and intentional lock-hash
failure cases. The overlaid upstream workspaces passed 8 common-utils, 41 anylinuxfs, and 9 vmproxy
tests. Post-overlay cargo-audit results are clean for common-utils and vmproxy; the anyhow advisory
is absent from anylinuxfs, while the independently queued crossbeam-epoch, quick-xml, lru, and
bincode findings remain reported rather than being mixed into this checkpoint.

The real project build passed 58/58 Rust tests and the complete Bats suite passed 375/375. Standard
and Legacy GUI builds each passed 307/307 Swift tests and produced checksum-valid DMGs. Both DMGs
were attached read-only and passed deep/strict BinaryBears Developer ID and Hardened Runtime
verification. The native VM remains blocked before guest execution by `EINVAL`; no hardware,
drive, installation, notarization, push, release, publication, or remote action was performed.

## crossbeam-epoch 0.9.20 security update (dependency refresh, 2026-08-31)

The anylinuxfs Cargo graph now resolves exact crossbeam-epoch 0.9.20 instead of 0.9.18, removing
RUSTSEC-2026-0204. The update is applied only to a disposable anylinuxfs build copy and the complete
post-overlay Cargo.lock is pinned to SHA-256
`5b78d0605ef0f495f3104f45d2710dd2f4217c7c5fdbcbf76f70933282963ad4`. Other workspace
locks and the upstream submodule remain unchanged.

Nine focused overlay/lock tests and shell static analysis passed. The real project build supplied
the required static-libblkid and Linux cross-build environment and passed all 58 upstream Rust
tests (8 common-utils, 41 anylinuxfs, and 9 vmproxy). Cargo-audit 0.22.2 no longer reports the
crossbeam advisory; the two quick-xml vulnerabilities and the bincode/lru warnings remain visible
for their own checkpoints. The complete Bats suite passed 375/375.

Standard and Legacy GUI builds each passed 307/307 Swift tests and emitted checksum-valid DMGs.
Both DMGs were attached read-only and passed version 3.1.1, deep/strict BinaryBears Developer ID
(Team SQY8T23X8N), and Hardened Runtime checks. The native VM remains blocked before guest
execution by `EINVAL`; no hardware, drive, installation, notarization, push, release, publication,
or remote action was performed.

## libkrun registry checksum coverage, no version change (dependency refresh, 2026-08-31)

Crates.io still exposes 1.19.3 as the newest published libkrun package; upstream GitHub tag
v1.19.4 is still not published there. The version decision therefore remains unchanged. The
historical `LIBKRUN_COMMIT=SEE_CARGO_LOCK` placeholder was inaccurate because both consumers use a
registry archive rather than a git dependency.

`sources.lock` now records the real crates.io archive SHA-256
`f414a63a9e7f9134c71581eca90ef5dfdf55693d9c602ba2a81794a0ebee716d`, and a focused test
checks version, registry source, and checksum in both consumer Cargo.lock files. The lock gate
passed 7/7. No dependency graph changed and no build, hardware, signing, notarization, or remote
result is claimed from this metadata-only correction.

## Homebrew build-toolchain inventory, no repository pin change (dependency refresh, 2026-08-31)

Official formula metadata reports shellcheck 0.11.0, bats-core 1.14.0, LLVM/LLD 23.1.0, umoci
0.6.0, xz 5.8.3, util-linux 2.42.2, gettext 1.0, and pkgconf 3.0.6. The local environment actually
used for all reported builds matches those versions except LLVM/LLD 22.1.8 and pkgconf 3.0.4.

The exact local preflight passed, including the static util-linux/gettext archives. anylinuxfs is
verified not to carry a dynamic libblkid dependency, so these formulas remain build-only. The
repository's workflows install current formula names on fresh runners rather than promising
byte-reproducible Homebrew kegs. The user's global Homebrew installation was not upgraded for this
repository; LLVM/LLD 23.1.0 and pkgconf 3.0.6 therefore remain hosted-runner compatibility gates.
No hardware, signing, notarization, push, release, or publication action was performed.

## bincode maintenance review, no pin change (dependency refresh, 2026-08-31)

RUSTSEC-2025-0141 classifies bincode as unmaintained, supplies no patched version, and does not
describe a concrete vulnerability. Both ntfsmac-relevant occurrences of bincode 2.0.1 are owned by
imago through krun-devices/libkrun. The current imago 0.2.4 manifest still requires bincode major
version 2.

An exact bincode 3.0.0 resolver probe was executed only against a disposable accepted lockfile and
failed as expected because imago requires `^2`; the lock hash did not change. Bincode 1.3.3 is not
a compatible downgrade for imago's bincode 2 APIs or serialized QCOW2 metadata. Eliminating the
warning therefore requires an upstream serialization/API and on-disk compatibility migration, not
a safe lock overlay. The warning remains visible and unsuppressed.

No graph changed, so this review does not claim another build, signing, hardware, notarization, or
remote result. The immediately preceding scans already show zero vulnerabilities and this single
allowed maintenance warning in both affected graphs.

## GitHub Pages action pin coverage, no version change (dependency refresh, 2026-08-31)

Official tag refs confirmed that configure-pages v6.0.0
(`45bfe0192ca1faeb007ade9deae92b16b8254a0d`), upload-pages-artifact v5.0.0
(`fc324d3547104276b827a68afc52ff2a11cc49c9`), and deploy-pages v5.0.0
(`cd2ce8fcbc39b97be8ca5fce6e763baed58fa128`) remain current. The workflow was already pinned
to those immutable commits, so no action version changed.

Their commits are now also recorded in `sources.lock`, with one exact workflow-vs-lock test per
action. The focused lock/action gate passed 13/13 and all root workflows parsed as YAML. No hosted
workflow was dispatched; Pages upload/deployment remains a remote-only result. No runtime,
hardware, signing, notarization, push, release, or publication action was performed.

## lru 0.18.3 security update (dependency refresh, 2026-08-31)

Both libkrun-derived graphs now resolve exact lru 0.18.3: anylinuxfs moves from 0.17.0 and
vmrunner-sys from 0.18.0. Their complete disposable lockfiles are pinned respectively to SHA-256
`27ba0a27915d80ab1e3ea22ab878a4c5f0ff35416e4fd79f101c160354e8d996` and
`621de7110d06ab7a06b8900d098bf8819b2ef95298fb5a57436746137d5f50c4`. The other workspace
locks and the pinned upstream submodule remain unchanged.

Nine focused overlay/lock tests and shell static analysis passed. The real build compiled
vmrunner-sys and passed 58/58 upstream Rust tests. Cargo-audit 0.22.2 reports zero vulnerabilities
and no lru warning in either affected graph; only the separately reviewed bincode 2.0.1
unmaintained warning remains. The complete Bats suite passed 375/375.

Standard and Legacy GUI builds each passed 307/307 Swift tests and emitted checksum-valid DMGs.
Both DMGs were attached read-only and passed version 3.1.1, deep/strict BinaryBears Developer ID
(Team SQY8T23X8N), and Hardened Runtime checks. The native VM remains blocked before guest
execution by `EINVAL`; no hardware, drive, installation, notarization, push, release, publication,
or remote action was performed.

## plist 1.10.0 / quick-xml 0.41.0 security closure (dependency refresh, 2026-08-31)

The resolved direct plist dependency moves from 1.8.0 to exact 1.10.0 and its quick-xml parser
moves from 0.38.4 to exact 0.41.0. plist 1.10.0 constrains quick-xml to `^0.41`; therefore 0.42.0
was tested and correctly rejected by Cargo as incompatible, while 0.41.0 meets both RustSec fixed
version boundaries. The complete disposable anylinuxfs lock is pinned to SHA-256
`f4ef1a47f41be32e90b3ee1f0cd195e3d125df513df7b6df9ccd4a235eb06922`; the other
workspace locks and pinned submodule remain unchanged.

Nine focused overlay/lock tests and shell static analysis passed. The real build compiled the exact
pair and passed 58/58 upstream Rust tests. Cargo-audit 0.22.2 reports zero vulnerabilities: both
RUSTSEC-2026-0194 and RUSTSEC-2026-0195 are gone. The independent lru warning and non-drop-in
bincode maintenance warning remain visible. The complete Bats suite passed 375/375.

Standard and Legacy GUI builds each passed 307/307 Swift tests and emitted checksum-valid DMGs.
Both DMGs were attached read-only and passed version 3.1.1, deep/strict BinaryBears Developer ID
(Team SQY8T23X8N), and Hardened Runtime checks. The native VM remains blocked before guest
execution by `EINVAL`; no hardware, drive, installation, notarization, push, release, publication,
or remote action was performed.

## Final dependency-refresh gate (2026-08-31)

The branch-tip local gate passed 379/379 Bats tests, 58/58 upstream Rust tests in the final build,
and 307/307 Swift tests for both Standard and Legacy applications. Cargo-audit 0.22.2 reports zero
vulnerabilities across the effective graphs; only the reviewed, unsuppressed bincode 2.0.1
maintenance warning remains in the two libkrun-derived graphs. Govulncheck 1.7.0 reports no
vulnerability in the exact gvproxy v0.8.9 plus x/crypto v0.55.0 overlay. Init-rootfs retains
GO-2026-5932 through its OpenPGP image path, with no fixed module version available.

Both version 3.1.1 DMGs passed SHA-256 verification and were mounted read-only. Their apps passed
deep/strict Developer ID verification for BinaryBears Team SQY8T23X8N, report Hardened Runtime
26.5.0, and satisfy the embedded Alpine 3.24.1 digest/package-lock contract. The mounted gvproxy
metadata contains x/crypto v0.55.0, and the shipped anylinuxfs binary has no dynamic
libblkid/libmount/libuuid dependency.

Hardware acceptance is not claimed: the most recent native libkrun attempt stopped before guest
execution with `EINVAL`, and no real drive was accessed or mounted. Docker was stopped after the
isolated Alpine package test. Notarization and hosted workflows were not run. No installation,
push, release, publication, or other remote mutation was performed. At this historical checkpoint,
the separate GitHub issue #24 work was still absent from this branch.

## `dev` 3.1.2 integration, Alpine relock, and USB detection (2026-09-04)

The dedicated dependency branch now contains current `dev`/`origin/dev` at
`b0ff6cd0ad96743b70d7a3e33b86f8ff8f99b58e` (`v3.1.2`) through merge commit `ccb671b`.
This imports the already-reviewed issue #24 follow-up without developing or amending that issue in
the dependency task. The `dev` branch/worktree was not modified. The imported behavior includes
full OCI configuration isolation, serialized first runtime discovery and staging waits, truthful
no-drive/disconnected/mount/read-only state, dedicated runtime retry, removal of the unsafe
read/write override, explicit Finder opening, and automatic Diagnose refresh after mount changes.

The first complete post-merge gate failed closed because Alpine v3.24 had removed the exact
`libexpat-2.8.3-r0.apk` artifact. The next isolated commit changes only libexpat to `2.8.4-r0`,
pins the official aarch64 APK SHA-256 to
`ca1be5be36985a8370f4a8e9e33a25788ac95260295718e1b0b721a16bb2aa61`, and updates the
add-on/APK aggregate hashes to
`08456aa1550bff36b4e6d5a0e26e231a7af97db567aa5170fa0df569e6675f16` and
`06a3d02506a7467a17403ac327076b38c04711959af86039fb50722551a261f3`. All other 69
packages are unchanged; ntfs-3g remains exactly 2026.7.7-r0. An offline, network-disabled ARM64
install matched the exact 70-package closure.

The final source/build gate passed 380/380 Bats tests, 58/58 upstream Rust tests, and 323/323 Swift
tests in both Standard and Legacy variants. Both version 3.1.2 DMGs passed SHA-256, read-only mount,
layout, architecture, embedded-runtime contract, nested entitlements, deep/strict Developer ID
(Team `SQY8T23X8N`), and Hardened Runtime verification. Standard SHA-256 is
`20232cd80098433d0de450fcabf2ad628e833b4593c2a416f5ec4f43c4c3a1fb`; Legacy SHA-256 is
`14913f980af314aff507c7f97ed294b2ea0ea70ab3504d4e85ea09948d4c2c26`.

On the user-provided external NTFS USB device, the exact disposable branch runtime booted the
native libkrun guest, installed the 54 verified Alpine APK artifacts, matched the 70-package
database, detected the partition, and reused the completed cache on a second scan. Diagnostics
matched all current pins and reported zero NFS mounts and security sessions. The volume remained
on its pre-existing read-only macOS mount; ntfsmac did not mount or write it, no test file was
created, and no system app/helper was replaced. This is native runtime/device-detection evidence,
not read/write media acceptance. Notarization, hosted CI, push, release, and publication were not
run.
