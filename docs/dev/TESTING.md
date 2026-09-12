# ntfsmac testing guide

This is the current test entrypoint. Dated reports under `docs/testing/` retain full run logs and
hardware evidence.

## Automated source gate

Run from a clean feature or release branch:

```sh
git diff --check
./tests/run-all.sh
./build/run-swift-tests.sh modern /tmp/ntfsmac-modern-tests
./build/run-swift-tests.sh legacy /tmp/ntfsmac-legacy-tests
```

The shell suite builds and verifies the vendored runtime, helper packaging, security transaction,
CLI behavior, release wiring, and regression tests. Both Swift variants must compile and complete a
non-empty test run. Legacy source tests protect migration and historical behavior;
they do not produce a supported 3.1.3 Legacy installer.

Hosted macOS runners use `NTFSMAC_ROOTFS_BUILD_MODE=compile-only`: every shipped
binary and its source tests are built, but the native VM/package-install test is
explicitly skipped. The build verifies the bundled OCI and locked APK artifacts without claiming
they were installed. Run the default full mode on a physical Mac and test the
downloaded release artifact before publishing. This build-only option is not
included in the app and does not change runtime safety checks.

Run these commands sequentially. Packaging tests and real packaging both generate
`helper/GeneratedCLIManifest.swift`; overlapping them can put the wrong tree hash
in a bundle. The checked-in file must return to its placeholder afterward.

On macOS 26.6.2 the wrapper skips only `PopoverStateRenderTests` because of a known AppKit runner
hang. Run any changed render path directly with `swift test --filter <test-name>` and record it
separately; do not count a skipped render suite as executed.

## Beta 3 offline and MBR regression

The candidate must list both sibling Linux partitions on an MBR SSD, including empty
labels, in the GUI and CLI. The generic `Linux` label is a mount candidate; the guest
still detects the actual filesystem. LVM, RAID and swap remain excluded.

The offline tests verify the exact OCI graph and APK closure, missing/tampered assets,
symlinks and path escapes, stale initializers, atomic install replacement, and separate
cache identities. `offline-initializer.bats` imports/unpacks the real OCI under macOS
network denial and checks that rejected payloads preserve the cache. The installer
uses the shipped native verifier; Python is needed only for development/build tests.

Local evidence on 2026-09-12: native CGO initializer booted the VM into a fresh cache
under `sandbox-exec` with `(deny network*)`; Alpine signature-checked installation
completed and the exact 70-package manifest matched both locks. This proves offline
first initialization on the current physical Mac, separately from SSD mount/write
and final packaged-app acceptance.

The initial local Beta 3 candidate was build `31305`, Developer ID signed with BinaryBears
LLC. Its UDZO/zlib-9 DMG is 86,966,133 bytes; SHA-256
`590fc27edd84540b4bbde8bd88ad2ecdf233709f011501293fb957e8a105bcce`.
App/DMG contents, nested signatures, architecture/minimum-OS checks and checksum
passed with notarization explicitly disabled for this local candidate. No release,
tag, commit or push was made.

The source gate executed all 420 shell cases: 400 initially passed and 20 failed
because two synthetic lock fixtures omitted the new payload hash. Both fixtures
were corrected; the complete affected files then passed (36 Diagnose cases and
6 audit cases, including one new offline-patch drift regression). No unresolved
shell-case failure remains. Both Standard and Legacy Swift runs passed 335 tests;
Rust passed 61 tests. The 10 Python verifier cases run through the shell suite.

The exact app copied from that DMG replaced Beta 2 on the physical Mac, with the
old app retained. The GUI installed the helper/CLI, showed Beta 3 (31305), detected
both MBR Linux partitions, and mounted both as ext4 simultaneously. GUI Verified
Copy and CLI Copy/Verify passed on the authorized 1 MiB temporary files. Independent
GUI unmount/remount of the 124 GB partition preserved the other mount and passed
reread SHA-256. Diagnose confirmed healthy app/permissions, two active private-link
and PF sessions, and no unnecessary VPN route. The owner executed the standalone
privileged CLI cycle in Terminal: unmount/remount of the 875.7 GB partition left
the 124 GB mount available, both reread SHA-256 manifests matched, and the script
exited 0 with two protected sessions. Both temporary files were hash-checked and
removed; their absence was confirmed after sync. GUI Eject All then unmounted
both partitions. Final Diagnose was healthy with zero NFS mounts, zero security
sessions and the bridge down; the pre-existing FAT bootfs mount remained present.
GUI refresh still displayed both Linux partitions with working mount controls.
The DMG layout was also inspected in Finder. This hardware evidence covers the
current Apple M5/macOS 26.6.2 and this two-partition ext4 SSD; it is not new NTFS,
ext2/ext3 or macOS 14 runtime qualification. Notarization and remote CI remain
separate release gates.

## Issue #24 regression

The release must prove all related layers:

1. `init-rootfs` supplies application-owned registry files/directories and an empty auth context;
   it never inherits the user's containers or Docker configuration.
2. The functional resolver test passes with poisoned, unreadable registry and credential files.
3. The first runtime scan is single-flight, sequential, visibly preparing, and has a longer bounded
   timeout; recurring scans retain their shorter bound. No scan starts until the current helper has
   verified and staged the bundled CLI, even when an older executable is already installed.
4. Runtime failure has a dedicated retry view, while no media shows normal idle UI and neutral
   permission diagnostics.
5. A clean Standard app copied to `/Applications` passes the same flow, including when
   replacing an older Legacy installation.

Coverage lives in `runtime-config-isolation.bats`, `DriveScannerTests`, `FDAPromptCopyTests`,
`DiagnoseRunnerTests`, and `PopoverStateRenderTests`.

## Local package gate

`./build.command gui` builds only the Standard DMG. For a release candidate, use the official
BinaryBears Developer ID identity and verify:

- app and both helper versions match;
- host binaries are arm64 and the guest runtime is aarch64 Linux;
- nested signatures and helper identities match the selected variant;
- the DMG contains `ntfsmac.app`, the Applications symlink, and approved artwork;
- checksums verify and the mounted Finder layout is visually correct.

Official notarization uses `build/notarize-release.sh` through the release workflow. The downloaded
draft artifacts receive the final signature, stapling, Gatekeeper, checksum, and smoke checks.

## Real-drive smoke matrix

Use a backed-up or expendable external partition. Never format or repair a reporter's disk as part
of diagnosis.

For Standard, test:

1. clean install and helper approval/denial recovery;
2. relaunch without a drive shows **No drives found**, then a detected drive triggers Full Disk
   Access verification and any required guidance;
3. mount, write, flush/reread hash comparison, unmount, remount, and reread;
4. Diagnose, safe Quit, update check, and complete uninstall;
5. migration from an installed Legacy helper when applicable.

Repeat the Standard matrix after migration from an installed 3.1.2 Legacy helper.
Confirm no mount, helper process, security session, or test file remains afterward.

The 3.1.3 target is macOS 14+, Apple Silicon only. Run the driver matrix separately on
Sonoma and a current OS. Check every bundled host executable's minimum OS and then
execute the actual packaged runtime: a cross-build or VM desktop alone is not enough.
Newer-OS optimizations must remain gated and be exercised on their eligible OS.

## Safety-specific checks

- Multi-partition MBR regression: `DriveScannerTests` and `tests/cli/list-drives.bats` cover
  a FAT32 boot partition with two unlabeled Linux siblings, independent identifiers/sizes,
  Linux auto-detect routing, refresh/removal, and exclusion of LVM/RAID/swap. Check both Linux
  rows on the connected SSD; enumeration alone is not a successful mount or integrity test.
- Connect NTFS and exFAT simultaneously, including MBR `Windows_NTFS` and GPT Microsoft Basic
  Data partitions. Only confirmed NTFS belongs in the NTFS list. Repeat after reformatting the
  explicitly authorized disposable device; never infer a filesystem from a partition type or
  reuse a different device's metadata. Unknown metadata must not enable an NTFS mount action.
- Formatting tests require an explicitly named expendable device and a fresh physical-device
  identity check before each erase. Keep other attached disks outside the write/format targets.
- Dirty, hibernated, or Fast-Startup NTFS must refuse unsafe writable mounting and direct recovery
  to Windows; never offer a silent override.
- Hot-unplug, external unmount, and unavailable backend state must converge without a false green
  mount or another drive's teardown.
- Verified Copy must publish only after reread verification, retain recoverable partials on failure,
  and never overwrite an existing destination.
- Diagnostics must remain privacy-safe and distinguish confirmed failure from unavailable evidence.

Resource-dependent coverage that cannot be run must be marked blocked, not passed. Keep raw local
evidence private and publish only concise, privacy-reviewed results.

### Filesystem metadata follow-up (build 31306)

The candidate now probes the exact partition before mounting and displays the verified
filesystem and label. Inventory remains unprivileged; the authenticated helper uses a
non-blocking mutation lock, a two-second capability check and a five-second native metadata
probe. Unknown/unreadable metadata remains explicitly unverified, and a confirmed unsupported
filesystem is excluded. No format is cached by device number. An older runtime lacking the
command is rejected before its implicit mount fallback can run.

Local source checks: 344 Standard and 344 Legacy Swift tests pass, including identity mismatch,
missing/malformed/denied metadata, changed formats, unsupported formats, helper contention,
old-runtime rejection and mounted EXT4 refinement. The complete native build passes 62 Rust
tests and exact 70-package runtime verification. Native command checks under network denial
and an empty HOME confirm missing devices fail without runtime initialization. The final
complete shell suite passes all 428 cases, including native source builds, the offline
initializer, packaging, filesystem metadata and stalled-help regressions.

The exact Developer ID signed DMG was installed as build 31306. Its size is 86,985,355 bytes
and SHA-256 is `bb57d6df706128cbf8bce12767084e99391e53293e83ca77d7761f5dcf565a82`.
Release verification passed with notarization disabled. On the physical Mac, the GUI showed
`rootfs / EXT4` and `data / EXT4` before mounting, while both were mounted, and after the first
Eject All cycle. Both new 1 MiB temporary files passed CLI Copy/Verify, GUI unmount/remount,
and reread SHA-256; only those files were removed and their absence verified after sync.
Final runtime state is healthy with zero mounts/sessions and the bridge down.

The owner's standalone privileged `ntfsmac filesystem` check passed with exit 0: both
partition identities matched and the native probe returned EXT4 with labels rootfs/data,
without mounting or writing. A further GUI refresh/mount-both/Eject All cycle preserved the
already mounted FAT32 bootfs partition throughout. After Eject All, Refresh reconfirmed both
EXT4 labels; final diagnostics reported zero mounts/sessions and the bridge down. A separate
attached exFAT drive was inspected read-only and correctly excluded from ntfsmac candidates.
The official GitHub DMG was then downloaded, installed and tested before publication.
Developer ID signatures, stapling, Gatekeeper, checksum and Finder layout passed. Its runtime
initialized with networking denied and exactly 70 locked packages. GUI/helper update, both
EXT4 mounts, CLI copy, unmount/remount, SHA-256 reread and cleanup passed again; diagnostics
ended with zero mounts/sessions and the FAT32 sibling preserved. Release and CI workflows
passed, including 428 shell cases and 344 Swift tests per variant. The tested draft was
published unchanged as `v3.1.3-beta.3`, prerelease and not latest; stable remains `v3.1.2`.
Official DMG: 86,925,837 bytes; SHA-256
`064214aaf093cd041a19e3ccac8542459d5d34f4e9ca51e32e36cc6cbbee6fba`.
