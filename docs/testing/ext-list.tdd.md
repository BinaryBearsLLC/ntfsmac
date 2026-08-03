# TDD Evidence: ext2/3/4 list support (CLI + GUI)

**Source plan:** inline `/ecc:plan` output (this session), narrowed by the user to
"Only add ext4 / ext3 / ext2 support to cli and GUI. Forget the other requests including
bitlocker ntfs" → "go. use ext4 path. Let's keep the name as is". No `*.plan.md` file was
used; journeys were derived during this run from the approved plan summary.

## User journeys

1. As a user with an ext4/ext3/ext2 external drive, I want it to appear in the CLI
   `mount` picker and the GUI drive list, so that I can mount it the same way as NTFS.
2. As a user, I want out-of-scope filesystems (btrfs/xfs/zfs/LUKS/LVM) to stay hidden, so
   the picker only shows what ntfsmac actually mounts.
3. As a user, mounting an ext partition should need no `--fs-driver` flag (the guest kernel
   auto-detects via blkid + built-in ext4 driver), identical to the existing NTFS default
   path.

## Task report

### Task 1 — RED: ext list/filter tests (CLI bats + GUI Swift)

- **Summary:** added failing tests asserting ext4 is surfaced, btrfs is excluded, and
  `anylinuxfs list` is called without `--microsoft`.
- **Validation run:** `bats tests/cli/list-drives.bats` and
  `swift test --filter DriveScannerTests --build-path /tmp/ntfsmac-swift-build`.
- **RED evidence (CLI):**
  ```
  not ok 1 list_mountable_drives surfaces ext4 partitions alongside NTFS
  not ok 3 list_mountable_drives calls anylinuxfs list without --microsoft
  ok   2 list_mountable_drives excludes out-of-scope filesystems (btrfs filtered client-side)
  ```
  Test 2 passed vacuously in RED (current `--microsoft` filter returns no btrfs); it
  becomes meaningful at GREEN as a leak-guard.
- **RED evidence (GUI):**
  ```
  ✘ excludesOutOfScopeFilesystemsFromUnfilteredList() — ["disk4s2","disk4s3","disk4s4"] != ["disk4s2","disk4s3"]; btrfs surfaced
  ✘ driveScannerCallsBareListWithoutMicrosoftFilter() — ["list","--microsoft"] != ["list"]
  ✔ parsesExt4PartitionWithCorrectFsType() — passed (parser already fstype-agnostic)
  ```
- **Checkpoint commit:** `8043fb0` (CLI RED), `f84bc17` (GUI RED).

### Task 2 — GREEN: widen list filter to NTFS+ext

- **Summary:** `cli/lib/list-drives.sh` and `gui/Drives/DriveScanner.swift` switched from
  `anylinuxfs list --microsoft` to bare `anylinuxfs list` + client-side allow-set
  `{ntfs, exfat, BitLocker, ext2, ext3, ext4}`. `mount.sh` unchanged (ext path already
  emits no `-t`/`--fs-driver` — `nfs-mount.sh:79` only adds `-t` when fs_driver non-empty).
- **Validation run:** `bats tests/cli/*.bats` (full suite) and
  `swift test --filter DriveScannerTests --build-path /tmp/ntfsmac-swift-build`.
- **GREEN evidence (CLI):** `tests/cli/list-drives.bats` → 3/3 ok; full CLI suite 112 pass,
  0 fail (`bats tests/cli/*.bats | grep -c '^ok'` → 112, no `not ok`).
- **GREEN evidence (GUI):** `Test run with 9 tests in 0 suites passed` — all DriveScanner
  tests green, including the two previously-RED tests.
- **Checkpoint commit:** `1be5bf2`.

### Task 3 — Kernel-module gate (ext4 built into the kernel image)

- **Summary:** verified `ext4.ko`/`jbd2.ko`/`mbcache.ko` are built into the vendored
  libkrunfw kernel image, so ext2/3/4 mount works in the guest with no new kernel build.
- **Validation run:** `brew install squashfs && unsquashfs -ls vendor/kernel/modules.squashfs`
  then extract + read `modules.builtin`.
- **Evidence:** `modules.squashfs` contains only `fs/zfs/{spl.ko,zfs.ko}` as loadable modules
  plus a `modules.builtin` manifest. `modules.builtin` lists
  `kernel/fs/ext4/ext4.ko`, `kernel/fs/jbd2/jbd2.ko`, `kernel/fs/mbcache.ko` as **built-in**
  — the ext4 driver (mounts ext2/3/4) is in the kernel `Image`. Gate passed. (The image
  also has xfs/btrfs/f2fs/ntfs3 built-in and zfs loadable, deliberately NOT wired into the
  allow-set — ext is the approved scope.)

### Task 4 — Docs

- **Summary:** README tagline + Why section; AUDIT.md new "ext2/3/4 mount support" section
  recording the feature decision (no package, no vendored source, no XPC/signing change,
  kernel-module verification).
- **Checkpoint commit:** `238d75a`.

## Test specification

| # | What is guaranteed | Test file / command | Type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | ext4 partitions surface in the CLI picker alongside NTFS | `tests/cli/list-drives.bats: surfaces ext4` | unit (bats) | PASS | `bats tests/cli/list-drives.bats` → ok 1 |
| 2 | Out-of-scope btrfs is filtered client-side (not surfaced) | `tests/cli/list-drives.bats: excludes out-of-scope` | unit (bats) | PASS | same → ok 2 |
| 3 | CLI calls `anylinuxfs list` without `--microsoft` | `tests/cli/list-drives.bats: calls list without --microsoft` | unit (bats) | PASS | same → ok 3 |
| 4 | ext4 partition parses to `Drive.fsType == "ext4"` | `gui/Tests/DriveScannerTests.swift: parsesExt4PartitionWithCorrectFsType` | unit (Swift Testing) | PASS | `swift test --filter DriveScannerTests` |
| 5 | Out-of-scope btrfs is dropped by `DriveListParser.allowedFsTypes` | `gui/Tests/DriveScannerTests.swift: excludesOutOfScopeFilesystemsFromUnfilteredList` | unit (Swift Testing) | PASS | same |
| 6 | `DriveScanner.refresh()` calls `["list"]` not `["list","--microsoft"]` | `gui/Tests/DriveScannerTests.swift: driveScannerCallsBareListWithoutMicrosoftFilter` | unit (Swift Testing) | PASS | same |
| 7 | Existing NTFS/exfat/whole-disk/header parsing unchanged | `tests/cli/mount.bats`, `gui/Tests/DriveScannerTests.swift` (pre-existing tests) | regression | PASS | full CLI suite 112/112; GUI 9/9 |
| 8 | ext4 driver present in the kernel image (mount will succeed) | `unsquashfs -ls … modules.squashfs` + `modules.builtin` | manual gate | PASS | ext4.ko/jbd2.ko/mbcache.ko built-in |

## Coverage and known gaps

- No line-coverage tool is configured for the bats CLI suite or the Swift tests in this
  repo (no c8/jacoco/xcov wired); the project's 80% rule is met qualitatively: both
  branches of the new allow-set filter (fstype in set → keep; fstype not in set → drop)
  and the scanner arg change are each exercised by a dedicated test.
- **Untested at the unit level (intentional):** a real end-to-end ext4 mount (requires a
  physical ext4 partition + a running libkrun VM). The kernel-module gate (Task 3) is the
  substitute evidence that the guest can mount ext; the list/mount plumbing is covered by
  the stubbed tests above. A live mount test belongs in a manual/CI acceptance pass, not
  this TDD cycle.
- **Known environment caveat:** Swift builds on a path-with-spaces volume hit a `.build`
  race (`runner.swift modified during the build` — same class of issue documented in
  `build/AUDIT.md`'s rootfs-build findings). Worked around by building on a path without
  spaces via `--build-path /tmp/ntfsmac-swift-build`, mirroring the AUDIT fix. Not a code
  issue.

## Merge evidence

Four checkpoint commits on `main`, in order: `8043fb0` (CLI RED) → `f84bc17` (GUI RED) →
`1be5bf2` (GREEN) → `238d75a` (docs). If squashed, preserve this summary in the PR/squash body.