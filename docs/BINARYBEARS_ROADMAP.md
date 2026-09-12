# BinaryBears ntfsmac roadmap

This is the current product roadmap for `dev`. Detailed implementation history and measurements
remain in the dated files under `docs/testing/` and `docs/audits/`.

## Published 3.1.2 line

- Apple Silicon and macOS 13+.
- Menu-bar app plus CLI; no kernel extension or SIP change.
- `ntfs-3g` by default, NTFS3 as an explicit experimental choice, and ext2/3/4 support.
- Standard `SMAppService` and labelled Legacy `SMJobBless` installers from one source tree.
- Private vmnet/NFS transport with per-session PF and route ownership.
- Reconciled GUI/CLI/host mount truth, multi-drive lifecycle, and safe Quit behavior.
- Privacy-safe Diagnose plus Verified Copy/Verify with flush, reread, and SHA-256 manifests.

## Release lines

### v3.0.0

Established the BinaryBears production identity, signed/notarized DMG channel, helper migration,
privacy-safe diagnostics, updater, and published website.

### v3.1.0

Made the modern helper the Standard path while retaining a Legacy DMG. It also simplified
Diagnose, refined Settings/focus behavior, protected mounted drives during Quit, and completed the
dual-artifact release pipeline.

### v3.1.1

Patch release for [issue #24](https://github.com/BinaryBearsLLC/ntfsmac/issues/24):

- isolated the pinned runtime pull from unreadable optional `registries.d` metadata without
  changing user files;
- report drive-discovery/runtime failures truthfully in setup and normal UI, with a retry action;
- preserve identical behavior in Standard and Legacy because they share the runtime path.

### v3.1.2

Follow-up patch for [issue #24](https://github.com/BinaryBearsLLC/ntfsmac/issues/24):

- isolate every registry and authentication input used by the pinned public runtime pull;
- serialize the longer first runtime check and prevent stale scans during helper updates;
- keep no-drive launches, Full Disk Access, mount state, and Diagnostics truthful;
- report explicit read-only causes, remove the unsafe RW override, and label **Open in Finder**;
- clear disconnected drives consistently from rows, Diagnostics, and the header.

Thanks to [@VixenSugo](https://github.com/VixenSugo) for reporting the issue, retesting both
Standard and Legacy builds, and providing the diagnostics and video that exposed the remaining
failure paths.

Release-candidate evidence is recorded in
[the concise v3.1.2 validation note](testing/BINARYBEARS_V3_1_2_LOCAL_RC_2026-09-04.md).

## Next work

### v3.1.3 candidate — `Update/3.1.3`

- Beta 3 fixes MBR multi-partition Linux discovery in both GUI and CLI. Every
  Linux sibling remains available to mount through filesystem auto-detection, even when
  an unprivileged scan cannot resolve its superblock. Generic rows display Linux rather
  than claiming a confirmed ext filesystem. Publication and native mount acceptance remain
  separate release gates.
- Target macOS 14+ on Apple Silicon, with newer-OS runtime optimizations retained.
- Ship Standard only; deprecate the Legacy installer while testing migration from it.
- Preserve the `dev` fixes and the separate `3.1.2` rollback branch.
- Validate and lock dependency updates individually, including ntfs-3g 2026.7.7
  and the Alpine package graph.
- Reject filesystem guesses based only on partition type when multiple drives are connected.
- Show a single unvalidated-OS notice, with the issue tracker and the existing Command-click
  Diagnose export. Keep acknowledgement across app and OS updates.
- Record exact OS/build evidence; invite successful and unsuccessful community compatibility
  reports without presenting untested systems as verified.

This candidate is not yet qualified for release. Build-target checks, current-host tests,
Sonoma guest execution, physical-drive acceptance, and notarization are separate gates;
see the [Sonoma validation record](testing/SONOMA_LOCAL_VALIDATION_2026-09-08.md).

- Extend hardware/OS coverage when the required devices and controlled playback fixtures exist.
- Review new `anylinuxfs` versions through the pinned-source audit; never bulk-merge upstream.
- Add convenience features only when they preserve privacy, truthful state, and the compact
  menu-bar experience.

## Evidence and operating docs

- [Release process](RELEASE.md)
- [Current GUI contract](dev/GUI-PLAN.md)
- [Testing guide](dev/TESTING.md)
- [v3.1.2 local release evidence](testing/BINARYBEARS_V3_1_2_LOCAL_RC_2026-09-04.md)
- [v3.1.0 local release evidence](testing/BINARYBEARS_V3_1_LOCAL_RC_2026-08-27.md)
- [Validation ledger](testing/BINARYBEARS_VALIDATION_RESULTS_2026-08-12.md)
- [Mount and transport audit](audits/LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md)
- [Security transaction audit](audits/LIVE_P0_SECURITY_TRANSACTION_AUDIT_2026-08-11.md)
