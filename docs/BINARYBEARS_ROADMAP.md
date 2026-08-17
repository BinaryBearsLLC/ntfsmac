# BinaryBears ntfsmac roadmap

This is the short, current product roadmap for the BinaryBears `dev` branch. Detailed historical
evidence remains in the dated files under [`docs/testing`](testing/) and [`docs/audits`](audits/),
and in Git history.

## Current baseline

The compatibility product is software-complete for its measured P0/P1 scope:

- Apple Silicon, macOS 13+, menu-bar app, CLI, and SMJobBless helper.
- `ntfs-3g` default; NTFS3 explicit and experimental.
- Private vmnet/NFS transport with per-session PF and route ownership.
- Authoritative GUI/CLI/host mount reconciliation.
- Fail-closed, reason-coded SECURITY rows and privacy-safe diagnostics.
- Verified Copy and Verify with flush, reread, and SHA-256 manifests.
- Multi-drive lifecycle, notifications, Finder opening, Eject All, and professional DMG layout.

The packaged acceptance ledger currently records 28 `PASS`, 0 `FAIL`, and 2 resource-dependent
`BLOCKED` cells. A block is not a pass; it remains visible in the dated ledger until the required
hardware or controlled playback environment is available.

## v3.0.0 — production BinaryBears release

`v3.0.0` is the next release and a hard gate before any P2 implementation.

### Repository and product identity

- [x] Preserve the pre-rebrand source at `archive/dev-pre-v3-rebrand` and signed tag
  `dev-pre-v3-rebrand-20260817`, both resolving to `98dd96b`.
- [x] Keep fork `main` as the independent upstream mirror; do not merge it into the v3 rebrand.
- [x] Keep the visible product name exactly **ntfsmac**.
- [x] Use **ntfsmac by BinaryBears** only for README and website marketing.
- [x] Change production identifiers to `com.binarybears.ntfsmac` and
  `com.binarybears.ntfsmac.helper`.
- [x] Apply the approved ntfsmac icon to the app, DMG, README, and site.
- [x] Add the gear-marked helper variant inside the app's permission guidance.
- [x] Retain the original author and license notices in this repository.

### Migration and update behavior

- [x] Detect and remove the old `com.khr898.ntfsmac.helper` before blessing the v3 helper.
- [x] Migrate only safe preferences: notification opt-in and confirmed launch-at-login intent.
- [x] Re-probe Full Disk Access for the new helper and never inherit stale permission state.
- [x] Add a manual update check plus an automatic check limited to once every 24 hours.
- [x] Read only the latest published stable GitHub Release and open its GitHub page; never download,
  install, track, or run a background update service.

### Release and public project

- [x] Keep local contributor builds ad-hoc and credential-free.
- [x] Prepare Developer ID signing and notarization for official BinaryBears releases.
- [ ] Produce `ntfsmac-3.0.0-Apple-Silicon.dmg` and its SHA-256 file from a signed v3 tag.
- [ ] Create a draft GitHub Release, test that exact downloaded DMG, then publish without rebuilding.
- [ ] Publish the static, analytics-free GitHub Pages site.
- [x] Complete the tracked-tree privacy audit and enable concise issue templates.

### v3 release gate

The final local RC is tested once after the implementation is complete: automated suites, clean
install, migration from the old helper, Full Disk Access, one known-clean mount/write/reread/unmount,
complete uninstall, updater behavior, signature, DMG, and notarization. GitHub then builds the draft
artifact. The downloaded draft DMG receives the final smoke test and checksum comparison.

Only the already-tested draft may be published. A failure returns to `dev`; it never converts into
a partial release.

## After v3.0.0

Patch releases follow SemVer (`v3.0.1`, `v3.0.2`, and so on) and use the same signed-tag and draft
artifact process.

### P2 — modern helper variant

P2 starts only after the published v3 DMG passes its post-download test.

- Prototype the macOS 13+ `SMAppService` lifecycle without weakening the XPC boundary.
- Give the modern variant a separate internal identity and migration contract.
- Validate clean install, approval, denial, upgrade, mismatch, reinstall, and complete uninstall.
- Determine from live System Settings evidence whether a bundle-based helper can present the
  friendly **ntfsmac Helper** name and gear icon.
- Ship the compatibility and modern variants only when users can distinguish them clearly.

### Later product work

- Complete the two resource-blocked extended qualification cells when their prerequisites exist.
- Review upstream changes deliberately after v3; never bulk-merge upstream into `dev` as a release
  prerequisite.
- Consider convenience features only when they preserve privacy, truthful state, and the minimal
  menu-bar experience.

## Evidence map

- [`BINARYBEARS_VALIDATION_RESULTS_2026-08-12.md`](testing/BINARYBEARS_VALIDATION_RESULTS_2026-08-12.md): live packaged acceptance ledger, updated through the final 2026-08-17 closure.
- [`BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md`](testing/BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md): manual gate definitions.
- [`LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md`](audits/LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md): mount truth and topology audit.
- [`LIVE_P0_SECURITY_TRANSACTION_AUDIT_2026-08-11.md`](audits/LIVE_P0_SECURITY_TRANSACTION_AUDIT_2026-08-11.md): live PF/route transaction evidence.
- [`dev/GUI-PLAN.md`](dev/GUI-PLAN.md): current UI behavior contract.
- [`dev/PLAN.md`](dev/PLAN.md): historical architecture and implementation plan.
