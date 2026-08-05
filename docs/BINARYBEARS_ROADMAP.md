# BinaryBears ntfsmac Roadmap

> [!IMPORTANT]
> This roadmap applies only to the
> [`BinaryBearsLLC/ntfsmac`](https://github.com/BinaryBearsLLC/ntfsmac) fork. It is not a
> commitment on behalf of the original [`khr898/ntfsmac`](https://github.com/khr898/ntfsmac)
> project or the [`nohajc/anylinuxfs`](https://github.com/nohajc/anylinuxfs) project.

This is the canonical product roadmap for the BinaryBears fork. It replaces the older practice
of treating implementation plans, test-session notes, and private scratch files as a current
feature list. The status below was reconciled on 2026-08-05 against upstream/BinaryBears `main`
at `d2b151d` (`v2.0.050826`) and the preserved pre-sync BinaryBears `dev` at `e9f85e5`.

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
- [x] Multiple concurrent drive entries and per-drive mount/unmount state.
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

### Foundations that are not complete product features

- [-] **NTFS3:** CLI parsing, helper/XPC transport, and command construction exist and are tested;
  there is no GUI choice and no recorded BinaryBears NTFS3 hardware qualification yet.
- [-] **Security hardening:** packet-filter and VPN-route primitives plus unit tests exist, but
  they are not integrated into the live mount transaction and do not feed measured GUI state.
- [-] **Open in Finder:** the tested `FinderOpener` implementation exists, but the current
  multi-drive popover does not expose a corresponding control.
- [-] **Transfer telemetry:** the sampling subsystem and tests remain in the codebase, but the
  current multi-drive UI deliberately does not present a speed row.
- [-] **Alpine reproducibility:** build-time code verifies a pinned Alpine tag and arm64 digest,
  but the shipped anylinuxfs/init-rootfs defaults still contain `alpine:latest`. A first-run
  initialization can therefore fetch runtime content that is newer than the reviewed build pins.

## Prioritized roadmap

### P0 — Trust, reproducibility, and truthful security

#### 1. Pin the runtime Alpine environment

- [ ] Replace the shipped `alpine:latest` defaults with an exact tag and platform digest derived
  from `build/sources.lock`.
- [ ] Add a packaging gate that rejects a shipped runtime containing an unapproved
  `alpine:latest` reference.
- [ ] Record the initialized rootfs version/digest in privacy-safe diagnostics.
- [ ] Define an explicit migration path for an existing `~/.anylinuxfs/alpine` cache; never
  silently destroy user data or force a download during an unrelated action.
- [ ] Test clean initialization, cached initialization, offline reuse, digest mismatch, interrupted
  download, and upgrade/rollback behavior.

This closes the difference between a pinned source/build input and the image actually downloaded
on a user's first mount.

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
- [ ] Add the requested **Hide** action without changing mount or helper state.
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
| 1 | Runtime Alpine digest pin | `supply-chain/runtime-alpine-pin` | Clean/cached/offline init tests; packaged-binary scan |
| 2 | anylinuxfs update audit workflow | `docs/anylinuxfs-update-policy` | Dry-run audit against the next candidate pin |
| 3 | Live mount security transaction | `security/live-hardening` | PF/route inspection; VPN and multi-mount tests |
| 4 | Security telemetry and Hide | `feat/security-status-ui` | CLI/JSON/GUI parity; no-false-green matrix |
| 5 | Verified Copy core/CLI | `feat/verified-copy-cli` | Failure injection and SHA-256 fixture matrix |
| 6 | Verified Copy GUI | `feat/verified-copy-gui` | Packaged-app UI and cancellation tests |
| 7 | NTFS3 hardware qualification | `test/ntfs3-qualification` | Both-driver hardware report and manifests |
| 8 | Experimental NTFS3 GUI choice | `feat/ntfs3-driver-choice` | Preflight, diagnostics, rollback/error tests |
| 9 | SMAppService migration | `refactor/smappservice-helper` | Clean/upgrade/uninstall matrix on supported macOS |
| 10 | Remaining focused UX items | one branch per item | Automated tests plus packaged-app validation |

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
