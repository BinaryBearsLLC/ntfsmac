# BinaryBears ntfsmac Roadmap

> [!IMPORTANT]
> This roadmap applies only to the
> [`BinaryBearsLLC/ntfsmac`](https://github.com/BinaryBearsLLC/ntfsmac) fork. It is not a
> commitment on behalf of the original [`khr898/ntfsmac`](https://github.com/khr898/ntfsmac)
> project or the [`nohajc/anylinuxfs`](https://github.com/nohajc/anylinuxfs) project.

This is the canonical product roadmap for the BinaryBears fork. It replaces the older practice
of treating implementation plans, test-session notes, and private scratch files as a current
feature list. The code status below was reconciled on 2026-08-12 against `upstream/main` at
`0725c31` (`v2.1.090826`) and the BinaryBears live-security completion at `762cc91`.
The original live hardware findings from 2026-08-06 are recorded in
[Live Mount-State and NFS Transport Audit — 2026-08-06](audits/LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md)
and the focused VPN-on P0 follow-up is recorded in
[Live P0 Security Transaction Audit — 2026-08-11](audits/LIVE_P0_SECURITY_TRANSACTION_AUDIT_2026-08-11.md).
Untested matrix cells remain release gates even when the implemented acceptance checks pass.
The current packaged acceptance ledger is
[BinaryBears packaged validation results — 2026-08-12](testing/BINARYBEARS_VALIDATION_RESULTS_2026-08-12.md).
Replacement commit `db3aacf` passed its default real-hardware mount, measured security transaction,
and complete GUI/root teardown on 2026-08-13; the remaining P0 hardware matrix cells stay open.

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
| `upstream-pr/<N>of<total>-*` | One ordered change proposed to khr898 | Start the series from current `upstream/main`; exclude fork branding/roadmap and refresh each dependent candidate after its predecessor merges |

Upstream changes are integrated into `dev` as an explicit sync after `main` is updated. Already
accepted work is taken from upstream's final implementation rather than replaying the fork's older
version of the same commits. This keeps maintainer fixes authoritative and reduces recurring
conflicts.

The current four-part upstream candidate series, its dependency order, exact validation evidence,
and local/remote publication state are recorded in [`BRANCHING.md`](BRANCHING.md). Preparing those
branches does not imply that they were pushed, opened as pull requests, or accepted upstream.

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
- [x] Per-drive **Open in Finder** using the reconciled mount point, never a guessed path.
- [x] Mount, unmount, error, and Eject All notifications behind an explicit opt-in that persists
  only after macOS grants notification permission.
- [x] **Eject All** attempts every mounted drive, reports each result, and keeps failed-drive
  recovery controls visible.
- [x] SECURITY rows default to `unknown` instead of manufacturing a successful state.
- [x] SECURITY Hide/Show changes presentation only and leaves mount/helper state untouched.
- [x] Runtime Alpine tag/digest pinning, versioned cache migration, diagnostics, and package gate.
- [x] Runtime-cache ownership self-heal across privileged upgrades, without following symlinks or
  requiring a manual ownership command.

### Foundations that are not complete product features

- [-] **NTFS3:** CLI parsing, helper/XPC transport, one-mount GUI opt-in, preflight guidance, and
  privacy-safe result diagnostics exist and are tested; BinaryBears hardware qualification is
  still a release gate.
- [-] **Security hardening:** per-session PF/route enforcement is integrated into CLI and GUI
  mount/unmount paths with measured reason-coded state. The Option-A transaction observes the
  new vmnet `/30`, applies the exact route and PF policy before anylinuxfs performs its NFS
  reachability check, then publishes success only after the final soft-NFS proof. CLI text/JSON
  and the compact GUI use the same fixed states and privacy-safe reasons; the remaining real-
  hardware matrix is still required.
- [x] **Verified Copy software:** the CLI owns copy-to-partial, flush, reread, deterministic
  SHA-256 verification, and same-filesystem publication. Each verified read/write GUI row exposes
  the same workflow through a small overflow action with exact-volume validation, compact state,
  and whole-process-group cancellation. Post-reconnect media qualification remains a separate
  hardware gate.
- [x] **Open in Finder:** every verified mounted-drive row opens its own observed mount point.
- [x] **Transfer telemetry decision:** the unused global sampler and speed row were removed. A
  bridge-wide byte counter cannot truthfully attribute traffic to concurrent drives, so the
  minimal UI presents no misleading transfer speed.
- [-] **Authoritative mount-state synchronization:** implemented with paired anylinuxfs-session
  and host NFS-mount evidence, bounded polling, and a fail-closed unknown state. Unit/state tests
  pass; the packaged-app hardware matrix below is still a release gate.
- [-] **NFS transport contract:** ntfsmac now pins anylinuxfs to `--net-helper vmnet`, reports a
  privacy-safe transport-contract token, and includes a fail-closed live route/listener gate.
  The packaged app passed that gate with one real NTFS device across VPN-on, VPN-off, and live
  route transitions; concurrent-device transport-gate evidence remains open.

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
- [-] Complete packaged-app hardware tests for GUI→CLI, CLI→GUI, external teardown, crash
  recovery, restart recovery, Refresh, hot-unplug, and multiple drives.

On 2026-08-11 the packaged 2.1 candidate passed GUI mount, GUI unmount, Finder network-share
disconnect, and a second external NFS unmount while the app remained open. In each teardown the
host mount, anylinuxfs session, private VM/bridge, exact route, and GUI green state disappeared.
The app also remained in `mounting` while the helper operation was in flight. On 2026-08-12 a
forced GUI-only termination preserved the real mount; `opengui` relaunched one process, recovered
the authoritative RW/security state, and a normal Unmount left no NFS session, security state file,
or PF child anchor. On 2026-08-13 the current installed package also passed GUI-created mount to
installed-CLI Unmount reconciliation both passively and with immediate Refresh: the open GUI left
green in under one second and diagnostics settled to zero mounts/sessions. The reverse CLI mount
then passed its passive functional path: with the app process still running, reopening the
menu-bar popover discovered the CLI-created RW mount and enforced security state; Open targeted
the exact MobileData Finder window and GUI Unmount returned to healthy zero state. The menu-bar
popover closing while Terminal owns focus is normal AppKit presentation, not an app exit. Only the
immediate-Refresh repeat then showed the same CLI-created disk6s1 RW state and all three truthful
SECURITY rows; final GUI Unmount again cleared the mount, session, and bridge. This completes the
current packaged cross-surface cell. The current package also passed the Finder external-disconnect
half of the teardown cell: ejecting only the synthetic `disk6s1.local` share removed host NFS,
session security, VM/bridge, and GUI green state by the first observation. The independent
operator-authenticated `/sbin/umount` repeat produced the same automatic zero-mount/session/bridge
state without Refresh. The final root inspection found no state files or PF child anchors,
completing the current external-disconnect cell. The operator then restarted the exact launchd
helper with no active mount; one job, one helper process, and the expected plist/binary pair remain,
and the first post-restart GUI mount/unmount succeeded without reinstall or another authorization.
The mount reached verified RW with one enforced session; teardown returned to healthy zero state
while the same sole helper process remained, completing helper reconnect. Physical hot-unplug also
remains. Concurrent two-drive state and independent teardown passed separately. The packaged
public-evidence fault cell also passed: making only the root-owned security summary world-writable
changed all three GUI security claims and schema-6 diagnostics to reason-coded `unknown` before a
manual Refresh, without misclassifying the still-present NFS mount. Restoring `0644` recovered the
measured enforced state automatically, and final GUI teardown returned to zero mounts/sessions with
the bridge down. This closes the current fail-closed public-evidence gate.

The first new mount attempted immediately after that VPN-transition cycle then remained in vmnet
startup for about 150 seconds without creating an NFS mount or security session. The packaged GUI
correctly stayed non-green on `Mounting…`, and the operator's scoped process-group recovery left
zero backend processes, mounts, sessions, or bridge state while preserving the VPN default. The
existing packaged watchdog is 240 seconds and was not allowed to expire, so this observation does
not claim that its bound failed. Source review nevertheless found that its timeout killed only the
direct child even though anylinuxfs may move the VM supervisor into another process group. The
working tree now terminates the snapshotted descendant tree, reports fixed `backend_timeout`
diagnostics, and renders one concise minimal-UI recovery message. Automated shell and Swift tests
pass; a rebuilt packaged expiry/retry is still required before closing this new lifecycle finding.

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
- [x] Resolve `diskNsN.local` during a live mount and prove which endpoint the kernel actually
  uses. Confirm that no NFS listener is exposed on non-loopback or unrelated interfaces.
- [x] Select the direct private-`/30` path and force `--net-helper vmnet` on every ntfsmac mount,
  so a stale per-user anylinuxfs configuration cannot silently re-enable gvproxy.
- [x] Add privacy-safe diagnostics for transport topology and enforcement state without exporting
  addresses, interface names, volume labels, or device identifiers.
- [x] Add a read-only packaged-app gate that fails on gvproxy, a loopback NFS listener, a
  non-private endpoint/route, or a non-`soft` ntfsmac mount.
- [-] Execute that gate with the packaged app on real hardware for VPN off/on, concurrent mounts,
  teardown, and helper recovery, retaining only privacy-safe results in the repository.

On 2026-08-11 one packaged VPN-on session passed the privacy-safe transport gate: private `/30`
endpoint, bridge route, vmnet helper, soft NFS, and no loopback listener. Effect checks reached
only the intended NFS/mountd ports and rejected unrelated bridge ports. Teardown removed the
session and returned endpoint routing to the pre-existing VPN. On 2026-08-13 the current package
repeated the VPN-on gate and then passed a live VPN-on -> VPN-off -> VPN-on transition without
unmounting: the GUI remained truthful automatically and after Refresh, schema-6 diagnostics and
the authenticated security gate stayed enforced, reads succeeded in every state, NFS remained
private/vmnet/soft with no loopback listener, and each system default route changed only with the
operator's VPN action. Final teardown preserved the restored VPN default and removed the mount,
session, bridge, state file, and PF child anchor. The concurrent-mount transport-gate cell remains
open; helper reconnect passed the separate packaged recovery cell.

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
- [x] Repair the legacy root-owned cached `vmproxy` during privileged package staging and restore
  the invoking user's host ownership after every later privileged runtime replacement.

The immutable digest-only pull reference, cache directory, and rootfs version marker are derived
from the same locked tag, arm64 digest, and anylinuxfs commit; the build independently proves the
tag resolves to that digest. Legacy, incomplete, or mismatched caches are preserved
side-by-side; initialization is triggered only by a mount that needs the pinned environment.
The installer also self-heals the specific root-owned `rootfs/vmproxy` left by older privileged
updates. The runtime's update path restores the XPC peer's kernel-derived UID/GID after replacing
that host file while retaining its guest-visible root metadata. Real non-symlink path checks,
focused installer/build coverage, the full `289/289` Bats suite, Swift `247/247`, and a complete
runtime rebuild pass. Replacement commit `db3aacf` passed the affected BB-01 upgrade-cache staging,
unprivileged backend enumeration, and two-row popover checks on 2026-08-13; its mount/unmount and
ownership-preservation cycle also passed. Only the deliberately blank clean-install cell remains.

#### 2. Establish an anylinuxfs update policy

The fork does **not** retrieve the newest anylinuxfs source on every build. Git checks out the
exact submodule revision recorded by this repository; the current audited pin is
`8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3`. This is deliberate and should remain visible.

- [x] Add a repeatable audit checklist covering upstream commits, release notes, dependency-lock
  changes, local patches, filesystem behavior, packaging, and hardware regression tests.
- [x] Require every accepted pin change to be recorded in `build/AUDIT.md` and the pull request.
- [x] Never auto-merge a source update that changes the privileged, VM, NFS, or filesystem path.

The selected policy is **Option A**. The read-only workflow and complete review gates live in
[`docs/dev/ANYLINUXFS_UPDATE_POLICY.md`](dev/ANYLINUXFS_UPDATE_POLICY.md). Its 2026-08-08 dry-run
against upstream `v0.19.0` passed ancestry/delta/local-patch checks but deliberately deferred the
pin change pending dependency, build, and hardware evidence.

**Decision A/B**

- **Option A — periodic audited pin updates (recommended):** check upstream on a release cadence,
  review the diff, update the submodule and pins in one dedicated PR, then run the full gates.
- **Option B — automated update PRs:** a bot may open pin-update PRs, but they remain blocked from
  merge until the same human review and hardware matrix pass. Do not build from a floating branch.

#### 3. Make security hardening effective during a real mount

- [x] Define one transactional sequence: mount preparation → private link discovery → route policy
  → packet-filter policy → NFS mount → measured status publication.
- [x] Verify that the packet-filter rules are attached to an evaluated PF ruleset path; loading a
  named anchor alone must not be treated as proof of enforcement.
- [x] Apply and remove VPN-bypass routes per active mount without breaking unrelated routes.
- [x] Make teardown idempotent across unmount, Quit, failed mount, helper reconnect, and crash
  recovery.
- [x] Support concurrent mounts without one teardown invalidating another mount's protections.
- [x] Publish reason-coded state: `enforced`, `notEnforced`, `notRequired`, or `unknown`.

The implementation uses one direct-child `com.apple/ntfsmac-<device>` anchor, PF enable token,
state file, and optional exact host route per active mount. It proves the macOS `com.apple/*`
evaluation path, detects both full- and split-tunnel VPN capture,
measures the loaded child rules, bounds status recovery, and removes only state owned by the
target session. Root helper mutations are serialized across XPC connections, and normal uninstall
stops when session cleanup cannot be proven. Because upstream anylinuxfs creates vmnet and then
waits for NFS inside one command, ntfsmac runs that command under a bounded supervisor, observes
the newly created validated bridge and `/30`, and installs the measured route/PF policy before
allowing the backend's NFS reachability check to succeed. A backend or final-proof failure releases
the early resources, preserving cleanup-pending state only when release itself cannot be proven.

**Decision A/B**

- **Option A — visible best-effort rollout (recommended first):** permit the mount, but show a
  prominent non-green state whenever hardening cannot be proven.
- **Option B — strict mode:** roll back or reject the mount when required policy cannot be proven.
  Consider this only after the live implementation is stable; it may later become an explicit
  user setting.

Selected: **Option A**. Missing PF tools, an unevaluated anchor path, unsafe route evidence, stale
state, or unverified `soft` semantics produce a non-green reason code while leaving the mounted
volume usable. `tests/live/verify-security-transaction.sh` is the privacy-safe packaged-app gate;
the VPN-off/on and live-route-transition hardware cells pass, while the concurrent-drive gate
remains required before release.

#### 4. Complete evidence-backed SECURITY UI

- [x] Replace generic promises with narrowly measured labels such as **Private VM link**,
  **VPN-safe route**, and **PF policy enforced**.
- [x] Add the requested **Hide** action without changing mount or helper state.
- [x] Feed the same state and privacy-safe reason codes to CLI text, CLI JSON, and GUI diagnostics.
- [-] Test mounted/unmounted, VPN on/off, multiple mounts, missing tools, stale state, malformed
  output, helper reconnect, and teardown. No missing result may become a green check.

The automated state/parser/aggregation suite covers idle, enforced, non-enforced, missing,
malformed, stale, VPN-captured, teardown, and concurrent-session behavior. VPN-off/on,
live-route transition, and helper reconnect now pass on packaged real hardware; the broader
concurrent-drive transport claim still needs its dedicated gate.

### P1 — Verifiable copying and controlled NTFS3 adoption

#### 5. Add Verified Copy with SHA-256

Finder and third-party applications write to the exported NFS volume directly, so ntfsmac cannot
reliably intercept every ordinary copy. A trustworthy integrity feature must own the copy or be
described only as a later verification, not as transparent protection for all Finder operations.

- [x] Add `ntfsmac copy --verify <source> <destination>` using streaming SHA-256.
- [x] Copy to a temporary destination, flush it, reread the destination, compare type/size/hash,
  then rename atomically where the destination filesystem supports it.
- [x] Add `ntfsmac verify <source> <destination>` for an existing file or directory tree.
- [x] For directories, generate a deterministic manifest of relative path, entry type, size, and
  SHA-256; define explicit symlink and metadata behavior.
- [x] Preserve the source and keep a failed temporary destination clearly recoverable; never
  delete the source automatically.
- [x] Add a GUI **Verified Copy** flow only after the CLI/core behavior is complete.
- [x] State the limit honestly: a successful comparison validates the bytes read at that time; it
  cannot guarantee against later media failure or preserve every platform-specific metadata field.

The destination must not exist. The CLI copies to a hidden partial directory beside the final
name, calls `sync`, rereads source and destination into sorted manifests, and only then renames the
payload into place. Regular-file bytes and sizes, directory entry types, and symlink target text
are verified; permissions, ownership, ACLs, extended attributes, resource forks, timestamps,
hard-link relationships, and sparse allocation are explicitly outside this integrity contract.
When macOS represents excluded destination metadata as `._*` AppleDouble files, normalization is
strict: only a valid destination-only sidecar with a paired entry and no same-path source entry is
omitted. Real source entries named `._*` remain byte-verified.

The GUI adds no permanent copy page: **Verified Copy…** lives in the mounted drive row's overflow
menu and appears only for an independently verified read/write mount. Native source/destination
panels feed literal argv to the unprivileged installed CLI, never a shell or the privileged helper.
The destination parent must resolve inside the selected mount and retain the same filesystem
identity immediately before launch; existing and broken-symlink destinations are rejected. While
one copy is active, mount/unmount/Eject All/Settings/Quit actions are disabled. Cancel signals the
dedicated CLI process group, retains the source and any partial destination, and never publishes a
final name as success.
Replacement commit `db3aacf` passed the installed-package 505-entry nested/Unicode/symlink tree and
independent manifest verification on real NTFS hardware on 2026-08-13, including destination-only
AppleDouble sidecars. Its installed CLI interruption test also exited `130`, preserved the 4 GiB
source, withheld the final name, and retained one recoverable partial as designed.

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

**Decision: Option A implemented**

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
- [x] Add preflight guidance: disable Windows Fast Startup, fully shut down Windows, and repair
  filesystem errors with Windows `chkdsk`. Never recommend `ntfsfix` as a substitute repair.
- [x] Add explicit **Experimental** labeling, compatibility differences, and a one-mount driver
  choice in the GUI; no silent fallback between drivers.
- [x] Record the selected driver and privacy-safe failure category in diagnostics.
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

P1 is software-complete on 2026-08-12. The same-media post-reconnect/Windows verification and
same-device `ntfs-3g` versus NTFS3 qualification above remain release gates, not implied passes.
Replacement commit `db3aacf` passed the same-media physical reconnect and independent 256 MiB
SHA-256 reread on 2026-08-13; Windows and the driver comparison remain open.

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

- [x] Wire a per-drive **Open in Finder** action to the existing tested opener.
- [x] Add automation-safe `ntfsmac opengui` presentation of the same minimal popover, without
  Accessibility permission or synthetic clicks. Cold launch waits for a real menu-bar anchor;
  repeated requests coalesce instead of creating windows or app instances.
- [x] Remove the global transfer sampler and speed row: the available counters cannot reliably
  attribute concurrent traffic per drive, and an aggregate number would be misleading.
- [x] Add mount, unmount, and error notifications with user-controlled, default-off behavior.
- [x] Add Eject All with per-drive results and no loss of a failed mount's recovery controls.
- [x] Keep per-drive read-only and mount-point preferences out of the UI until a concrete user
  story and complete helper wiring exist; no persisted no-op controls were added.
- [ ] **Professional DMG presentation:** retain the simple drag-to-Applications install model but
  give the mounted image a polished installer-like Finder layout: large app and Applications
  icons, deliberate alignment and spacing, a restrained branded background/drag cue, and a sized
  window with no accidental clutter. Validate the mounted result visually in light and dark mode,
  verify icon positions and the Applications symlink, and keep ad-hoc signing, right-click Open
  guidance, and DMG-only distribution unchanged.

The initial 2026-08-12 packaged run exposed a Finder-presentation false positive: Launch Services
accepted the NFS URL but no Finder window appeared. The source now asks Finder to reveal the exact
observed mount point before using fallbacks; the rebuilt artifact must pass the per-drive live
check before P3 can be called packaged-valid. Replacement commit `db3aacf` visibly opened the
correct Finder window for both concurrently mounted drive rows on 2026-08-13. The professional
DMG presentation is a separate open packaging-UX item and does not expand the normal menu-bar
surface.

The same replacement package passed the two-drive Eject All success path on 2026-08-13: the
compact report showed one `Unmounted` result per original row, both mounts and security sessions
settled to zero, the bridge stopped, and an operator-authenticated check found no security state
files or PF child anchors. The safe packaged partial-failure attempt then exposed a security
postcondition defect: anylinuxfs returned zero while a read-only working-directory hold kept the
host NFS mount active, so the CLI removed that drive's security session prematurely. Diagnostics
correctly became unhealthy with one host mount and zero security sessions; normal Unmount recovered
after releasing the hold. The CLI now proves the target disappeared from the authoritative host
mount table before tearing down per-session PF/route ownership and retains protection when that
proof fails. Regression coverage includes a false-zero busy mount, an unreadable mount table, and
a volume name containing spaces. The rebuilt installed package passed the functional repeat: the
held drive remained accessible and retained one enforced security session, the idle drive left,
the per-drive report and recovery controls stayed truthful, and normal Unmount recovered to a
healthy zero-mount state after release. The final operator-authenticated check found no private
state files or PF child anchors, completing the packaged partial-failure cell.

The 2026-08-13 packaged notification run confirmed the default-off boundary and explicit macOS
prompt, then exposed two lifecycle edge cases without changing the minimal Settings surface. macOS
committed the operator's Allow choice while the async request returned an error, and a notification
scheduled while ntfsmac was foreground received an empty presentation option set. Source now
reconciles system authorization after a request error and retains a foreground delegate that asks
for the same concise banner plus sound. Commit `d99c4ac` then rebuilt successfully with `292/292`
shell tests and `249/249` Swift tests. The resulting arm64 app passed strict code-signature checks
and its verified DMG has SHA-256
`c7bacbbec54a303f3ee2541da49a916b9668b8ac78c825151fb0fdce5c0a8905`; the packaged
retest then delivered mount, foreground unmount, and controlled-failure requests with banner and
sound presentation options. macOS muted their visible presentation only because the display was
shared during assisted control. The failure retained its mount and security session until recovery,
and a complete mount/unmount cycle with the app preference disabled created no notification
requests. The operator then revoked ntfsmac in System Settings: reopening the in-popover Settings
reconciled the persisted opt-in to off and presented actionable System Settings guidance. This
completes the packaged notification matrix. The unusual first-grant callback race was observed on
the preceding installed package and is covered by the focused authorization regression in the
rebuilt source; macOS does not return an already registered application to `notDetermined` through
its normal notification controls.

The same run found a cold-launch timing defect in `opengui`: the installed app truthfully recovered
the surviving mount but presented its popover at the lower-left of the screen. Source now defers
presentation until AppKit exposes valid menu-bar screen geometry and has regression coverage for
the rejected fallback position. Rebuilt commit `004e76e` passed anchored cold and warm opens, three
simultaneous requests with one process, invalid-argument handling, and the no-Accessibility
contract.

P3's packaged-app checks are part of the
[assisted manual acceptance runbook](testing/BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md); they do
not replace the still-open P0/P1 hardware qualification gates.

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
| 9 | Experimental NTFS3 GUI choice | `feat/ntfs3-driver-choice` | Preflight, diagnostics, and explicit no-fallback/error tests |
| 10 | NTFS3 hardware qualification | `test/ntfs3-qualification` | Both-driver hardware report and manifests |
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
| [`docs/dev/ANYLINUXFS_UPDATE_POLICY.md`](dev/ANYLINUXFS_UPDATE_POLICY.md) | Mandatory review and evidence gates for anylinuxfs pin changes |
| [`build/AUDIT.md`](../build/AUDIT.md) | Vendored-source and build-input audit evidence |

When code behavior changes, update the smallest authoritative document in the same pull request.
Do not copy the whole roadmap into session notes or create another competing roadmap.
