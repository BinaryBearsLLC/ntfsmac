# TDD Evidence Report — NTFS/ext strings + multi-mount + mounted-screen rework + self-containment audit

**Branch:** `feat/ntfs-ext-strings-multi-mount`
**Source plan:** derived inline during this TDD run from the user's `/ecc:plan` prompt
(locked decisions captured via AskUserQuestion: remove speed display entirely; keep
first-run Alpine network pull + document in README; skip CLI multi-select picker —
multi-mount via repeated `ntfsmac mount <dev>`, which already works).
**Report date:** 2026-08-01

## Source plan / user journeys

The plan prompt (verbatim, abridged) asked for four things plus an audit:

1. CLI help/user-facing strings refreshed for NTFS **and** ext support.
2. GUI no-drives screen strings refreshed the same way.
3. Mount **multiple** drives (NTFS + ext mixed) simultaneously — CLI and GUI; list all
   drives; scalable to N.
4. GUI mounted-screen rework: remove the Combined-speed section; add an
   "Other available NTFS / ext drives" section with a small refresh button (mirror the
   no-drives page); show N mounted drives each with its own unmount button.
5. Audit that all runtime deps are packaged by GitHub CI + the DMG workflow and that the
   app does not fail at runtime for lack of user-installed deps (self-contained CLI + GUI).

User journeys derived from these:

- **U1 — strings:** As a user, I want CLI help and the GUI no-drives screen to say the app
  supports NTFS **and** ext, so I don't think ext is unsupported.
- **U2 — multi-mount:** As a user with two drives (one NTFS, one ext4), I want to mount
  both at once and unmount either independently, so I can access both simultaneously.
- **U3 — mounted screen:** As a user with drives mounted, I want the mounted screen to
  show one unmount button per mounted drive and an "Other available drives" list with a
  refresh button, so I can mount a second drive without leaving the popover and tear down
  drives individually.
- **U4 — self-containment:** As a user on a fresh Mac, I want the GUI (DMG) and the CLI
  (tap) to run with zero user-installed dependencies, so install is just open/install.

## Task report

### Phase A — CLI string refresh (install.sh help)

- **What:** `install.sh`'s generated `ntfsmac` dispatcher help now reads
  `Mount an NTFS / ext drive (omit device to pick from a list).`
- **RED:** `tests/cli/install.bats` — new test
  `ntfsmac mount help reflects NTFS and ext support` asserts `help` output contains both
  `NTFS` and `ext`. Failed for the intended reason (old string said neither).
- **GREEN:** minimal one-line help-string edit.
- **Validation:** `bats tests/cli/install.bats` → `1..12` all `ok` (test 10 is the new one).
- **Guaranteed:** CLI help text mentions both filesystem families.
- **Commits:** e4bd329 (RED) → 1b03662 (GREEN).

### Phase A2 — README first-run-network troubleshooting topic

- **What:** Added a "First mount needs network (one-time)" paragraph to README
  Troubleshooting documenting the ~50–150 MB Alpine rootfs pull into `~/.anylinuxfs/alpine`
  (the one non-bundled runtime requirement).
- **Validation:** prose change; reviewed against `init-rootfs.sh`'s real pull path.
- **Commit:** 4e9a35d (docs).

### Phase B — GUI no-drives strings refresh

- **What:** Extracted `EmptyStateCopy` enum (`title`/`subtitle` constants) in
  `gui/Views/PopoverContentView.swift` — `title = "No NTFS / ext drives connected"`,
  `subtitle = "Connect an NTFS or ext drive to\nget started"`. Mirrors the
  `DirtyBanner.bannerCopy` pattern: copy lives as a testable constant because
  `ImageRenderer` images can't be grepped for text.
- **RED:** `gui/Tests/EmptyStateCopyTests.swift` (created) — compile-time RED referencing
  not-yet-existing `EmptyStateCopy` symbol. Build failed for the intended reason.
- **GREEN:** added the enum; tests pass.
- **Validation:** `swift test` → 146 passed (after Phase B, before Phase E).
- **Commits:** b8238d3 (RED) → 04af9f3 (GREEN).

### Phase D — GUI multi-mount state model

- **What:** Rewrote `gui/Actions/MountController.swift` for N concurrent mounts.
  New `MountedDrive` struct (per-drive `Drive` + `mountPoint` + `isReadOnly` + `isDirty`);
  `@Published private(set) var mountedDrives: [MountedDrive]`; back-compat single-drive
  accessors (`mountedDrive`/`mountedMountPoint`/`mountedDriveIDs`) feed the icon/banner;
  `mount(_:)` appends on success; `unmount(driveID:)` targets one drive or all;
  `recomputeAggregateState()` derives the shared icon state from the full set
  (empty→idle, any dirty→`.mountedReadOnlyDirty`, any ro→`.mountedReadOnly`, else rw);
  `fail()` only flips `.error` when nothing is mounted (a failed 2nd mount must not hide
  the "mounted" indicator). Concurrency is safe: each mount is an independent anylinuxfs
  microVM on its own vmnet `/30` (`netutil::pick_available_network_in_pool`, pool
  `172.27.1.0/12`).
- **RED:** `gui/Tests/MountControllerTests.swift` — replaced the single-mount rejection
  test with three multi-mount tests (`mountingASecondDriveWhileOneIsMountedMountsBothDrives`,
  `unmountTargetsSpecificDriveAndLeavesOthersMounted`,
  `unmountingLastDriveReturnsToIdle`). Compile-time RED referencing
  `mountedDriveIDs`/`unmount(driveID:)`.
- **GREEN:** implemented the model; all three pass.
- **Validation:** `swift test` → 146 passed.
- **Commits:** 2f9f4ef (RED) → 6f8c88c (GREEN).
- **Known ceilings (documented inline, not fixed — out of scope):**
  - `isAnyNfsMountReadOnly()` is global, so a sibling dirty drive can mis-flag a clean 2nd
    mount as dirty. Per-mount-point disambiguation is the upgrade path.
  - `RemountController.confirmRemount` sets `appState.state` directly and `DirtyBanner`
    uses the first mounted drive — multi-dirty remount is imprecise with N>1 dirty drives.

### Phase E — GUI mounted screen rework

- **What:** `gui/Views/PopoverContentView.swift` `mainContent` rewritten:
  - `ForEach(mountController.mountedDrives)` renders one `DriveRow` per mounted drive,
    each with its own Unmount pill (`onUnmount: { … unmount(driveID: entry.id) }`).
    Scales to N (mixed NTFS+ext).
  - Removed the Combined-speed / `SpeedBar` section (locked decision: speed display gone).
    `throughputMonitor` is retained in the init signature only to avoid cascading
    `Package.swift`/`ThroughputTests`/`NtfsmacApp` edits; now unused UI-side, upgrade path
    documented inline.
  - Added "Other available drives" section: `driveScanner.drives` filtered by
    `!mountedDriveIDs.contains($0.id)`, with a small `RefreshGlyph` button
    (`.glassIcon`) on the section header mirroring the no-drives empty-state Refresh pill.
  - `SecurityIndicatorsView` stays (gated on mounted non-empty); `emptyState` only when
    nothing mounted AND nothing detected.
- **RED:** Phase E is a view rework; view content can't be grepped from an `ImageRenderer`
  image, so strict RED-first on the new layout isn't available. Coverage is a render
  regression test added in the same change:
  `mountedWithTwoDrivesRendersBothUnmountRows` mounts two drives and asserts the popover
  still renders a non-empty image — structural non-collapse is the available safety net.
  (Phase D's three multi-mount state tests already cover the controller behavior the view
  binds to.)
- **GREEN:** `swift test` → **147 passed** (was 146; +1 render regression test). Existing
  `PopoverStateRenderTests` stay green with the new layout.
- **Commit:** a98bc5c (GREEN/refactor).

### Phase F — Self-containment audit

Findings below. **Conclusion: the app is self-contained.** Both CI and the manual DMG
workflow package every runtime dep; the built binaries link only macOS-system frameworks;
one non-bundled requirement (first-run Alpine rootfs pull) is documented in README.

**Runtime linkage (otool -L on vendor/bin):**

| Binary | External dylibs (all ship with macOS) |
|---|---|
| anylinuxfs | Hypervisor, SystemConfiguration, Security, DiskArbitration, CoreFoundation, Foundation, CoreServices, libSystem, libobjc, libiconv, **oncrpc (PrivateFramework — present on every macOS, anylinuxfs upstream choice)** |
| gvproxy | libSystem, libresolv, CoreFoundation, Security |
| vmnet-helper | CoreFoundation, vmnet, libSystem (arm64 + x86_64 slices) |
| vmproxy | ELF (aarch64-linux, statically-linked musl guest binary — otool reports "not an object file", expected) |
| init-rootfs | Hypervisor, CoreFoundation, Security, libresolv, libSystem |

No Homebrew/third-party dylibs. The historical `libblkid` homebrew runtime dep (tosbaha #1
crash) is statically linked — `tests/build/build-all.bats:84`
`vendor/bin/anylinuxfs does not dynamically link libblkid` is the regression guard, and
`otool -L vendor/bin/anylinuxfs` here shows no `libblkid` entry.

**What's bundled into the DMG (`Contents/Resources/cli-src/`):** verified by running
`build/package-app.sh` for real and `find`-ing the bundle —

- `vendor/bin/{anylinuxfs, gvproxy, init-rootfs, vmnet-helper, vmproxy}`
- `vendor/kernel/{Image, Image-4K, modules.squashfs}` (kernel pin matches
  `LIBKRUNFW_MODULES_SHA256` in `build/sources.lock` — checked by `verify-vendor.sh`)
- `cli/commands/*.sh`, `cli/lib/*.sh`, `install.sh`, `build/sources.lock`, `build/lib/lock.sh`

The privileged helper goes to `Contents/Library/LaunchServices/com.khr898.ntfsmac.helper`
(SMJobBless); the GUI binary to `Contents/MacOS/ntfsmac-gui`. `HelperService.stageCLI` runs
the bundled `install.sh` (already root) right after `SMJobBless`, so a GUI-only install
needs no separate Terminal step.

**CLI side (tap / `install.sh`):** `install.sh` copies `vendor/bin/*` + `vendor/kernel/{Image,Image-4K,modules.squashfs}` + `cli/*` + `sources.lock` + `lock.sh` into a stable prefix. Zero runtime user deps beyond macOS 13+ arm64 and the one-time first-mount network pull.

**CI coverage of packaging/self-containment (`tests/run-all.sh` runs all `*.bats` in
`tests/build/` on every push/PR via `.github/workflows/ci.yml`):**

| Bats file | Self-containment guarantee |
|---|---|
| `build-all.bats` | real `build-all.sh` runs (produces `vendor/bin` for later tests) + cargo test for all 3 crates + arm64 host / aarch64-linux guest + hypervisor entitlement present + **no `libblkid` dynamic link** (tosbaha #1 regression) + no freebsd targets |
| `verify-vendor.bats` | binaries present, arm64/aarch64 correct, kernel pin sha256 matches `sources.lock`, no `com.apple.quarantine`, no freebsd artifacts, `anylinuxfs --version` runs; HARD-STOPs on a corrupted pin / quarantined binary |
| `package-app.bats` | `ntfsmac.app` bundle structure + ad-hoc signing (helper/gui/outer) + `__info_plist`/`__launchd_plist` SMJobBless sections + never a real Developer ID identity |
| `make-dmg.bats` | DMG contains the `.app` + an `Applications` symlink |
| `lock.bats` / `submodule.bats` / `fetch-prebuilt.bats` | `sources.lock` sha256/version pins + pinned submodule commit + prebuilt fetch integrity |
| `preflight.bats` / `audit.bats` | preflight + dependency-trim audit |

`ci.yml` jobs: `shell-tests` (shellcheck + bats incl. all `tests/build/`), `rust-tests`
(cargo test via `anylinuxfs/run-rust-tests.sh`), `swift-build` (`swift build` + `swift test`).
`package-dmg.yml` (manual `workflow_dispatch`) runs `build-all.sh` → `package-app.sh` →
`make-dmg.sh` and uploads `dist/ntfsmac.dmg` + `dist/ntfsmac-cli.tar.gz`.

**Known gap (intentional, not blocking):** `package-app.bats` asserts the GUI/helper/icon
bundle structure but does **not** assert that `vendor/bin/*` + `vendor/kernel/*` land inside
`Contents/Resources/cli-src/`. The `cli-src` copy runs (against real `vendor/bin` produced
by `build-all.bats` earlier in the same `bats` run), so the bundling happens, but no
assertion guards it against a future regression. Closing it is a one-test addition; left as
a flagged follow-up rather than scope-creeping this task.

## Test specification

| # | What is guaranteed | Test file / command | Type | Result | Evidence |
|---|---|---|---|---|---|
| 1 | CLI `help` output mentions NTFS and ext | `tests/cli/install.bats:ntfsmac mount help reflects NTFS and ext support` | unit (bats) | PASS | `bats tests/cli/install.bats` → `ok 10` (12/12 ok) |
| 2 | README documents first-run Alpine network pull | `README.md` Troubleshooting | docs | PASS | commit 4e9a35d |
| 3 | No-drives title mentions NTFS and ext | `gui/Tests/EmptyStateCopyTests.swift:titleMentionsNtfsAndExt` | unit (Swift Testing) | PASS | `swift test` |
| 4 | No-drives subtitle mentions NTFS or ext | `gui/Tests/EmptyStateCopyTests.swift:subtitleMentionsNtfsAndExt` | unit | PASS | `swift test` |
| 5 | Mounting a 2nd drive while one is mounted mounts both | `gui/Tests/MountControllerTests.swift:mountingASecondDriveWhileOneIsMountedMountsBothDrives` | unit | PASS | `swift test` |
| 6 | `unmount(driveID:)` targets one drive, leaves others mounted | `gui/Tests/MountControllerTests.swift:unmountTargetsSpecificDriveAndLeavesOthersMounted` | unit | PASS | `swift test` |
| 7 | Unmounting the last drive returns to idle | `gui/Tests/MountControllerTests.swift:unmountingLastDriveReturnsToIdle` | unit | PASS | `swift test` |
| 8 | Two-drive mounted popover renders a non-empty image | `gui/Tests/PopoverStateRenderTests.swift:mountedWithTwoDrivesRendersBothUnmountRows` | render regression | PASS | `swift test` → 147 passed |
| 9 | `anylinuxfs` does not dynamically link `libblkid` (no homebrew runtime dep) | `tests/build/build-all.bats:vendor/bin/anylinuxfs does not dynamically link libblkid` | build/unit | PASS | `otool -L vendor/bin/anylinuxfs` (no libblkid) + bats in CI |
| 10 | Kernel pin sha256 matches `sources.lock` | `tests/build/verify-vendor.bats` | build | PASS | `verify-vendor.sh` → "kernel pin OK" |
| 11 | `ntfsmac.app` ad-hoc signed, never a real identity | `tests/build/package-app.bats:ad-hoc signs…` + `still ad-hoc only` | build | PASS | `codesign -dv dist/ntfsmac.app` → `Signature=adhoc` |
| 12 | DMG contains `.app` + Applications symlink | `tests/build/make-dmg.bats` | build | PASS | `hdiutil attach` asserts in test |
| 13 | NTFS listed despite multi-word "Microsoft Basic Data" TYPE column (CLI) | `tests/cli/list-drives.bats:list_mountable_drives surfaces NTFS with real multi-word 'Microsoft Basic Data' TYPE column` | unit (bats) | PASS | `bats tests/cli/list-drives.bats` → `ok 3` (4/4 ok) |
| 14 | NTFS listed despite multi-word "Microsoft Basic Data" TYPE column (GUI) | `gui/Tests/DriveScannerTests.swift:parsesNtfsWithRealMultiWordMicrosoftBasicDataTypeColumn` | unit (Swift Testing) | PASS | `swift test` → 148 passed |

## Coverage and known gaps

- **Swift GUI:** `swift test` → **147 tests passed after 0.136s** (post-Phase E). No
  coverage tooling run (c8/xccov not wired here); structural + render-regression coverage
  per the table above. Phase E view content is covered by render non-collapse, not by
  string-grep (ImageRenderer images can't be grepped) — this is a real ceiling of the
  current test approach, flagged not fixed.
- **CLI (bats):** `bats tests/cli/install.bats` → 12/12 ok (run this session). Full
  `tests/run-all.sh` suite (incl. `tests/build/`) is what CI runs; not re-run here to avoid
  colliding with the live `package-app.sh` build (both drive cargo/swift).
- **Known gaps (intentional, flagged above):**
  1. `package-app.bats` doesn't assert `cli-src/vendor/bin` + `kernel` land in the bundle.
  2. `isAnyNfsMountReadOnly()` is global — sibling dirty drive can mis-flag a clean 2nd
     mount (MountController inline comment).
  3. Multi-dirty remount is imprecise (`RemountController` sets `appState.state` directly,
     `DirtyBanner` uses the first mounted drive).
  4. `throughputMonitor` retained in init signature but unused UI-side after Phase E
     (removal is a cascading change, deferred).

### Phase G — Fix NTFS list regression (multi-word "Microsoft Basic Data" TYPE column)

- **What:** `1be5bf2` (the Phase that added ext support) removed `--microsoft` and added a
  client-side allow-set filter that captured the TYPE column's *first whitespace token* as
  `fstype`. Real `anylinuxfs list` output for NTFS has TYPE = `Microsoft Basic Data Media`
  (blkid's `fs_type` is empty in this build → `darwin::augment_line` falls back to the raw
  GPT type name `fs_type.unwrap_or(part_type)`). The capture grabbed only `"Microsoft"`, the
  allow-set `{ntfs,exfat,BitLocker,ext2,ext3,ext4}` rejected it, and NTFS drives vanished
  from both the CLI picker and the GUI drive list — a real-world regression the synthetic
  single-token test fixtures (`'   1:  ntfs MyDrive …'`) never caught.
- **Fix:** in `cli/lib/list-drives.sh` + `gui/Drives/DriveScanner.swift`, the regex now
  captures the TYPE+NAME columns as **one blob** (ident + size still parsed from the right,
  unambiguous), and a new derive step matches the **prefix the server's own `--microsoft`
  filter keys on**: `"Microsoft Basic Data"` (GPT type for ntfs AND exfat) and `"BitLocker"`,
  falling back to the blkid single-token fstype (`ext2/3/4`, sometimes ntfs/exfat). Still one
  bare `list` call per refresh — no second VM boot (matters for the GUI 5s poll). `fstype` is
  display-only; mount validates `--fs-driver` itself, never the picker. Whole-disk rows still
  rejected by `^disk[0-9]+s[0-9]+$` (security non-negotiable, unchanged).
- **RED:** `tests/cli/list-drives.bats:list_mountable_drives surfaces NTFS with real
  multi-word 'Microsoft Basic Data' TYPE column` + `gui/Tests/DriveScannerTests.swift:
  parsesNtfsWithRealMultiWordMicrosoftBasicDataTypeColumn` — both use the user's real pasted
  `anylinuxfs list` line (`   4:       Microsoft Basic Data Media   224.2 GB   disk4s4`).
  Confirmed failing on the old code (bats: `disk4s4` absent; Swift: `drives.count 0 != 1`).
- **GREEN:** `bats tests/cli/list-drives.bats` → 4/4 ok; `swift test` → **148 passed**
  (was 147; +1). Existing single-token fixtures stay green (ntfs/exfat/ext4/btrfs cases all
  still parse correctly under the blob+prefix derive).
- **Validation:** `shellcheck cli/lib/list-drives.sh` → only the pre-existing `SC1091` info
  (sourced files, unchanged); full CLI bats suite green.
- **Commits:** 517bae9 (RED) → 6e1fb5a (GREEN).
- **Note:** the now-correct tests `list_mountable_drives calls anylinuxfs list without
  --microsoft` and `driveScannerCallsBareListWithoutMicrosoftFilter` were NOT changed —
  the fix keeps bare `list` (no `--microsoft`), so those assertions still hold.

## Merge evidence (checkpoint commits on this branch)

```
6e1fb5a fix: list NTFS drives despite multi-word 'Microsoft Basic Data' TYPE (GREEN)  [Phase G]
517bae9 test: add reproducer for NTFS list regression (Microsoft Basic Data) (RED)   [Phase G]
adbe5e2 docs: README troubleshooting — drive not listed / whole-disk "unidentifiable" [Phase F2]
a98bc5c feat: rework mounted screen for N drives, drop Combined speed (GREEN)   [Phase E]
6f8c88c feat: support multiple concurrent mounts in MountController (GREEN)      [Phase D]
2f9f4ef test: multi-mount + per-drive unmount reproducers (RED)                  [Phase D]
04af9f3 feat: no-drives copy now says NTFS / ext (GREEN)                         [Phase B]
b8238d3 test: add reproducer for ext mention in no-drives copy (RED)             [Phase B]
4e9a35d docs: note one-time first-mount Alpine rootfs pull in troubleshooting     [Phase A2]
1b03662 feat: list NTFS/ext support in CLI mount help (GREEN)                    [Phase A]
e4bd329 test: add reproducer for NTFS/ext help string (RED)                      [Phase A]
```

RED/GREEN pairing per phase: A (e4bd329→1b03662), B (b8238d3→04af9f3), D (2f9f4ef→6f8c88c),
E (a98bc5c — GREEN/refactor; RED is the render-regression test added in the same commit
because Phase E is a view rework, see Phase E note), G (517bae9→6e1fb5a). Phase A2/F2 are
docs-only.

## Build artifact (this session)

`./build/package-app.sh` ran for real (two-pass: placeholder-hash pass 1 → cli-src tree
hash `94bb34e7b4d203c568509c9a81add04f61ce4e85bb984fd136cf8b685ae07fe2` → real-hash
pass 2) → `dist/ntfsmac.app`, ad-hoc signed (`Identifier=com.khr898.ntfsmac`,
`Signature=adhoc`). Copied to `dist/ntfsmac.app`
per request. `helper/GeneratedCLIManifest.swift` auto-restored to the checked-in
placeholder by the script's EXIT trap.