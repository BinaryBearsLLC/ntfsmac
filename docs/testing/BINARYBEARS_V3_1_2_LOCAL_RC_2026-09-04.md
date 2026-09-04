# BinaryBears v3.1.2 local release-candidate evidence — 2026-09-04

This concise record separates source, installed-hardware, package, notarization, and publication
evidence. Raw device identifiers and local logs remain private.

## Scope

- Candidate: `3.1.2`, Standard `SMAppService` and Legacy `SMJobBless`, Apple Silicon/macOS 13+.
- Issue: [#24](https://github.com/BinaryBearsLLC/ntfsmac/issues/24).
- Tester confirmation: the repaired Windows NTFS volume completed the intended workflow.
- Thanks to [@VixenSugo](https://github.com/VixenSugo) for the report, diagnostics, video, and
  repeated Standard/Legacy testing that exposed the complete failure path.

## Verified before the release commit

- Installed Standard beta `3.1.1 (31102)` initialized the pinned runtime, detected a clean NTFS
  USB volume, mounted it read/write, and reported one protected private NFS session.
- A fresh 16 MiB file matched byte-for-byte and by SHA-256 after flush, GUI unmount, remount, and
  reread. The test file was removed and final diagnostics reported zero mounts and sessions.
- Diagnostics changed from protected/read-write to neutral idle after unmount. Relaunch without a
  drive showed **No drives found**, not an incomplete-setup state.
- The hot-eject check exposed one stale header count. The source correction now uses the same
  reconciled visible-drive set as the rows and Diagnostics.

## Candidate gates

- Version and build are exactly `3.1.2` in the app and both helper variants. Brand synchronization,
  plist validation, ShellCheck, and the dual-artifact release contract passed.
- Shell/Bats: **337/337**. Swift: **323/323 Standard** and **323/323 Legacy**. Three forced AppKit
  render regressions also passed for no-drive idle, discovery failure, and detected-drive states.
- Both Apple Silicon DMGs were Developer ID signed and passed `verify-release.sh`, including nested
  signatures, entitlements, architecture, image integrity, and SHA-256 sidecars. Their Finder
  layouts were inspected after mounting.
- Standard SHA-256:
  `d8f240a0317118f48ae3d8e27d17c4f87aa69e4a3a187e103fb9567e5f716d1c`.
- Legacy SHA-256:
  `cfa8a0b79e8a16f044381f1f666cebb28ab0ce6aac3a7c762fa4cf712aa29e52`.

## Installed Standard candidate

- The exact signed `3.1.2` Standard candidate replaced the local beta and upgraded the helper from
  `3.1.1` to `3.1.2` without asking for permissions that were already granted.
- A physical external NTFS USB volume mounted read/write through `ntfs-3g` and NFS. Diagnostics
  schema 6 reported one mount, one protected session, and enforced private-link/PF state.
- A fresh random 16 MiB file matched byte-for-byte and by SHA-256 after write, flush, GUI unmount,
  remount, and reread. It was then removed; no test file remains on the volume.
- After final unmount and logical eject, rows, header, and Diagnostics all changed to no-drive idle.
  A complete app relaunch still showed **No drives found**, never setup. Final diagnostics reported
  zero mounts/sessions, bridge down, and protection not required.

## Installed Legacy candidate

- The exact signed `3.1.2` Legacy candidate installed its `SMJobBless` helper and mounted the same
  physical NTFS USB volume read/write through the shared `ntfs-3g`/NFS path. Diagnostics again
  reported one protected session with enforced private-link/PF state.
- A separate random 16 MiB file matched byte-for-byte and by SHA-256 after write, flush, GUI
  unmount, remount, and reread. It was removed successfully.
- **Uninstall Everything** removed the CLI, runtime, Legacy helper file, and Legacy launchd service
  with no active mount left behind. The Standard candidate was then restored, its Login Item was
  re-approved, and the runtime was staged again.
- A final Standard mount/unmount passed. The installed app is Standard `3.1.2`; final diagnostics
  are healthy with zero mounts/sessions, bridge down, and protection not required.

Apple notarization, stapling, downloaded-draft smoke tests, and publication remain separate gates
after approval of the release commit and text.
