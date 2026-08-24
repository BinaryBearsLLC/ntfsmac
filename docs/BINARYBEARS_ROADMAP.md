# BinaryBears ntfsmac roadmap

This is the short, current product roadmap for the BinaryBears `dev` branch. Detailed historical
evidence remains in the dated files under [`docs/testing`](testing/) and [`docs/audits`](audits/),
and in Git history.

## Current baseline

The published compatibility product is software-complete for its measured P0/P1 scope:

- Apple Silicon, macOS 13+, menu-bar app, CLI, and SMJobBless helper.
- `ntfs-3g` default; NTFS3 explicit and experimental.
- Private vmnet/NFS transport with per-session PF and route ownership.
- Authoritative GUI/CLI/host mount reconciliation.
- Fail-closed, reason-coded protection evidence and privacy-safe diagnostics.
- Verified Copy and Verify with flush, reread, and SHA-256 manifests.
- Multi-drive lifecycle, notifications, Finder opening, Eject All, and professional DMG layout.

The packaged acceptance ledger currently records 28 `PASS`, 0 `FAIL`, and 2 resource-dependent
`BLOCKED` cells. A block is not a pass; it remains visible in the dated ledger until the required
hardware or controlled playback environment is available.

## v3.0.0 — production BinaryBears release

`v3.0.0` was published on 2026-08-18 and completed the hard release gate before P2.

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

- [x] Remove a registered `com.khr898.ntfsmac.helper` before blessing; remove orphaned legacy
  files during the first integrity-checked v3 staging and during complete uninstall.
- [x] Migrate only safe preferences: notification opt-in and confirmed launch-at-login intent.
- [x] Re-probe Full Disk Access for the new helper and never inherit stale permission state.
- [x] Add a manual update check plus an automatic check limited to once every 24 hours.
- [x] Read only the latest published stable GitHub Release and open its GitHub page; never download,
  install, track, or run a background update service.

### Release and public project

- [x] Keep a clearly labelled ad-hoc, credential-free contributor fallback while automatically
  using the exact BinaryBears Developer ID identity when present for real local helper validation.
- [x] Prepare Developer ID signing and notarization for official BinaryBears releases.
- [x] Produce `ntfsmac-3.0.0-Apple-Silicon.dmg` and its SHA-256 file from a signed v3 tag.
- [x] Create a draft GitHub Release, test that exact downloaded DMG, then publish without rebuilding.
- [x] Publish the static, analytics-free GitHub Pages site.
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

### v3.1.0 candidate — modern helper integration

The published v3 DMG passed its post-download test. The modern lifecycle is now integrated as the
standard `v3.1.0` candidate; P2 remains an internal roadmap name and is not written in the app or
standard artifact name.

The published `v3.0.0` compatibility line remains the current supported release until the complete
dual-distribution gate below passes and `v3.1.0` ships.

- [x] Integrate the macOS 13+ `SMAppService` LaunchDaemon lifecycle without weakening the XPC
  boundary.
- [x] Give the standard helper the separate internal identity
  `com.binarybears.ntfsmac.helper.daemon` and preserve the compatibility identity for migration.
- [x] Build and test standard and Legacy code paths from one source tree with isolated Swift build
  directories.
- [x] Make GUI/release builds emit both DMGs automatically, with explicit local and workflow
  controls to disable Legacy.
- [x] Keep the standard user-facing name exactly **ntfsmac**; label only the compatibility output
  and Settings metadata as **Legacy**.
- [ ] Complete live clean install, System Settings approval/denial, compatibility upgrade,
  mismatch, reinstall, Full Disk Access, complete uninstall, and known-clean mount/write/reread/
  unmount on the packaged standard candidate.
- [ ] Repeat the applicable packaged acceptance matrix on the Legacy candidate.
- [ ] Record live System Settings evidence for the friendly service name/icon; do not infer it from
  bundle metadata alone.
- [ ] Publish only after both locally tested candidates are rebuilt as signed/notarized draft
  artifacts and the downloaded DMGs pass their final smoke tests.

#### v3.1.0 completion sequence — implementation status

Items 2–6 are integrated in the `upgrade/v3.1.0` candidate and covered by focused regressions.
They are not release claims: the complete local Standard/Legacy gate, packaged live acceptance,
official artwork, signing/notarization, and downloaded-draft smoke tests remain mandatory.

- [ ] **0.1 — Rebrand both DMGs with official BinaryBears artwork.** This gate is blocked until the
  maintainer supplies the approved logo assets. Use those originals in the standard and Legacy
  installer presentation; do not invent, redraw, trace, or ship placeholder branding. Preserve the
  visible app name **ntfsmac**, keep only the compatibility DMG explicitly labelled **Legacy**, and
  visually validate the final mounted-window composition before either artifact can ship.
- [ ] **1 — Complete the resource and visual baseline.** Record app, helper, and runtime CPU,
   resident memory, wakeups, and memory growth separately for idle, popover-open polling, Refresh,
   Diagnose, one mounted drive, and a 30-minute soak. Record both standard and Legacy builds on the
   same Mac/OS/power conditions. Short idle sampling is useful development evidence, but does not
   replace the full candidate matrix.
- [x] **2 — Make standard-helper migration transactional.** The standard build detects registered,
   running, and orphaned Legacy helper state. It first obtains approval for and verifies a healthy
   standard helper/XPC connection, then uninstalls the Legacy helper and proves its job, process,
   and files are absent. A denied or failed standard installation must retain the working Legacy
   helper and show a recoverable state. The explicitly labelled Legacy build never removes the
   helper it requires.
- [x] **3 — Protect Quit while storage is active.** With any verified mount, present `Unmount and Quit`
   as the safe default, `Quit Anyway`, and `Cancel`. `Don't show again` may persist only the safe
   `Unmount and Quit` action. It has no Settings control: Command-clicking Quit clears the saved
   choice and restores the confirmation. An active Verified Copy or in-flight mount/unmount disables
   Quit so an operation is never interrupted or covered by a saved preference.
- [x] **4 — Replace the GUI diagnostic row dump with a semantic summary.** Keep the CLI and privacy-safe
   JSON schema unchanged. Aggregate the same evidence into a few textual macro categories with an
   explicit status, short explanation, and next action. Hide implementation details from the
   normal user; retain them only in the CLI and developer JSON export. Never rely on colour alone
   and never map missing evidence to green.
- [x] **5 — Integrate protection status into Diagnose.** Remove the standalone SECURITY presentation.
   Diagnose includes one plain-language `Connection protection` macro category; `Hide` dismisses
   the complete Diagnose presentation, including that category. Running Diagnose again reveals a
   fresh result. The normal GUI never exposes PF, routes, vmnet, XPC, or similarly internal terms.
- [x] **6 — Refine the Settings header, update action, and button focus.** Use one balanced header row:
   Back on the left, `Settings` optically centred, and the icon-only update action on the right,
   all aligned to the same baseline and stable hit-target geometry. Remove stacked decorative
   button rectangles. Do not autofocus an action when the popover opens or transfer focus because
   of a pointer click; show a thin focus treatment only after deliberate keyboard navigation, with
   no stale halo, excessive thickness, or layout movement.
- [ ] **7 — Repeat resource qualification and the complete release gate.** Compare the final
   candidate with step 1, investigate sustained CPU or monotonic memory growth, then run both
   packaged variants through automated, visual/accessibility, migration, mount, quit, uninstall,
   signing, and downloaded-DMG acceptance. Local validation must finish before any push; the final
   signed/notarized draft and downloaded-DMG checks follow only after the official artwork lands.

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
