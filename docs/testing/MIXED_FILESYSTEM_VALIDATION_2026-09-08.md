# Mixed-filesystem fix and hardware qualification — 2026-09-08

## Scope and provenance

Local branch `codex/fix-mixed-filesystem-detection` starts at dependency-refresh checkpoint
`a7066b8`, in the existing isolated worktree. It includes `dev` commit `b0ff6cd` (3.1.2,
including the separately developed issue #24 fixes). `dev` itself is unchanged. The product
version remains 3.1.2; local test build **31208** identifies the new app and both helpers.
This is not a release announcement or a claim of completed release acceptance.
Read-only `git ls-remote origin` on this date also confirmed remote `dev` at `b0ff6cd`.

The owner authorized writes on expendable MobileData and formatting only TEST_USB. Retroid_SD
was a read-only observation/control, never a formatting or write target. Disk identifiers,
external/physical status, USB media identity and capacity were checked before formatting.

## Fix

The old backend falls back from an unsuccessful unprivileged libblkid probe to partition type.
Both MBR `Windows_NTFS` (0x07) and GPT `Microsoft Basic Data` can contain NTFS **or exFAT**.
Both UI and CLI parsers previously converted those ambiguous values to NTFS. The installed old
app reproduced the report: three attached drives appeared as NTFS, although two were exFAT.

The build now applies a checked transformation only to the disposable anylinuxfs source copy:

- prefer libblkid filesystem evidence;
- for unresolved Windows-family partitions, obtain macOS `FilesystemType` using
  `diskutil info -plist` and require an exact `DeviceIdentifier` match;
- missing, malformed or mismatched metadata becomes unknown, never inferred NTFS;
- both frontend parsers also reject ambiguous Windows-family names from stale backends;
- candidate dependency audits reject upstream patch-marker drift.

The upstream submodule and all dependency pins remain unchanged by this fix. Existing Linux
family discovery behavior is not rewritten. This corrects identification; it does not add native
exFAT/APFS/HFS+ support to ntfsmac, because macOS already handles those filesystems.

## Dependencies carried by this build

The [dependency ledger](DEPENDENCY_REFRESH_2026-08-30.md) records individual update/test
checkpoints. Exact commits, checksums and graph hashes are in `build/sources.lock` and the Alpine
manifests. This follow-up does not combine additional dependency updates.

| Component | Selected version / change |
| --- | --- |
| ntfs-3g, libraries and utilities | 2026.2.25-r0 → **2026.7.7-r0** |
| anylinuxfs / vmproxy | 0.18.0 → **0.19.0**, source `0a4472bd7507c1f9a57894547c1af7ea4382d99f` |
| init-rootfs gRPC | 1.81.1 → **1.82.1** |
| Alpine | **3.24.1**, immutable arm64 image digest; 16 base + 54 add-on packages |
| Alpine libexpat | **2.8.4-r0**, replacement artifact relocked separately |
| vmnet-helper | 0.12.0 → **0.13.0**, commit and archive SHA-256 locked |
| gvproxy | **0.8.9 retained**; x/crypto security overlay **0.55.0**, complete graph hash |
| libkrun | **1.19.3 retained**, exact registry checksum |
| libkrunfw | **6.12.62-rev1 retained**, exact kernel/modules artifact hashes |
| Go / Rust | **1.27.0 / 1.98.0**, exact build toolchain pins |
| Rust security overlays | anyhow **1.0.104**, crossbeam-epoch **0.9.20**, plist **1.10.0**, quick-xml **0.41.0**, lru **0.18.3**; complete lockfile hashes |
| CI actions | Reviewed checkout/setup-go/Rust/Pages implementations pinned to immutable commits |

Practical improvements are security fixes, reproducible guest installation and cache identity,
dependency provenance checks, and correct mixed-drive discovery. No throughput improvement or
new filesystem feature is claimed without a corresponding benchmark/acceptance test. Existing
Verified Copy and issue #24 runtime/setup fixes are inherited from `dev`, not invented by these
dependency bumps. Previously recorded bincode maintenance and OpenPGP advisory limitations are
not claimed resolved; no new advisory scan was performed in this follow-up.

## Local source and package checks

| Gate | Result |
| --- | --- |
| Complete Bats suite | PASS **382/382**, exit 0 |
| Standard Swift suite | PASS **324/324** |
| Legacy Swift suite | PASS **324/324** |
| Upstream Rust with build transformations | PASS **61/61**, including 3 new filesystem regressions |
| Focused drive-list / dependency-policy tests | PASS **13/13** and **5/5** |
| Build, syntax, ShellCheck, patch drift and whitespace checks | PASS |
| Standard and Legacy app packaging | PASS, both build **31208** |
| Both nested app signatures | PASS, local BinaryBears Developer ID |

`PopoverStateRenderTests` remain excluded by the documented macOS 26.6.2 runner guard, not counted
as executed. The isolated scratch-home rootfs assembly still reports the known pre-guest `EINVAL`;
the installed native runtime using the real user cache successfully boots, mounts and writes.
No new build-31208 DMG/Finder acceptance or Apple notarization has been performed.

## Hardware evidence

Standard build 31208 was copied to `/Applications/ntfsmac.app`; the previous app was preserved
in a local backup folder. The app's existing helper update/staging flow installed the matching
runtime. Installed anylinuxfs and packaged vendor binary SHA-256 match:
`825fca55151f18aa71977e28260f5a10e4e8acd373ce263ecf1a19f3c222166e`.
The new GUI shows **one** NTFS drive (MobileData) with both exFAT controls still connected.

| Media / filesystem | Identification | Write, flush, unmount, remount, reread SHA-256 |
| --- | --- | --- |
| MobileData / NTFS, Standard app new helper | PASS | PASS, 16 MiB; exact test file removed |
| TEST_USB / exFAT GPT | Correctly excluded from NTFS list | PASS, 16 MiB through macOS native mount |
| TEST_USB / FAT32 MBR | Correctly excluded | PASS, 16 MiB through macOS native mount |
| TEST_USB / HFS+ GPT | Correctly excluded | PASS, 16 MiB through macOS native mount |
| TEST_USB / APFS GPT | Correctly excluded | PASS, 16 MiB through macOS native mount |
| Retroid_SD / exFAT MBR | Correctly excluded | Not written; observation-only control |
| TEST_USB / NTFS, ext2, ext3, ext4 | Pending privileged format matrix | Pending |
| Legacy app hardware mount/write | Pending | Pending |

The MobileData test used the actual newly installed Standard app and reviewed XPC helper, not the
old installed version. SHA-256 before/after remount was
`341aacac661ccb210720bedaa9ead5d668fe5ea41a73532fc147c71e34040df1`.
Mounted diagnostics reported build 31208, ntfs-3g 2026.7.7-r0, pinned initialized Alpine 3.24.1,
one NFS mount/session and enforced private-link/soft-NFS/PF policy. After cleanup and unmount,
diagnostics were healthy with zero NFS mounts and zero security sessions.

An earlier command-line harness attempt failed before writing because it specified an absent
custom mount directory. The harness was corrected to use automatic mount-point selection. That
failed attempt is not counted as a hardware pass; the subsequent GUI test above completed.
The first TEST_USB privileged matrix attempt stopped after unmount because macOS `gpt` has no
`change` subcommand. No format occurred in that attempt. The harness now uses the existing
Microsoft partition type for NTFS and guarded exact-range `remove`/`add` for the Linux type.

Raw temporary logs remain local (`/tmp/ntfsmac-mixed-*`, `/tmp/ntfsmac-test-usb-*`, and
`/tmp/ntfsmac-hardware-*`). Do not publish them without privacy review. The temporary e2fsprogs
1.47.4 test tool came from the Homebrew bottle cache and was extracted in `/tmp`, not added to
the app's dependencies or installed globally.

## Remaining release gates

Complete the explicitly authorized TEST_USB NTFS/ext matrix and Legacy hardware acceptance,
then perform release-artifact, DMG/Finder, notarization/stapling and downloaded-artifact checks
once the release strategy is approved. Longer transfers, hot-unplug and dirty/hibernated-media
tests are not covered by the 16 MiB acceptance above. No push, hosted CI run, release, issue
comment or other remote publication was performed by this work.
The first local commit attempt was blocked by the locked SSH signing key; signing was not
disabled and Git configuration was not changed.
