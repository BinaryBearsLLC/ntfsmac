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
non-empty test run.

On macOS 26.6.2 the wrapper skips only `PopoverStateRenderTests` because of a known AppKit runner
hang. Run any changed render path directly with `swift test --filter <test-name>` and record it
separately; do not count a skipped render suite as executed.

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
5. A clean app copied to `/Applications` passes the same flow in both Standard and Legacy builds.

Coverage lives in `runtime-config-isolation.bats`, `DriveScannerTests`, `FDAPromptCopyTests`,
`DiagnoseRunnerTests`, and `PopoverStateRenderTests`.

## Local package gate

`./build.command gui` builds Standard and Legacy DMGs. For a release candidate, use the official
BinaryBears Developer ID identity and verify:

- app and both helper versions match;
- host binaries are arm64 and the guest runtime is aarch64 Linux;
- nested signatures and helper identities match the selected variant;
- both DMGs contain `ntfsmac.app`, the Applications symlink, and approved artwork;
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

For Legacy, repeat clean install, Full Disk Access, mount/write/reread/unmount, and uninstall.
Confirm no mount, helper process, security session, or test file remains afterward.

## Safety-specific checks

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
