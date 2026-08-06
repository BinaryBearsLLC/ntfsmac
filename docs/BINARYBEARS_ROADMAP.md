# BinaryBears ntfsmac Roadmap

> [!IMPORTANT]
> This roadmap applies only to the
> [`BinaryBearsLLC/ntfsmac`](https://github.com/BinaryBearsLLC/ntfsmac) fork. It is not a
> commitment on behalf of the original [`khr898/ntfsmac`](https://github.com/khr898/ntfsmac)
> project or the [`nohajc/anylinuxfs`](https://github.com/nohajc/anylinuxfs) project.

This is the canonical product roadmap for the BinaryBears fork. It replaces the older practice
of treating implementation plans, test-session notes, and private scratch files as a current
feature list. The code status below was reconciled on 2026-08-05 against upstream/BinaryBears
`main` at `d2b151d` (`v2.0.050826`) and the preserved pre-sync BinaryBears `dev` at `e9f85e5`.
Live hardware findings from 2026-08-06 are recorded separately in
[Live Mount-State and NFS Transport Audit — 2026-08-06](audits/LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md)
and are release-blocking until the acceptance criteria below pass.

The post-sync wiring audit and its focused recovery branches are recorded in
[BinaryBears Upstream Regression Audit — 2026-08-05](audits/UPSTREAM_REGRESSION_AUDIT_2026-08-05.md).

## Status legend

| Marker | Meaning |
| --- | --- |
| `[x]` | Shipped in the BinaryBears fork and supported by code or recorded validation evidence |
| `[-]` | Foundation exists, but the user-facing feature or live integration is incomplete |
| `[ ]` | Planned; not shipped |
| **Decision A/B** | Product or engineering choice that must be resolved with evidence before implementation |

“Implemented” and “verified on real hardware” are intentionally different claims. Unit tests can
validate parsing, command construction, and state transitions; they cannot prove NTFS write
integrity, VPN behavior, packet-filter enforcement, or clean-install behavior on every supported
macOS release.

## Product principles

1. **Data integrity and compatibility outrank speed.** Performance modes remain opt-in until
   their failure cases are understood and reproduced.
2. **No false safety indicators.** The GUI must show `unknown` or `not enforced` when a condition
   has not been measured.
3. **Privacy-safe diagnostics.** Reports expose capability and reason codes, not user, device,
   volume, network, or VPN identity.
4. **Audited dependencies.** Source updates are reviewed and pinned to exact revisions; runtime
   downloads must become reproducible as well.
5. **Focused delivery.** Each roadmap item lands through its own branch, focused commit or commit
   series, pull request, documentation update, and test evidence.
6. **Honest scope.** The BinaryBears fork may propose improvements upstream, but this roadmap does
   not imply that upstream has accepted or scheduled them.

## Branch model

| Branch | Purpose | Update rule |
| --- | --- | --- |
| `main` | Clean mirror of `khr898/ntfsmac:main` | Fast-forward/synchronize from upstream; no BinaryBears-only roadmap commits |
| `dev` | BinaryBears product line | Current `main` plus this roadmap and tested fork-only improvements |
| `feat/*`, `fix/*`, `docs/*` | One BinaryBears roadmap deliverable | Branch from `dev`, validate, then PR back to `dev` |
| upstream candidate branch | One change proposed to khr898 | Branch directly from current `upstream/main`; exclude fork branding/roadmap |

Upstream changes are integrated into `dev` as an explicit sync after `main` is updated. Already
accepted work is taken from upstream's final implementation rather than replaying the fork's older
version of the same commits. This keeps maintainer fixes authoritative and reduces recurring
conflicts.

## Completed BinaryBears foundation

### Build, runtime, and drive support

- [x] Apple Silicon and macOS 13+ build pipeline with guided CLI/GUI packaging.
- [x] Ad-hoc bundle signing and package structure, architecture, and signature checks.
- [x] Exact anylinuxfs source pin through the `vendor/src/anylinuxfs` submodule and
  `ANYLINUXFS_COMMIT` in `build/sources.lock`.
- [x] `ntfs-3g` as the implicit compatibility-first NTFS default.
- [x] ext2, ext3, and ext4 discovery and mounting through the shared microVM/NFS path.
- [x] NTFS discovery for GPT and MBR `Windows_NTFS` partitions.
- [x] Partition-only device validation in both the unprivileged and privileged layers.
- [x] Multiple concurrent GUI-owned drive entries and per-drive mount/unmount actions.
- [x] Soft NFS mounts retained as the hot-unplug safety policy.

### GUI, diagnostics, and lifecycle

- [x] Native menu-bar application with system-adaptive idle icon and explicit activity states.
- [x] Settings presented inside the menu-bar popover, with Back navigation.
- [x] Canonical app version/build displayed in Settings and diagnostics.
- [x] Contextual help, accessible labels, and inline Diagnose visibility controls.
- [x] Command-click Diagnose export using the same privacy-safe JSON schema as the CLI.
- [x] In-popover helper reinstall and confirmed uninstall workflow.
- [x] Lazy XPC connection and helper lifecycle recovery improvements.
- [x] Real Service Management state for Launch at login.
- [x] SECURITY rows default to `unknown` instead of manufacturing a successful state.
- [x] SECURITY Hide/Show changes presentation only and leaves mount/helper state untouched.
- [x] Runtime Alpine tag/digest pinning, versioned cache migration, diagnostics, and package gate.

### Foundations that are not complete product features

- [-] **NTFS3:** CLI parsing, helper/XPC transport, and command construction exist and are tested;
  there is no GUI choice and no recorded BinaryBears NTFS3 hardware qualification yet.
- [-] **Security hardening:** packet-filter and VPN-route primitives plus unit tests exist, but
  they are not integrated into the live mount transaction and do not feed measured GUI state.
- [-] **Open in Finder:** the tested `FinderOpener` implementation exists, but the current
  multi-drive popover does not expose a corresponding control.
- [-] **Transfer telemetry:** the sampling subsystem and tests remain in the codebase, but the
  current multi-drive UI deliberately does not present a speed row.
- [-] **Authoritative mount-state synchronization:** implemented with paired anylinuxfs-session
  and host NFS-mount evidence, bounded polling, and a fail-closed unknown state. Unit/state tests
  pass; the packaged-app hardware matrix below is still a release gate.
- [-] **NFS transport contract:** ntfsmac now pins anylinuxfs to `--net-helper vmnet`, reports a
  privacy-safe transport-contract token, and includes a fail-closed live route/listener gate.
  Packaged-app listener/route evidence with real hardware is still required.

## Prioritized roadmap

### P0.0 — Live-hardware release blockers

These two findings override lower-priority feature work. They are not data-corruption findings:
the 2026-08-06 SHA-256 suite passed before and after a safe unmount/remount. They are nevertheless
trust-boundary failures because the UI can publish a false mounted state and the observed NFS
endpoint does not match the documented architecture without further explanation and proof.

#### A. Reconcile GUI, CLI, and macOS mount truth

The packaged 2.0 (050826) GUI retained the test NTFS volume as `Mounted read/write` after
`ntfsmac unmount <partition>` succeeded. At the same time, `diskutil` reported `Mounted: No`, the host
mount table contained no matching NFS mount, and `ntfsmac diagnose --json` reported
`bridge=down` and `nfs_mount_count=0`. Clicking GUI Refresh did not repair the state; GUI Diagnose
then displayed `NFS mounts: None` inside the still-mounted presentation.

- [x] Introduce one read-only authoritative mount snapshot aligned with the same anylinuxfs
  session and host NFS-mount sources used by CLI diagnostics. It identifies ntfsmac-owned mounts
  per device and mount point without relying only on `MountController.mountedDrives`.
- [x] Reconcile at app launch, popover open, periodic poll, Refresh, and after every helper
  mount/unmount response. A successful command response is provisional until the observed host
  state agrees.
- [x] Detect CLI mount/unmount, external unmount, helper/VM exit, and hot-unplug while the GUI is
  open. Remove stale rows and green status; surface a reason-coded warning when state is ambiguous.
- [x] Preserve correct independent state for multiple mounts. One disappearing mount must not
  erase or misclassify surviving mounts.
- [x] Reconcile the header/icon/controls from the authoritative snapshot and publish an explicit
  reason-coded warning/unknown state whenever the sources cannot prove green mounted state.
- [x] Add parser and state-machine coverage for CLI-created mounts, external teardown, source
  failure, provisional helper responses, and independent concurrent mounts.
- [ ] Complete packaged-app hardware tests for GUI→CLI, CLI→GUI, external teardown, crash
  recovery, restart recovery, Refresh, hot-unplug, and multiple drives.

Acceptance: no UI control, icon, diagnostic row, or CLI output may claim a drive is mounted or
writable after the corresponding host mount disappears. A CLI-created mount must also appear in
the already-running GUI within the bounded reconciliation interval.

#### B. Prove or remediate the NFS endpoint architecture

Two consecutive live sessions logged `vmproxy ... -b 127.0.0.1`, checked the NFS server at
`127.0.0.1:2049`, and mounted a share as `diskNsN.local:/mnt/<label>`. Source tracing identifies
that sequence as anylinuxfs's gvproxy transport, not its direct vmnet-helper transport. The old
diagnostic's broad process check incorrectly reported `bridge=up` for this loopback session.

- [x] Trace both vendored paths: gvproxy binds/checks the loopback proxy, while vmnet-helper
  assigns a private `/30`, publishes the VM endpoint through the synthetic `.local` name, and
  routes the host NFS client over the private bridge.
- [ ] Resolve `diskNsN.local` during a live mount and prove which endpoint the kernel actually
  uses. Confirm that no NFS listener is exposed on non-loopback or unrelated interfaces.
- [x] Select the direct private-`/30` path and force `--net-helper vmnet` on every ntfsmac mount,
  so a stale per-user anylinuxfs configuration cannot silently re-enable gvproxy.
- [x] Add privacy-safe diagnostics for transport topology and enforcement state without exporting
  addresses, interface names, volume labels, or device identifiers.
- [x] Add a read-only packaged-app gate that fails on gvproxy, a loopback NFS listener, a
  non-private endpoint/route, or a non-`soft` ntfsmac mount.
- [ ] Execute that gate with the packaged app on real hardware for VPN off/on, concurrent mounts,
  teardown, and helper recovery, retaining only privacy-safe results in the repository.

Acceptance: packet/listener/route evidence must match one documented architecture, NFS must remain
`soft`, teardown must remove every listener and route owned by the session, and neither README nor
GUI may claim a dedicated private path more strongly than the measured evidence supports.

### P0 — Trust, reproducibility, and truthful security

#### 1. Pin the runtime Alpine environment

- [x] Replace the shipped `alpine:latest` defaults with an exact tag and platform digest derived
  from `build/sources.lock`.
- [x] Add a packaging gate that rejects a shipped runtime containing an unapproved
  `alpine:latest` reference.
- [x] Record the approved and installed Alpine state plus guest package versions in privacy-safe
  CLI text, CLI JSON, GUI summary, and Command-click export diagnostics.
- [x] Define an explicit migration path for an existing `~/.anylinuxfs/alpine` cache; never
  silently destroy user data or force a download during an unrelated action.
- [x] Test clean initialization, cached initialization, offline reuse, digest mismatch, interrupted
  download, and upgrade/rollback behavior.

The immutable digest-only pull reference, cache directory, and rootfs version marker are derived
from the same locked tag, arm64 digest, and anylinuxfs commit; the build independently proves the
tag resolves to that digest. Legacy, incomplete, or mismatched caches are preserved
side-by-side; initialization is triggered only by a mount that needs the pinned environment.

#### 2. Establish an anylinuxfs update policy

The fork does **not** retrieve the newest anylinuxfs source on every build. Git checks out the
exact submodule revision recorded by this repository; the current audited pin is
`8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3`. This is deliberate and should remain visible.

- [ ] Add a repeatable audit checklist covering upstream commits, release notes, dependency-lock
  changes, local patches, filesystem behavior, packaging, and hardware regression tests.
- [ ] Record every accepted pin change in `build/AUDIT.md` and the pull request.
- [ ] Never auto-merge a source update that changes the privileged, VM, NFS, or filesystem path.

**Decision A/B**

- **Option A — periodic audited pin updates (recommended):** check upstream on a release cadence,
  review the diff, update the submodule and pins in one dedicated PR, then run the full gates.
- **Option B — automated update PRs:** a bot may open pin-update PRs, but they remain blocked from
  merge until the same human review and hardware matrix pass. Do not build from a floating branch.

#### 3. Make security hardening effective during a real mount

- [ ] Define one transactional sequence: mount preparation → private link discovery → route policy
  → packet-filter policy → NFS mount → measured status publication.
- [ ] Verify that the packet-filter rules are attached to an evaluated PF ruleset path; loading a
  named anchor alone must not be treated as proof of enforcement.
- [ ] Apply and remove VPN-bypass routes per active mount without breaking unrelated routes.
- [ ] Make teardown idempotent across unmount, Quit, failed mount, helper reconnect, and crash
  recovery.
- [ ] Support concurrent mounts without one teardown invalidating another mount's protections.
- [ ] Publish reason-coded state: `enforced`, `notEnforced`, `notRequired`, or `unknown`.

**Decision A/B**

- **Option A — visible best-effort rollout (recommended first):** permit the mount, but show a
  prominent non-green state whenever hardening cannot be proven.
- **Option B — strict mode:** roll back or reject the mount when required policy cannot be proven.
  Consider this only after the live implementation is stable; it may later become an explicit
  user setting.

#### 4. Complete evidence-backed SECURITY UI

- [ ] Replace generic promises with narrowly measured labels such as **Private VM link**,
  **VPN-safe route**, and **PF policy enforced**.
- [x] Add the requested **Hide** action without changing mount or helper state.
- [ ] Feed the same state and privacy-safe reason codes to CLI text, CLI JSON, and GUI diagnostics.
- [ ] Test mounted/unmounted, VPN on/off, multiple mounts, missing tools, stale state, malformed
  output, helper reconnect, and teardown. No missing result may become a green check.

### P1 — Verifiable copying and controlled NTFS3 adoption

#### 5. Add Verified Copy with SHA-256

Finder and third-party applications write to the exported NFS volume directly, so ntfsmac cannot
reliably intercept every ordinary copy. A trustworthy integrity feature must own the copy or be
described only as a later verification, not as transparent protection for all Finder operations.

- [ ] Add `ntfsmac copy --verify <source> <destination>` using streaming SHA-256.
- [ ] Copy to a temporary destination, flush it, reread the destination, compare type/size/hash,
  then rename atomically where the destination filesystem supports it.
- [ ] Add `ntfsmac verify <source> <destination>` for an existing file or directory tree.
- [ ] For directories, generate a deterministic manifest of relative path, entry type, size, and
  SHA-256; define explicit symlink and metadata behavior.
- [ ] Preserve the source and keep a failed temporary destination clearly recoverable; never
  delete the source automatically.
- [ ] Add a GUI **Verified Copy** flow only after the CLI/core behavior is complete.
- [ ] State the limit honestly: a successful comparison validates the bytes read at that time; it
  cannot guarantee against later media failure or preserve every platform-specific metadata field.

##### Media-copy integrity investigation

Track the reported case where a video copied through ntfsmac showed deterministic-looking playback
artifacts, glitches, and intermittent lag on an LG webOS TV, while a Windows-mediated copy made
with different USB media played correctly. The original comparison is not conclusive because the
USB devices differed.

- [ ] Reproduce both copy paths with the same source file, same NTFS USB device, same port, and same
  TV; repeat each path enough times to expose intermittent failures.
- [ ] Record source size/SHA-256 before copying, then safely unmount, physically reconnect, reread
  the destination, and compare size/SHA-256. Prefer an additional Windows-side hash so verification
  bypasses the ntfsmac/NFS read path.
- [ ] Verify that an ntfsmac unmount cannot report success while its NFS mount is still present;
  treat a failed or incomplete host unmount as an error before the user removes the device.
- [ ] Exercise normal copies and controlled disposable-data fault cases over the required NFS
  `soft` mount; confirm RPC/VM interruptions surface as explicit copy failures, never silent success.
- [ ] Preserve anylinuxfs, kernel, and helper logs for every run and correlate errors with the first
  mismatching byte range and with repeatable versus playback-dependent artifact timestamps.
- [ ] If hashes match after physical reconnect, move the investigation to USB sustained-read speed,
  flash/controller health, fragmentation, power/port behavior, and TV codec/container limits.

MD5 is not proposed for new integrity work. SHA-256 is widely available, collision-resistant for
this purpose, and suitable for one canonical manifest format.

**Decision A/B**

- **Option A — app-managed copy and explicit verify (recommended):** deterministic progress,
  cancellation, errors, and source/destination correlation.
- **Option B — observe Finder copies:** macOS filesystem event streams are directory-oriented and
  cannot reliably prove which source produced a destination. This may support a convenience
  notification later, but must not be marketed as an integrity guarantee.

#### 6. Qualify NTFS3 as an experimental performance driver

The pinned anylinuxfs documentation describes `ntfs-3g` as the more compatible default and NTFS3
as faster, while warning that NTFS3 refuses hibernated/Fast Startup or erroneous volumes, may show
permission differences on Windows system directories, and has less reassuring field history.
Read the exact
[pinned NTFS notes](https://github.com/nohajc/anylinuxfs/blob/8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3/docs/important-notes.md#ntfs)
before testing it.

Current lower-layer syntax is already available:

```sh
ntfsmac mount --fs-driver ntfs3 disk4s1
```

- [x] Validate CLI values and translate NTFS3 to anylinuxfs `-t ntfs3`, never an inert mount
  option token.
- [x] Carry the driver choice through the helper/XPC request.
- [ ] Add preflight guidance: disable Windows Fast Startup, fully shut down Windows, and repair
  filesystem errors with Windows `chkdsk`. Never recommend `ntfsfix` as a substitute repair.
- [ ] Add explicit **Experimental** labeling, compatibility differences, and a one-mount driver
  choice in the GUI; no silent fallback between drivers.
- [ ] Record the selected driver and privacy-safe failure category in diagnostics.
- [ ] Compare `ntfs-3g` and NTFS3 with the same devices, data set, and Verified Copy manifest.

**Decision A/B**

- **Option A — keep `ntfs-3g` default and offer explicit NTFS3 opt-in (recommended):** preserves
  compatibility while making the performance path available to informed users.
- **Option B — make NTFS3 the default later:** eligible only after the full hardware matrix below
  passes, failure handling is clear, and collected evidence shows a material reliability benefit.
  This is not the current plan.

##### NTFS3 hardware qualification gate

The same suite must be run against both drivers and retain logs plus SHA-256 manifests:

| Area | Required coverage |
| --- | --- |
| Hosts | Every supported macOS major release on Apple Silicon represented by the project test pool |
| Media | Multiple USB devices/controllers and capacities; GPT and MBR partition maps |
| Data | One large file, many small files, deep trees, Unicode names, sparse files where supported |
| Operations | Create, copy, overwrite, append, rename, move, delete, remount, and safe unmount |
| States | Clean volume, intentionally dirty volume, Windows Fast Startup/hibernated volume, filesystem error |
| Workloads | Repeated long copy, cancellation, low free space, hot-unplug recovery, multiple mounted drives |
| Network | VPN off/on and route changes during a mount, without leaking private identifiers into reports |
| Compatibility | Non-system data volume and a Windows system volume with permission-sensitive directories |

Acceptance requires no silent corruption, deterministic failure messaging, no false read/write
state, successful post-copy SHA-256 verification, and a documented recovery path. Hardware testing
must use disposable test data with a separate backup.

### P2 — Modern helper lifecycle

#### 7. Migrate privileged-helper management to SMAppService

`SMJobBless` and `SMJobCopyDictionary` still work in the current ad-hoc-signed flow but are
deprecated. The migration changes a security-critical installation, approval, upgrade, reconnect,
and uninstall boundary; it should not be mixed into unrelated work.

- [ ] Prototype registration and status behavior with the existing macOS 13+ floor.
- [ ] Prove that the chosen ad-hoc signing model can support a predictable clean-install flow.
- [ ] Define migration from an already installed SMJobBless helper without leaving duplicate jobs.
- [ ] Validate install, approval-required, denial, reinstall, app upgrade, helper mismatch,
  communication failure, uninstall, and app deletion.
- [ ] Update Full Disk Access guidance and screenshots only after macOS presents the new service
  behavior consistently.

**Decision A/B**

- **Option A — migrate after P0/P1 trust work (recommended):** avoids changing the helper boundary
  while security state and driver qualification are still moving.
- **Option B — migrate earlier:** only if a supported macOS update makes the current flow unreliable
  or blocks distribution.

### P3 — Focused UX completion

- [ ] Wire a per-drive **Open in Finder** action to the existing tested opener.
- [ ] Decide whether per-drive transfer telemetry provides reliable, understandable value; either
  wire it correctly for concurrent mounts or remove the unused subsystem in one focused PR.
- [ ] Add mount, unmount, and error notifications with user-controlled behavior.
- [ ] Add Eject All with per-drive results and no loss of a failed mount's recovery controls.
- [ ] Revisit per-drive read-only and mount-point preferences only with a concrete user story and
  complete helper wiring; do not add persisted no-op controls.

## Delivery sequence

Each row is a separate review unit. Branch names are suggestions; BinaryBears implementation
branches start from `dev` and target `dev`. If one result is later suitable for upstream, rebuild
that proposal independently from current `upstream/main`.

| Order | Deliverable | Suggested branch topic | Required evidence before merge |
| --- | --- | --- | --- |
| 1 | GUI/CLI authoritative mount reconciliation | `fix/mount-state-reconciliation` | Cross-surface and external-teardown hardware matrix |
| 2 | NFS endpoint proof or remediation | `security/nfs-transport-contract` | Listener/route/packet evidence; VPN and multi-mount teardown |
| 3 | Runtime Alpine digest pin | `supply-chain/runtime-alpine-pin` | Clean/cached/offline init tests; packaged-binary scan |
| 4 | anylinuxfs update audit workflow | `docs/anylinuxfs-update-policy` | Dry-run audit against the next candidate pin |
| 5 | Live mount security transaction | `security/live-hardening` | PF/route inspection; VPN and multi-mount tests |
| 6 | Security telemetry and Hide | `feat/security-status-ui` | CLI/JSON/GUI parity; no-false-green matrix |
| 7 | Verified Copy core/CLI | `feat/verified-copy-cli` | Failure injection and SHA-256 fixture matrix |
| 8 | Verified Copy GUI | `feat/verified-copy-gui` | Packaged-app UI and cancellation tests |
| 9 | NTFS3 hardware qualification | `test/ntfs3-qualification` | Both-driver hardware report and manifests |
| 10 | Experimental NTFS3 GUI choice | `feat/ntfs3-driver-choice` | Preflight, diagnostics, rollback/error tests |
| 11 | SMAppService migration | `refactor/smappservice-helper` | Clean/upgrade/uninstall matrix on supported macOS |
| 12 | Remaining focused UX items | one branch per item | Automated tests plus packaged-app validation |

## Documentation ownership

| Document | Role |
| --- | --- |
| [`README.md`](../README.md) | Current public overview, quick start, and concise roadmap summary |
| This file | Canonical BinaryBears product roadmap and decision record |
| [`docs/BRANCHING.md`](BRANCHING.md) | Permanent branch roles, upstream synchronization, and contribution procedure |
| [`docs/dev/GUI-PLAN.md`](dev/GUI-PLAN.md) | Current GUI behavior contract and shipped/partial/planned status |
| [`docs/dev/PLAN.md`](dev/PLAN.md) | Historical architecture/build implementation plan |
| [`docs/dev/SHARED_TASK_NOTES.md`](dev/SHARED_TASK_NOTES.md) | Historical execution ledger, not a product-status source |
| [`docs/dev/TESTING.md`](dev/TESTING.md) | Manual real-hardware validation procedure |
| [`build/AUDIT.md`](../build/AUDIT.md) | Vendored-source and build-input audit evidence |

When code behavior changes, update the smallest authoritative document in the same pull request.
Do not copy the whole roadmap into session notes or create another competing roadmap.
