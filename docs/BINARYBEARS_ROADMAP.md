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
and complete GUI/root teardown on 2026-08-13. Every named P0 acceptance cell now passes on the
current Apple Silicon host; broader host/device coverage remains recorded separately in BB-P1-08.
The final BB-F02 safe-eject/uninstall cell passed on 2026-08-14, including the authenticated
no-state/no-PF-anchor teardown proof. The initially accepted BB-01 install cell was reopened after
the later empty-cache first mount proved that the launchd helper supplies `HOME` and invoker IDs but
not `USER`, causing anylinuxfs `init-rootfs` to fail before filesystem access. BB-01 now passes its
corrected packaged onboarding, read-only truth, clean read/write round trip, and authenticated
teardown. BB-F01 hot-unplug reconciliation plus the BB-P1-06/BB-P1-07 driver-policy repeats remain
focused correction-and-retest gates rather than hidden inside completed lifecycle cells.
BB-03 keyboard and login-item behavior passed its corrected packaged retest on 2026-08-16.
The subsequent BB-01 replay confirmed clean removal, but the installed candidate exposed Mount
before Full Disk Access was ready: enabling the permission consumed the first Mount request and
required a manual retry. Source commit `33ce2af` replaces that behavior with a consent-first helper
install, visible setup progress, and a non-mutating pre-mount permission gate; packaged validation
passed on the corrected candidate.
Focused source corrections for the three remaining failures are now implemented: the save panel
intercepts an existing name before AppKit can offer Replace; opt-in read/write NTFS3 uses a
non-mutating mountability probe from a versioned Alpine v2 runtime; and hot-unplug reconciliation
never probes a stale NFS path after physical absence is already authoritative. These changes pass
the complete source gates but remain packaged-retest candidates, not live acceptance evidence.

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
while the same sole helper process remained, completing helper reconnect. The 2026-08-14 physical
no-I/O hot-unplug test then failed: after the raw device disappeared from `diskutil`, the `soft` NFS
mount avoided a host hang but the VM/session and green GUI row remained beyond the bounded
reconciliation interval. The authoritative snapshot must include physical-device presence and
drive failed-closed cleanup when it disappears. Concurrent two-drive state and independent
teardown passed separately. The packaged
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
pass. Rebuilt commit `3a3faab` was installed with matching bundled/staged watchdog hashes and its
first post-authorization retry mounted successfully with private vmnet transport and enforced
security. The 240-second live expiry did not recur naturally, so its packaged cleanup remains an
explicit unmeasured cell rather than a claimed pass.

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
ownership-preservation cycle also passed. The deliberately blank clean-install replay initially
passed its install-only checks on 2026-08-14 with one expected authorization, exactly one helper
registration, matching GUI/CLI version metadata, the complete command surface, and healthy
zero-mount diagnostics. A later empty-cache first mount reopened this gate: `init-rootfs` failed
because the helper environment omitted `USER`. Fix and retest that boundary alongside the separate
fresh-install `Launch at login` availability anomaly tracked under BB-03.

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
- [x] Compare `ntfs-3g` and NTFS3 with the same devices, data set, and Verified Copy manifest.

The 2026-08-14 same-device run passed the 256 MiB payload, a 505-entry regular-only tree, Unicode,
the complete mutation set, and post-remount verification with both drivers. It also identified a
portability failure that keeps the hardware qualification gate red: NTFS3 exposes an `ntfs-3g`
symlink as a regular `IntxLNK` file, and cannot create the same symlink through the macOS/NFS copy
path. Verified Copy failed closed, withheld the final tree, and retained one recoverable partial.
Add an NTFS3 symlink preflight with specific guidance instead of allowing the lower-level
`Invalid argument`/`Operation timed out` pair to be the primary user message.

Windows subsequently enumerated the same `ntfs-3g` link payload as a regular 46-byte file while
backing up both driver test trees without copy failures. This corroborates the portability limit
across the Windows boundary; it does not redefine the POSIX link as a verified Windows symlink.
The first BB-P1-07 Windows-clean subcell also passed its regular-file operation matrix, retained the
256 MiB SHA-256, and completed read-only CHKDSK with no filesystem problem, bad sector, or dirty
bit. The current package then failed the Mac observation under default `ntfs-3g`: an ordinary
directory access returned `Operation timed out` after the fresh 256 MiB copy and mutations, while
the GUI remained green. The test stopped before NTFS3 and recovered through normal Unmount to zero
backend/security state. An independent Windows reread then proved both 256 MiB files retained the
expected SHA-256 and that CHKDSK, bad-sector, and dirty-bit state remained clean. This isolates the
failure to the NFS/backend path and stale-green presentation rather than payload or NTFS corruption.
Require a focused timeout/fail-closed UI investigation and packaged clean-state retest; the
remaining controlled Windows states continue as separate evidence cells. The intentionally dirty
state was then measured separately: NTFS3 correctly produced no host mount and did not fall back,
but surfaced a long raw Linux error transcript instead of a classified dirty-volume refusal.
Default `ntfs-3g` mounted the same dirty media read/write and presented a green GUI. No write was
performed and normal Unmount returned mounts/sessions to zero with the bridge down. Qualification
therefore also requires a deterministic dirty-state preflight/policy for both drivers, concise
recovery guidance, and a packaged repeat. Windows subsequently confirmed that the dirty bit
survived the macOS observations, found no structural error or bad sector, cleared the bit with
`chkdsk /F /X`, and passed both the final dirty query and read-only CHKDSK with exit `0`.
The Windows host exposes hibernation but disables Fast Startup through current system policy
(`HiberbootEnabled=0`), so Fast Startup is recorded as blocked by the available test configuration
instead of changing the operator's machine policy. An actual Windows hibernation with the external
USB attached did not reproduce a hibernated NTFS volume: explicit NTFS3 mounted it read/write with
no fallback, no Mac payload access occurred, and teardown was clean. Windows therefore closed that
removable volume during hibernation; the required fixture remains blocked rather than passed.
After the device was reconnected before Windows resumed, the volume remained non-dirty and a
read-only CHKDSK again completed with no problem, bad sector, or required action. The authenticated
Mac teardown also found no security state file or PF child anchor.

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

P1 is software-complete on 2026-08-12, but qualification has exposed implementation corrections
that remain release gates. Windows independently matched the retained 256 MiB Mac source SHA-256
on the same MobileData volume on 2026-08-14; the controlled same-media TV playback comparison
remains open. The independent clean Windows matrix and reread passed without NTFS corruption, while
the dirty-volume observation failed the required deterministic refusal/presentation policy.
The same-device `ntfs-3g` versus NTFS3 comparison has now run and failed the symlink
portability cell described above; completion of the comparison is not an implied qualification pass.
Replacement commit `db3aacf` passed the same-media physical reconnect and independent 256 MiB
SHA-256 reread on 2026-08-13. Rebuilt commit `3a3faab` then passed the complete packaged minimal-GUI
Verified Copy flow, including active cancellation and recoverable-partial evidence. The remaining
Windows state cells and the focused fixes/retests described above remain open.

### P2 — Modern helper variant

#### 7. Migrate privileged-helper management to SMAppService

`SMJobBless` and `SMJobCopyDictionary` still work in the current ad-hoc-signed flow but are
deprecated. The migration changes a security-critical installation, approval, upgrade, reconnect,
and uninstall boundary; it should not be mixed into unrelated work. BinaryBears has deferred P2 to
a separately buildable modern variant of the same product. It will share the repository, brand,
features, documentation, and release train with the current compatibility variant, while retaining
the distinct internal identity required to prevent helper and installation collisions.

- [ ] Prototype registration and status behavior with the existing macOS 13+ floor.
- [ ] Prove a predictable Developer ID-signed and notarized clean-install flow.
- [ ] Define migration from an already installed SMJobBless helper without leaving duplicate jobs.
- [ ] Validate install, approval-required, denial, reinstall, app upgrade, helper mismatch,
  communication failure, uninstall, and app deletion.
- [ ] Update Full Disk Access guidance and screenshots only after macOS presents the new service
  behavior consistently.
- [ ] Give the P2 variant its own internal bundle/helper identity, migration contract, artifact,
  and validation matrix so it can coexist with or cleanly replace the compatibility variant
  without duplicate helpers or ambiguous ownership; publish both from the same release pipeline.

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
- [x] **Professional DMG presentation:** retain the simple drag-to-Applications install model but
  give the mounted image a polished installer-like Finder layout: large app and Applications
  icons, deliberate alignment and spacing, a restrained branded background/drag cue, and a sized
  window with no accidental clutter. Validate the mounted result visually in light and dark mode,
  verify icon positions and the Applications symlink, and keep ad-hoc signing, right-click Open
  guidance, and DMG-only distribution unchanged.

The initial 2026-08-12 packaged run exposed a Finder-presentation false positive: Launch Services
accepted the NFS URL but no Finder window appeared. The source now asks Finder to reveal the exact
observed mount point before using fallbacks. Replacement commit `db3aacf` visibly opened the
correct Finder window for both concurrently mounted drive rows on 2026-08-13, and BB-P3-01 through
BB-P3-04 now pass on the installed package. BB-P3-05 then passed the professional DMG gate: the
720×460 Finder window uses two 112-point icons, an exact Applications symlink, hidden layout
assets, and a restrained neutral background/drag cue. The compressed image and unchanged app
signature verify, automated packaging coverage passes, and the mounted result passed Light/Dark
visual inspection with the host's Automatic appearance restored. This packaging change does not
expand the normal menu-bar surface. P3's feature-specific cells are complete; the global BB-03
accessibility/lifecycle failure remains a separate release gate.

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

## 2026-08-14 scope boundary

The assisted run is closed with no `IN PROGRESS` acceptance row: measured defects are `FAIL` and
unavailable external-resource cells are `BLOCKED`. The professional DMG was the only implementation
in this checkpoint and is complete. No helper environment, hot-unplug reconciliation, dirty-volume
policy, NTFS3 symlink handling, keyboard/login-item behavior, or Verified Copy panel wording was
mixed into the packaging change. Each remains a later focused correction with its own packaged
retest. At that checkpoint P2 remained a separate edition/version; the product direction approved
on 2026-08-15 below supersedes that classification.

## 2026-08-15 blocker-correction checkpoint

Commit `3c4f23a` implements the focused blocker corrections identified by the closed acceptance
run. The first installed keyboard repeat then proved its BB-03 focus change incomplete; follow-up
commit `864abd8` completes the explicit focus path across every interactive popover surface.

- BB-01 supplies the complete invoking-user environment (`HOME`, `USER`, `LOGNAME`, `SUDO_UID`,
  and `SUDO_GID`) to helper-launched CLI children.
- BB-F01/BB-P1-07 reconciliation combines runtime status, the host NFS table, bounded mount
  responsiveness, and external physical-partition presence. Physical removal triggers exact
  helper teardown immediately; one backend probe failure removes green, while two consecutive
  failures trigger teardown without disturbing surviving mounts. Stale scanner rows for absent
  devices are hidden.
- BB-P1-07 makes `ntfs-3g` use `norecover`, removes the packaged GUI's unsafe read/write override,
  and maps dirty/hibernated failures to concise Windows `chkdsk`/Fast Startup/full-shutdown
  guidance without exposing guest transcripts.
- BB-P1-06 carries the observed filesystem driver into the mounted row and rejects root or nested
  symbolic links before an NTFS3 Verified Copy starts.
- BB-03 gives every main-row action, overflow menu, refresh/security/footer control, Settings
  control, first-run/repair action, diagnostics action, and Verified Copy action an explicit
  keyboard focus stop. A fresh `SMAppService.mainApp.status == .notFound` remains actionable so the
  documented registration call can run and surface its real result.
- Verified Copy validates a fresh destination through the native save-panel delegate before
  AppKit can offer a misleading destructive Replace path; the final validator still refuses every
  existing destination.

Source gates pass Bats `297/297` and Swift `260/260`, including a clean vendored-component rebuild.
These are source fixes, not packaged evidence. BB-01, BB-P1-06, BB-P1-07, and BB-F01 remain `FAIL`
until the newly built app passes the hardware/UI repeats below; BB-03 now has packaged evidence.

The 2026-08-15 keyboard follow-up candidate was built from `864abd8`/`2e0ae09` as
`dist/ntfsmac.dmg`, SHA-256
`bdfcd62b8a7070639a4476301461ca4f630d7b1ade5edfe150161c1e28292fed`. Its strict app signature,
DMG checksum, clean runtime rebuild, and Swift `260/260` gate pass. On 2026-08-16 its installed
forward/reverse keyboard traversal reached every required main, drive, security, footer, Settings,
menu, and Back control. The BB-03 keyboard sub-gate therefore passes; packaged Launch-at-login
enable/readback/disable then also passed: macOS independently reported the app record enabled after
registration and disabled after removal while preserving the privileged helper. BB-03 is `PASS` as
of 2026-08-16.

The subsequent BB-01 clean-install preflight also passes: the in-app uninstall removed helper,
CLI/runtime, user runtime cache/logs, mounts, VM/network processes, session-state files, and PF
child anchors. The app process/bundle and preferences remain intentionally user-level. BB-01 stays
open: the following clean replay requested Full Disk Access only after the first Mount was clicked,
and enabling it did not resume that operation. Commit `33ce2af` now keeps the normal popover gated,
explains the administrator prompt before the explicit helper-install action, shows bounded helper
and CLI preparation progress, probes one raw 512-byte block read-only, and rechecks permission after
System Settings opens. It also versions the XPC protocol independently of the CLI payload so an
older helper cannot be mistaken for one supporting the new preflight. Source gates pass at Bats
`297/297` and Swift `269/269`; a new packaged first-run/mount/teardown repeat remains required.
The replacement DMG was then built from documentation head `3ef125e`, SHA-256
`f02a2c0de0a635516e20928b2e69245f761fa4a1518010e637eac3938549c5e2`; strict deep signature
verification and `hdiutil verify` both pass. This is a candidate artifact, not BB-01 acceptance
evidence until the installed onboarding and first mount pass.

The installed replay then passed the corrected onboarding boundary: no password prompt appeared
before explicit consent, helper/CLI preparation completed, Full Disk Access unlocked the normal
popover, and the first Mount click started the ntfsmac session without a retry. Independent host
and runtime evidence proved that this was the private NFS export, not macOS's native NTFS mount:
the host mounted `diskNsM.local:/mnt/...` as NFS while anylinuxfs reported the paired guest NTFS
filesystem. That guest filesystem landed `ro,norecover`; a write was correctly refused, but the
installed GUI incorrectly remained green because it derived writability only from the host NFS
client. Source commit `06dcd03` now combines both layers and treats read-only at either layer as
read-only. Its focused live-shaped regression test passes; the complete source gates are Bats
`297/297` and Swift `270/270`. BB-01 remains
open until a rebuilt package shows the read-only warning for this fixture, then completes a clean
read/write round trip and authenticated teardown on a known-clean fixture.

The corrected package was built from documentation head `73d3d08` with source fix `06dcd03` as
`dist/ntfsmac.dmg`, SHA-256
`e9a5494c44e8fe68ea07a0cbef1afbf3880b1dc32c92edd1504d89164bafbdc5`. Strict deep app-signature
verification, arm64 inspection, the complete source gates, and `hdiutil verify` pass. It is the
exact candidate for the read-only-truth and clean read/write repeats; it is not acceptance evidence
until installed.

The installed corrected candidate passed the first half of that repeat. The app binary matched the
built candidate byte-for-byte; one click created the real private NFS session, the paired runtime
mount reported `ntfs,ro,norecover`, and the popover immediately showed yellow `Mounted read-only`
with concise Windows recovery guidance. No write was attempted. GUI Unmount removed the host NFS
mount and guest session; diagnostics returned healthy with bridge down and zero security sessions.
The read-only false-green defect is therefore closed on packaged hardware. BB-01 still requires a
known-clean read/write round trip and the authenticated no-state/no-PF-anchor teardown proof.
The operator-authenticated follow-up then confirmed no security state file or PF child anchor, so
only the known-clean read/write round trip and its final teardown remain for BB-01.

That known-clean repeat now also passes on the installed corrected candidate. The second physical
NTFS fixture mounted through `diskNsM.local:/mnt/...`; paired guest status omitted `ro`, the GUI
showed green `Mounted read/write`, and security reported one enforced private session. A fresh
4 MiB payload was flushed, reread byte-for-byte, and matched SHA-256 before its scoped cleanup.
GUI Unmount returned host/guest mounts to zero, lowered the bridge, and left no scoped payload.
At that point only the final operator-authenticated no-state/no-PF-anchor check remained before
BB-01 could become `PASS`.
That final check returned `BB-01-RW-ROOT: PASS` with no security state file or PF child anchor.
BB-01 is therefore fully `PASS` on the installed corrected candidate.

## 2026-08-16 remaining-blocker source correction

Commits `8408f4f` and `e635bb9` trace the repeated packaged failures to three independent
mechanisms and correct them without changing the minimal popover, helper identity, signing model,
or P2 scope:

- **BB-F01:** physical enumeration completed, but the snapshot then ran `stat` against the stale
  NFS mount. A removed soft-NFS endpoint can keep that syscall blocked in the kernel even after the
  child process is signalled, so reconciliation never received its already-known
  `PHYSICAL_DEVICE_MISSING` result. Liveness probes now exclude physically absent devices while
  still checking every surviving mount. Exact per-device helper teardown remains the controller's
  response; no global unmount or PF flush was added.
- **BB-P1-06:** `panel(_:validate:)` occurs too late to prevent AppKit's native Replace sheet in
  this flow. The save-panel delegate now rejects a confirmed existing filename in
  `panel(_:userEnteredFilename:confirmed:)`, leaves the panel open with fixed no-overwrite copy,
  and retains both later validation layers for race-resistant defense in depth.
- **BB-P1-07:** NTFS3 did not share the compatibility driver's `norecover` policy and accepted a
  read/write mount that ntfs-3g classified as unsafe/read-only. Before an opt-in read/write NTFS3
  mount, guest vmproxy now runs `ntfs-3g.probe --readwrite`; any nonzero result fails closed with
  concise Windows full-shutdown/Fast Startup/`chkdsk` guidance. Explicit read-only NTFS3 and other
  filesystems are unchanged. Alpine's `ntfs-3g-progs` package is retained solely to provide that
  non-mutating probe; ntfsmac never invokes its repair tools.

Because the guest package contract changed, the application-owned Alpine cache is now revision 2
(`...-r2`, marker `ntfsmac-alpine-v2`). A v1 cache remains untouched beside it for rollback and
cannot be mistaken for a runtime containing the probe. Completion checks require the real
`/usr/bin/ntfs-3g.probe` binary before a v2 cache is reusable.

Automated evidence is Bats `300/300`, Swift `271/271`, a real host/guest rebuild, Rust probe-
selection coverage, an arm64 host `anylinuxfs`, an aarch64 Linux `vmproxy` containing the refusal
path, static libblkid verification, hypervisor-entitlement checks, and an exact generated rootfs
package manifest. After the packaged save-panel repeat, the live ledger is 26 `PASS`, 2 `FAIL`,
and 2 `BLOCKED`. BB-P1-07 and BB-F01 still require their focused packaged repeats.

The packaged candidate was built from documentation head `8ae12df` with source fixes `8408f4f`
and `e635bb9`. Its SHA-256 is
`6a9cb9cfb20abfd03a40e7c917e39affeba981a81dd68935ff971dd81ffbfb1d`. Strict deep bundle
verification, `hdiutil verify`, arm64 app/helper inspection, aarch64 Linux vmproxy inspection, the
embedded runtime-v2 contract, and the embedded NTFS3 refusal path all pass. It remains an ad-hoc
compatibility artifact and is not ledger acceptance evidence until installed and exercised below.

The candidate was installed and launched on 2026-08-16. Its installed GUI executable exactly
matched the staged artifact. The pre-mount baseline was clean: helper running, zero host mounts,
zero security sessions, no backend/network-helper process, and revision-2 Alpine state
`not_initialized`. A known-clean removable NTFS fixture was available for the first initialization.
The next gate is one GUI Mount request followed by authoritative host/diagnostic convergence; the
baseline alone does not convert any live ledger row.

That first request subsequently passed. Revision 2 initialized, the known-clean fixture mounted
read/write through default `ntfs-3g`, and the popover, NFS table, and schema-6 diagnostics agreed on
one enforced private session. The live vmnet/private/`soft` transport gate passed with no loopback
listener. A new 4 MiB payload matched by bytes and SHA-256 after reread and was removed. GUI
Unmount then reached zero mounts/sessions, bridge down, no backend/network-helper process, and no
scoped artifact. This closes the fresh runtime-v2 and clean compatibility-driver sub-gate; the
authenticated state/PF teardown and the three focused blocker repeats remain open.

The authenticated follow-up also passed with no security state file or PF child anchor. This
completes the candidate's runtime-v2/clean-mount cell. Continue with BB-P1-06 existing-destination
presentation, BB-P1-07 unsafe-state refusal, and BB-F01 two-drive hot unplug; do not credit the
clean-mount result for those distinct behaviors.

The packaged BB-P1-06 existing-destination presentation now passes: the save panel remained open
with the app's direct no-overwrite guidance, no native Replace dialog appeared, the destination
hash and size were unchanged, no copy/partial started, and the scoped fixtures were removed. A
following CLI cleanup removed the NFS mount and all backend/network processes, but the public
diagnostic summary remained at one security session even though that cleanup reported
`NO_SESSION_STATE`. Keep BB-P1-06 unconverted until an authenticated state/PF audit classifies this
as stale presentation or real residue; if residue exists, recover it before any next mount.

The authenticated audit found one real root-owned `diskNsM.state` file and no PF child anchor.
Direct CLI unmount lacked mount's root self-elevation, so it removed the NFS/backend and then
mistook the inaccessible `0700` state directory for `NO_SESSION_STATE`. The source candidate now
self-elevates before unmount begins; GUI behavior is unchanged because the helper is already root.
Focused Bats passes `16/16`. The first full run is intentionally not green (`299/301`) because two
diagnostic tests observed the live residual session; restart recovery plus a clean `301/301` rerun
are the next gates. Do not mount another fixture before recovery.

The first installed recovery attempt correctly failed closed as `STATUS_UNAVAILABLE` and retained
the orphan. `pf-teardown.sh` did not resolve `anylinuxfs` before sourcing the transaction library,
so standalone reconciliation could never acquire backend status without injected context. The
source fix now resolves the installed binary and has a focused passing regression. Because the
currently installed artifact predates that fix, perform one explicit trusted-binary recovery,
prove zero state/anchors/public sessions, then rerun all 302 Bats tests after the new regression is
included. Rebuild/reinstall only after those source gates pass.

The explicit trusted-binary recovery then returned `STALE_SESSIONS_REMOVED`; authenticated checks
proved zero state files, zero PF child anchors, and a zero-session public summary. BB-P1-06 is now
`PASS` on its packaged no-overwrite behavior. Before the remaining two blocker repeats, require a
clean `302/302` source run, rebuild/reinstall, and validate one direct CLI mount/unmount so the two
new teardown/reconciliation fixes have packaged evidence.

The clean source rerun subsequently passed Bats `302/302` and Swift `271/271`. A fresh final
teardown candidate was built with DMG SHA-256
`a00677da68b76cbb68bef6fd0b936fe8e6d04470397085fad2fbeb884f30c637`; the image, strict deep
ad-hoc signature, arm64 executables, static AArch64 vmproxy, and both corrected bundled scripts
were verified. That exact artifact is now installed: the GUI and both corrected scripts match the
candidate byte for byte, its strict deep signature passes, and the pre-test baseline has zero
mounts, sessions, and backend processes. Packaged behavior remains uncredited until the direct
CLI, BB-P1-07, and BB-F01 cells pass on the installed application.

## Approved BinaryBears production direction

After the blocker candidate passes packaged validation, `dev` becomes the canonical BinaryBears
product integration and GitHub distribution source while `main` continues to mirror upstream for
comparison and clean contributions. Distribution remains free, open source, and release-based on
GitHub.

The approved replacement app icon is a 500×500 PNG with alpha, SHA-256
`fcfddbb98d4745fa1e34fd7778283d348a613fa8f5be0a7f500b38cf05eeddc3`. Import it under a neutral
repository-owned filename during the rebranding commit, generate the complete `.icns` set, and
replace every app/DMG/README/site use together. Do not commit the operator's original download
path or generator filename.

Production releases will later use a BinaryBears Developer ID and Apple notarization. The
identifier/helper-label migration, signing identity, entitlements, update/uninstall behavior, and
old-install cleanup require a dedicated rebranding migration. Apple credentials and notarization
secrets belong only in local Keychain/GitHub encrypted secrets, never in Git.

The production identity gate includes the Full Disk Access presentation observed on 2026-08-16.
The compatibility helper is a standalone SMJobBless `TOOL`; even though its embedded plist already
declares `CFBundleDisplayName=ntfsmac Helper`, System Settings shows the raw
`com.khr898.ntfsmac.helper` label and a generic tool icon because there is no resource bundle from
which to resolve an icon. The compatibility rebrand must at minimum remove every `khr898` identity
and use the BinaryBears reverse-DNS label. A friendly helper name and branded icon in System
Settings are explicit P2/SMAppService acceptance targets and must be proved on installed macOS,
not inferred from plist keys that the OS may ignore.

P2 is no longer an unrelated app. It is the modern compatibility variant of the same BinaryBears
product: one name, one public repository, one roadmap, and one release pipeline should produce both
the current compatibility artifact and the future P2 artifact. They may require distinct internal
bundle/helper identifiers and artifact suffixes so they cannot collide, but their UX, feature
contract, documentation, and fixes should remain shared wherever technically possible. GitHub
Actions must eventually build/test both variants in a matrix and publish both DMGs in the same
release. The GitHub Pages product site follows rebranding and should remain macOS-like, polished,
animated with restraint, accessible, and fast.

## Exact next-agent handoff

Start from `dev` with the earlier blocker commits plus `8408f4f` (hot-unplug/save panel),
`e635bb9` (NTFS3/runtime v2), `58e6998` (privileged direct CLI unmount), and `ac42b7c`
(standalone reconciliation). Do not push unless explicitly authorized. Current source gates are
Bats `302/302` and Swift `271/271`.
Preserve the minimal popover and do not mix identity/signing migration into the blocker retest.

The already-built DMG
`a00677da68b76cbb68bef6fd0b936fe8e6d04470397085fad2fbeb884f30c637` is installed and its clean
baseline is verified. Run the packaged retest in this order:

1. **BB-01 — complete:** corrected DMG `e9a549…fbdc5`
   containing `06dcd03` correctly presented the rw-NFS/ro-guest fixture as yellow/read-only.
   The consent/progress/Full Disk Access gate and first-click session startup already passed on
   `f02a2c…c5e2`. The known-clean fixture also landed read/write and passed its 4 MiB byte/hash
   round trip plus non-root teardown. The final authenticated zero-state/PF check also passed;
   do not repeat unless onboarding, helper identity, mount reconciliation, or teardown changes.
2. **BB-03 — complete:** installed keyboard traversal and the independently read-back Launch at
   login enable/disable cycle passed on `bdfcd6…92fed`; do not repeat unless related code changes.
3. **BB-P1-06 and save panel — complete:** the previous packaged app rejected a local
   directory containing a nested symlink with the specific NTFS3 warning before destination
   publication, with no new partial. The final candidate intercepted an existing name before
   AppKit's Replace flow: the panel stayed open with direct no-overwrite guidance, destination
   size/hash stayed unchanged, and no copy or partial started. BB-P1-06 is `PASS`.
4. **Direct CLI teardown/reconciliation — complete:** packaged fallback cleanup exposed
   that direct CLI unmount did not self-elevate and standalone `pf-teardown.sh` did not resolve its
   backend status binary. The orphan was recovered with authenticated zero-state/PF/public-summary
   evidence. The final installed candidate then mounted a known-clean fixture through direct CLI
   with one enforced private session. Direct CLI Unmount authenticated before mutation, returned
   `SESSION_REMOVED`, and reached zero mount/backend/diagnostic/public sessions. The authenticated
   final audit found no state file or PF child anchor. Do not repeat unless CLI privilege ordering,
   teardown, or reconciliation changes.
5. **BB-P1-07 dirty policy — packaged probe false negative:** on the same unrepaired disposable volume,
   default `ntfs-3g` landed read-only with the corrected yellow recovery state, while explicit
   NTFS3 mounted read/write with no fallback. No payload write was issued. Treat this as a policy
   failure, not as NTFS3 recovery evidence. The final runtime-v2 package contained and executed the
   intended `ntfs-3g.probe` eligibility path, but that probe accepted the Windows-confirmed dirty
   fixture and NTFS3 then failed with the raw backend transcript. No host mount, backend, or session
   remained. Replace the insufficient eligibility signal with a reliable classified refusal before
   a guest NTFS3 mount is attempted, retain concise Windows guidance, then repeat on the still-dirty
   fixture. Only after that refusal passes, repair/clean on Windows and repeat mount/hash/unmount/
   Windows reread.
6. **BB-F01 hot unplug — source fix ready:** with USB_8GB on NTFS3 and MobileData on
   default `ntfs-3g`, physically removing only USB_8GB left its NFS mount, VM, security session,
   and green row alive for more than 30 seconds even though physical enumeration lost it
   immediately. Manual stale-row Unmount performed exact selective teardown and preserved
   MobileData; final normal Unmount reached zero, and the authenticated root check found no state
   files or PF child anchors. Repeat the two-drive no-I/O removal: the removed row must leave green
   promptly and its exact mount/VM/security state must disappear automatically while the survivor
   remains mounted and enforced. A controlled backend-stall cell remains optional when available.
7. Run strict signature verification, `hdiutil verify`, Bats `302/302`, Swift `271/271`, and the
   authenticated zero-state/PF check; only then convert the two remaining ledger rows from FAIL
   to PASS.
8. **Resource-gated qualification:** run the controlled TV comparison and extended GPT/low-space/
   controller/OS/system-volume matrix only when those external resources are actually available.

Once steps 1–7 pass, begin the rebranding/production migration as a new review unit: replace the
icon everywhere, migrate BinaryBears identifiers safely, sign/notarize, update Actions/releases,
and revalidate the professional DMG. That change intentionally reopens BB-P3-05. Implement the P2
variant later in the same product/release pipeline, not as an unrelated application.

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

The 2026-08-14 packaged Full Keyboard Access pass found incomplete traversal in the main popover:
the first drive's Mount action, Diagnose, and Quit were skipped while the remaining tested controls
accepted focus. Treat this as a focused accessibility correction under item 12; preserve the current
minimal layout and retest the installed package before closing BB-03.

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
