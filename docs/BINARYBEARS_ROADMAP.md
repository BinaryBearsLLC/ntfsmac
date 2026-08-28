# BinaryBears ntfsmac roadmap

This is the current product roadmap for `dev`. Detailed implementation history and measurements
remain in the dated files under `docs/testing/` and `docs/audits/`.

## Current product

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

### Current maintenance (unreleased)

Follow-up issue evidence showed that `registries.conf` and other OCI inputs could still block the
same public runtime pull. Current work isolates all registry and authentication inputs, serializes
the longer first runtime check, prevents stale CLI scans during helper updates, and separates
runtime, no-drive, and Full Disk Access states.

Thanks to [@VixenSugo](https://github.com/VixenSugo) for reporting the issue, retesting both
Standard and Legacy builds, and providing the diagnostics and video that exposed the remaining
failure paths.

Local validation covers the full automated suite, both signed package variants, repeated no-drive
launches, and a write/reread/remove/unmount cycle on the NTFS `MobileData` volume.

## Next work

- Extend hardware/OS coverage when the required devices and controlled playback fixtures exist.
- Review new `anylinuxfs` versions through the pinned-source audit; never bulk-merge upstream.
- Add convenience features only when they preserve privacy, truthful state, and the compact
  menu-bar experience.

## Evidence and operating docs

- [Release process](RELEASE.md)
- [Current GUI contract](dev/GUI-PLAN.md)
- [Testing guide](dev/TESTING.md)
- [v3.1.0 local release evidence](testing/BINARYBEARS_V3_1_LOCAL_RC_2026-08-27.md)
- [Validation ledger](testing/BINARYBEARS_VALIDATION_RESULTS_2026-08-12.md)
- [Mount and transport audit](audits/LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md)
- [Security transaction audit](audits/LIVE_P0_SECURITY_TRANSACTION_AUDIT_2026-08-11.md)
