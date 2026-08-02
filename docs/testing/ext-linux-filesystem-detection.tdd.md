# TDD Evidence: ext filesystem detection + exfat scope drop

**Source plan**: inline `/ecc:plan` (ext drives not surfaced in CLI/GUI picker).
**Date**: 2026-08-02.
**Branch**: `feat/ntfs-ext-strings-multi-mount`.

## User journeys

1. As a user with an ext2/3/4 external drive, I want ntfsmac to list it in the CLI
   picker and the GUI popover, so that I can mount it — same as NTFS.
2. As a user, I want exFAT drives excluded from ntfsmac's list, because macOS
   already reads/writes exFAT natively and ntfsmac should not re-handle it.

## Root cause

`anylinuxfs list` reports an ext partition's TYPE column as the GPT type name
`"Linux Filesystem"` when blkid can't resolve the superblock
(`vendor/.../diskutil/darwin.rs:132` `fs_type.unwrap_or(part_type)`; the GPT
name is in `LINUX_PART_TYPES`, `mod.rs:257`). GPT type `0FC63DAF`
(`"Linux Filesystem"`) covers **all** ext versions — ext2, ext3, ext4 — Apple
`diskutil` does not distinguish them.

Both parsers (`gui/Drives/DriveScanner.swift` `deriveFsTypeAndLabel`,
`cli/lib/list-drives.sh` derive branch) only special-cased `"Microsoft Basic
Data"` and `"BitLocker"` prefixes. For `"Linux Filesystem"` they fell to the
single-token branch, grabbed `"Linux"` as fstype, and the allow-set rejected
the row → ext drive invisible. Same shape as the previously-fixed NTFS
`"Microsoft Basic Data"` regression (commit 1be5bf2 aftermath).

## Task report

### Task A — Swift parser: ext GPT-name fallback
- **Summary**: add `"Linux Filesystem"` prefix branch → generic `"ext"` fstype; add `"ext"` to `allowedFsTypes`.
- **Validation**: `swift test --filter DriveScannerTests`
- **RED**: `parsesExtWithRealLinuxFilesystemTypeColumn` — `Expectation failed: (drives.count → 0) == 1` (row rejected).
- **GREEN**: all 12 DriveScannerTests pass.
- **Guarantee**: an ext partition whose TYPE column is `"Linux Filesystem"` (blkid unresolved) surfaces as a `Drive` with `fsType == "ext"` and correct label.

### Task B — bash parser: ext GPT-name fallback
- **Summary**: add `"Linux Filesystem"` `elif` branch → `"ext"`; add `"ext"` to `NTFSMAC_ALLOWED_FS_TYPES`.
- **Validation**: `bats tests/cli/list-drives.bats`
- **RED**: tests 5 & 6 failed at the `ext` fstype assertion (disk4s1 surfaced with wrong fstype).
- **GREEN**: 7/7 pass.
- **Guarantee**: `list_mountable_drives` emits `disk4s1<TAB><label><TAB>31.5 GB<TAB>ext` for the GPT-name ext row.

### Task C — exfat scope drop
- **Summary**: remove `"exfat"` from both allow-sets (macOS already read/write exFAT natively). Flip two fixtures needing a second unmounted drive (exfat → ext4): `PopoverStateRenderTests`, `tests/cli/mount.bats`.
- **Validation**: `swift test` (156 tests) + `bats tests/cli/` (117 tests)
- **RED**: `parsesMultipleDisksButExcludesExfatAlreadySupportedByMacOS` failed (`drives.count → 2`); bats test 7 failed (exfat surfaced).
- **GREEN**: 156/156 Swift, 117/117 bats.
- **Guarantee**: exfat partitions (when blkid resolves them) are dropped client-side; ntfs + ext + BitLocker remain.

## Test specification

| # | What is guaranteed | Test / command | Type | Result |
|---|---|---|---|---|
| 1 | ext `"Linux Filesystem"` TYPE (unlabeled) surfaces as fsType `"ext"` | `DriveScannerTests.swift: parsesExtWithRealLinuxFilesystemTypeColumn` | unit | PASS |
| 2 | ext `"Linux Filesystem"` TYPE with label keeps the label, not `"Filesystem"` | `DriveScannerTests.swift: parsesExtWithRealLinuxFilesystemTypeColumnAndLabel` | unit | PASS |
| 3 | ext `"Linux Filesystem"` row surfaces with fstype `ext` in bash picker | `tests/cli/list-drives.bats: surfaces ext with real 'Linux Filesystem' TYPE column` | unit | PASS |
| 4 | ext `"Linux Filesystem"` with label keeps `MyVol` in bash picker | `tests/cli/list-drives.bats: surfaces ext 'Linux Filesystem' TYPE with label` | unit | PASS |
| 5 | exfat partition excluded from Swift parser output | `DriveScannerTests.swift: parsesMultipleDisksButExcludesExfatAlreadySupportedByMacOS` | unit | PASS |
| 6 | exfat partition excluded from bash picker output | `tests/cli/list-drives.bats: excludes exfat` | unit | PASS |
| 7 | ext4 (blkid-resolved) still surfaces alongside NTFS | `DriveScannerTests.swift: parsesExt4PartitionWithCorrectFsType` | unit | PASS |
| 8 | btrfs/xfs/zfs/LUKS/LVM stay excluded | `DriveScannerTests.swift: excludesOutOfScopeFilesystemsFromUnfilteredList` | unit | PASS |
| 9 | GUI release build compiles clean | `swift build -c release` | build | PASS |

## Coverage and known gaps

- All ext versions (ext2/3/4) share the single GPT name `"Linux Filesystem"`; one
  prefix branch + generic `"ext"` fstype covers all of them. blkid-resolved ext
  (ext2/3/4 token) still passes via the existing single-token path.
- **Known caveat (exfat)**: `"Microsoft Basic Data"` GPT type covers ntfs AND
  exfat. When blkid resolves exfat → `"exfat"` → dropped by allow-set (handled).
  The rare GPT-fallback case (blkid empty for an exfat partition) can't
  distinguish ntfs from exfat — same limitation as anylinuxfs's own
  `--microsoft` filter. Not fixed; pre-existing.
- **MBR `"Linux"` type** (`mod.rs:261`) intentionally not mapped — out of scope,
  only GPT `"Linux Filesystem"` is.

## Task D — CLI: wire `--ignore-permissions` for ext on the mount path

- **Root cause**: ext is a real Unix fs with its own ownership bits. Unlike NTFS (which
  anylinuxfs remaps to the host user via `uid=/gid=`, `cmd_mount.rs` WINDOWS_LABELS.fs_types),
  ext gets no UID remap at mount — files stay owned by whatever uid/gid the disk stored, so
  the macOS user can't open `lost+found` or write. `--ignore-permissions` sets
  `all_squash,anonuid=0,anongid=0` on the NFS export (`vendor vmproxy/main.rs:1327`),
  mapping all client access to server root. User confirmed write works (slow — separate
  NFS-perf opt-in, out of scope here).
- **Summary**: `mount.sh` accepts `--ignore-permissions` (the helper's ext signal — skips the
  fstype probe); the picker captures the fstype column and threads it; the direct path probes
  `fs_type_for_device`; `--ignore-permissions` is auto-set **only** for ext-family and **only**
  when no `--fs-driver` was named. `run_anylinuxfs_mount` gains a 5th `ignore_perms` param.
  NTFS path untouched (ntfs-3g owns the uid/gid remap; adding all_squash there would change
  NTFS behavior — explicit "do not change the NTFS part").
- **Validation**: `bats tests/cli/list-drives.bats tests/cli/mount.bats`
- **RED**: tests 7–8 (`fs_type_for_device` command not found, 127); tests 27/29/30
  (no `--ignore-permissions` emitted / unknown option / picker doesn't forward it).
- **GREEN**: 31/31 pass.
- **Guarantee**: an ext drive mounted via the CLI (direct or picker) auto-gets
  `--ignore-permissions`; an NTFS drive never does; an explicit `--ignore-permissions` is
  forwarded as-is and skips the probe.

## Task E — GUI: ext mount — `FsDriver.ext` skips `--fs-driver`, adds `--ignore-permissions`

- **Root cause**: the helper always passed `--fs-driver ntfs-3g` (the `FsDriver` enum had no
  ext/auto case; `MountController` defaulted to `.ntfs3g`). ntfs-3g can't mount ext4, and
  `--ignore-permissions` was never sent.
- **Summary**: `FsDriver` gains `.ext` (reuses the existing `driver` XPC channel — no
  `HelperXPCProtocol`/`HelperClient` signature change). `HelperService.mount` branches: `.ext`
  → omit `--fs-driver`, append `--ignore-permissions`; `ntfs3g`/`ntfs3` → unchanged.
  `MountController.mount` / `RemountController.confirmRemount` derive the driver from
  `drive.fsType` when the caller passes none (`PopoverContentView.mountDrive`): ext-family →
  `.ext`, else `.ntfs3g`. `hasPrefix("ext")` is safe — `DriveListParser.allowedFsTypes` is
  the only fsType producer and the only value starting with "ext" is the ext family. NTFS
  path unchanged.
- **Validation**: `swift test` (160 tests)
- **RED**: `Type 'FsDriver' has no member 'ext'` (HelperTests + MountControllerTests).
- **GREEN**: 160/160 pass.
- **Guarantee**: a GUI ext mount sends `.ext` → the helper runs `ntfsmac mount <device>
  --ignore-permissions`; a GUI NTFS mount still sends `.ntfs3g` → `--fs-driver ntfs-3g`, no
  `--ignore-permissions`.

## Test specification (permission fix)

| # | What is guaranteed | Test / command | Type | Result |
|---|---|---|---|---|
| 10 | `fs_type_for_device` returns the fstype column for a device | `tests/cli/list-drives.bats: fs_type_for_device returns the fstype column for a given device` | unit | PASS |
| 11 | `fs_type_for_device` returns empty for an unknown device | `tests/cli/list-drives.bats: fs_type_for_device returns empty for an unknown device` | unit | PASS |
| 12 | direct CLI mount of an ext drive auto-passes `--ignore-permissions` | `tests/cli/mount.bats: auto-passes --ignore-permissions for an ext drive on the direct path` | unit | PASS |
| 13 | direct CLI mount of an NTFS drive does NOT pass `--ignore-permissions` | `tests/cli/mount.bats: does not pass --ignore-permissions for an NTFS drive on the direct path` | unit | PASS |
| 14 | explicit `--ignore-permissions` flag is forwarded and skips the probe | `tests/cli/mount.bats: explicit --ignore-permissions flag is forwarded to anylinuxfs and skips the probe` | unit | PASS |
| 15 | picker-chosen ext drive gets `--ignore-permissions` (no extra probe) | `tests/cli/mount.bats: picker-chosen ext drive gets --ignore-permissions` | unit | PASS |
| 16 | helper `.ext` driver → argv omits `--fs-driver`, has `--ignore-permissions` | `helper/Tests/HelperTests.swift: mountExtDriverOmitsFsDriverAndAppendsIgnorePermissions` | unit | PASS |
| 17 | helper `.ext` + readOnly → `--ignore-permissions --read-only` | `helper/Tests/HelperTests.swift: mountExtDriverWithReadOnlyAppendsReadOnlyAfterIgnorePermissions` | unit | PASS |
| 18 | helper ntfs3g still passes `--fs-driver`, no `--ignore-permissions` | `helper/Tests/HelperTests.swift: mountNtfs3gDriverStillPassesFsDriverAndNoIgnorePermissions` | unit | PASS |
| 19 | MountController derives `.ext` for ext drive, `.ntfs3g` for ntfs | `gui/Tests/MountControllerTests.swift: mountDerivesExtDriverForExtDriveAndNtfs3gForNtfs` | unit | PASS |
| 20 | release build compiles + app bundles | `swift build -c release` + `bash build/package-app.sh` | build | PASS |

## Merge evidence (checkpoint commits on this branch)

1. `test: ext 'Linux Filesystem' GPT-name TYPE column not surfaced (RED)` — Swift RED
2. `fix: surface ext drives via 'Linux Filesystem' GPT-name fallback (GREEN)` — Swift GREEN
3. `fix: surface ext drives via 'Linux Filesystem' GPT-name fallback in CLI (GREEN)` — bash GREEN
4. `test: exfat must be excluded (macOS reads/writes exFAT natively) (RED)` — exfat RED
5. `fix: drop exfat from mountable scope (macOS reads/writes exFAT natively) (GREEN)` — exfat GREEN
6. `fix: wire --ignore-permissions for ext on CLI mount path (GREEN)` — CLI perm GREEN
7. `fix: GUI ext mount — FsDriver.ext skips --fs-driver, adds --ignore-permissions (GREEN)` — GUI perm GREEN