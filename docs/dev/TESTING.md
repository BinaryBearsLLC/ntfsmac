# ntfsmac — manual test guide

> [!NOTE]
> This is the real-hardware procedure and a record of earlier gaps, not the product roadmap. See
> [`../BINARYBEARS_ROADMAP.md`](../BINARYBEARS_ROADMAP.md) for current completion status and
> pending NTFS3/security/integrity work. Statements labelled **Was** or **Fixed** are retained as
> historical evidence; the explicit current-state corrections below are authoritative.

The current, ordered checklist we will execute together is
[`../testing/BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md`](../testing/BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md).
This older guide remains useful background and fault history; use the acceptance checklist for
test IDs, stop conditions, expected results, and retained evidence.

Run hardware steps on a real Apple Silicon Mac. During an assisted session Codex can prepare and
interpret commands and evidence; the human operator remains responsible for physical media,
administrator prompts, VPN controls, Windows preparation, and macOS permission dialogs.

---

## Gap 0 (closed): the GUI popover is now wired up

Was: `gui/App/NtfsmacApp.swift` rendered a placeholder `Text("ntfsmac")` — every Phase 3 feature
view (`DriveRow`, `SpeedBar`, `DirtyBanner`, `SecurityIndicatorsView`, `DiagnosePanel`,
`FirstRunView`, `PreferencesView`) existed but was unreachable from the running app, because no
unit in PLAN.md's §6 list ever assembled them.

Now: `gui/Views/PopoverContentView.swift` composes all of it, driven by `AppState`, and
`NtfsmacApp.swift` instantiates the real controllers (`DriveScanner`, `MountController`,
`RemountController`, `DiagnoseRunner`, `HelperInstaller`, `Settings`) and
wires them in; the current full Swift suite remains the authoritative regression gate. So:

- The popover now shows the first-run helper-install prompt until the XPC helper is installed,
  then the real multi-drive list, mount/unmount buttons, dirty-RO banner, three measured SECURITY
  indicators (fail-closed to `unknown` when the public transaction summary is unavailable),
  Diagnose panel, Refresh, and Quit.
- The gear button replaces the current popover content with the in-popover Settings page. `Back`
  returns to the previous app content; no separate Preferences `NSWindow` or private selector is
  used.

**Known, deliberately tracked limitations that remain:** the primary GUI mount button uses
`ntfs-3g` read/write by default; a compact menu offers NTFS3 for one explicitly warned
Experimental mount, but its hardware qualification is still open. Verified Copy is wired through
the verified read/write drive row's compact overflow menu and delegates to the same CLI/core
contract; its post-reconnect/Windows media qualification remains open. Per-drive Open in Finder,
default-off notifications, and Eject All are wired; unreliable global transfer telemetry was
removed rather than displaying a misleading concurrent-drive speed. SECURITY indicators consume
the live mount transaction's fixed PF/route state and reasons, but the remaining packaged
VPN/concurrent-device matrix is still a release gate.

---

## Gap 1: GATE-CLI-BEFORE-GUI — real Hypervisor.framework VM boot

**Why this is a sandbox gap:** `sysctl kern.hv_support` returns `0` inside the coding-agent's
Bash tool — Hypervisor.framework has no hardware virtualization available there, independent of
code signing/entitlements. Your real Terminal on an Apple Silicon Mac should report `1`.

```bash
sysctl kern.hv_support
# expect: kern.hv_support: 1 — if 0 on your real Mac too, stop and tell me, that's a new finding.
```

Fixed: confirmed `1` on the real Apple Silicon Mac — Gap 1 passes, no code change needed.

If that's `1`, skip straight to "End-to-end: connect a real NTFS drive" below — it folds this
gate's install+list check into the same walkthrough instead of a separate throwaway prefix.

---

## Gap 2: Liquid Glass visual parity vs. the built SwiftUI screens

No longer blocked by Gap 0. Do this after the end-to-end walkthrough below, once the app has
been through every state at least once:

- **Dark/light**: toggle System Settings → Appearance, reopen the popover each time, compare
  against the matching built dark/light screen — corner radius, blur/translucency,
  border, drop shadow, and (once a drive is mounted) the green/blue/yellow/red accent colors.
- **States to walk**: idle (no drives) → mounting (blue pulsing icon) → mounted r/w (green) →
  unmount → (if you can trigger a dirty journal — see below) mounted read-only (yellow, banner
  visible) → unplug the helper's launchd job or rename a vendor binary to force an error state
  (red) — real repro, not required, only if you want full color coverage.
- **Settings page**: open via the gear button, compare against the Settings screen, then use Back
  (light isn't separately specified — not a gap, only one appearance is defined for this screen).
- Known approximation, not a bug: the popover's drop shadow collapses the original two-layer
  box-shadow + inset rim-light into one `.shadow()` call (SwiftUI has no multi-shadow primitive)
  — documented in `gui/Style/GlassTheme.swift`'s doc comment, expect it to look *close*, not
  pixel-identical, at the shadow edge specifically.

---

## End-to-end: connect a real NTFS drive (CLI, then GUI)

Fixed: `cli/lib/nfs-mount.sh`'s `run_anylinuxfs_mount()` now auto-ejects the target partition
(`diskutil unmount /dev/diskNsM` — just the one volume, never `diskutil eject`, which would kick
the whole physical disk) before invoking `anylinuxfs mount`, so a normal macOS auto-mount no
longer blocks the raw-device probe. This is the GUI's mount path too — the privileged helper
(`helper/HelperProtocol.swift`'s `HelperService.mount()`) shells out to the same `ntfsmac mount`
CLI command, so one fix covers both surfaces. Regression tests:
`tests/cli/mount.bats` — "auto-ejects the partition from macOS before mounting" and "a diskutil
unmount failure ... doesn't block the real mount".

Do the CLI pass first — if the CLI can't mount, the GUI can't either (same helper scripts
underneath), and the CLI gives you plain stdout instead of having to read UI state.

### Prerequisites

- A real NTFS-formatted USB/external drive, or a spare partition you can format NTFS from
  Windows/another machine. (`diskutil` can't format NTFS on macOS — if you don't have one handy,
  ask and I'll walk through creating a small NTFS test image instead, that also exercises the
  mount path without needing physical hardware.)
- Plug it in before starting. `diskutil list` should show it; note its identifier, e.g. `disk4`,
  and the NTFS partition under it, e.g. `disk4s1`. No need to eject it yourself first —
  `ntfsmac mount`/the GUI's `[Mount]` button now does that automatically.
- **Run this from a bare Apple Silicon Mac Terminal, not from inside a Parallels (or any other) VM
  guest.** Hypervisor.framework nested virtualization is unreliable/unsupported in that
  configuration and will surface as VM-boot or device-probe failures below that look like
  ntfsmac bugs but aren't.

### Part A — CLI

```bash
cd <repo>
diskutil list                                   # find the real disk4sN for your NTFS partition

NTFSMAC_PREFIX=$(mktemp -d)
export NTFSMAC_PREFIX
./install.sh
$NTFSMAC_PREFIX/bin/anylinuxfs list             # should list your drive as ntfs, confirms the
                                                 # VM boots and can see the device (Gap 1's check,
                                                 # folded in here)
```

Fixed: `anylinuxfs list` can preserve the raw partition type when blkid does not return an NTFS
fstype. GPT partitions then appear as `Microsoft Basic Data`, while real MBR NTFS media appears
as `Windows_NTFS`. The GUI and CLI parsers already normalized the GPT prefix but treated the MBR
prefix as an unknown fstype and silently dropped the drive. Both parsers now normalize
`Windows_NTFS` to `ntfs` and preserve any following volume label. Regression fixtures mirror two
real external MBR disks: an unlabeled 248 GB `disk4s1` and labeled 8.1 GB `USB_8GB`/`disk5s1`.

Fixed — confirmed a real code bug, not a Parallels/nested-virtualization environment issue as
first suspected (ruled out: confirmed this exact run was on the bare Apple Silicon Mac Terminal).
`build/build-all.sh` and `build/init-rootfs.sh` each did their own bare `codesign -s -` with no
entitlements; `build/sign.sh` (which embeds `com.apple.security.hypervisor`,
`build/entitlements/anylinuxfs.entitlements`) existed but nothing in the pipeline ever called
it. `install.sh`'s `verify_signature()` only checks signature validity (`codesign -v`), not
which entitlements are present, so this passed silently — every real build shipped an
unentitled `anylinuxfs`/`init-rootfs` that can't call `Hypervisor.framework`, which surfaces as
exactly this `errno 22`. Both build scripts now call `build/sign.sh` after vendoring their
binary; verified against a real cargo build (`tests/build/build-all.bats`,
`tests/build/rootfs.bats` — new "carries the hypervisor entitlement" tests). Applies to CLI and
GUI identically — the GUI has no separate binary-staging path, it consumes the same
install.sh-populated prefix. Re-run `./install.sh` from a fresh build to pick up the fix.



```bash
$ NTFSMAC_PREFIX/bin/ntfsmac mount disk4s1       # replace with your real identifier
```

```
macOS: Error: Cannot probe /dev/disk4s4: LibErr(0); Insufficient permissions?
mount: failed to mount disk4s4
```

Fixed — real cause, confirmed against upstream's own docs
(`vendor/src/anylinuxfs/docs/important-notes.md` "Permissions"): `anylinuxfs mount` needs raw
`/dev/disk*` access, which macOS refuses without root (it drops back to the invoking user once
the disk is open — not a permanent privilege escalation). `ntfsmac mount` never told you this;
it just surfaced anylinuxfs's own cryptic FFI error. `cli/commands/mount.sh` now self-elevates
via `exec sudo "$0" "$@"` when not already root — you'll get a normal `sudo` password prompt
instead of this error. Transparent to the GUI (its privileged helper already runs as root, so
this check never fires there). Regression test: `tests/cli/mount.bats` — "self-elevates via
sudo when not root".



```bash
mount | grep nfs                                # confirm it's mounted, options include "soft"
ls /Volumes/<label>                             # replace <label> with the real volume name
touch /Volumes/<label>/ntfsmac-test.txt         # real write test
echo "hello" > /Volumes/<label>/ntfsmac-test.txt
cat /Volumes/<label>/ntfsmac-test.txt           # confirm it round-trips
rm /Volumes/<label>/ntfsmac-test.txt

$NTFSMAC_PREFIX/bin/ntfsmac diagnose --json | python3 -m json.tool
$NTFSMAC_PREFIX/bin/ntfsmac unmount disk4s1

mount | grep nfs                                # confirm it's gone
```

Fixed: `ntfsmac unmount help` used to fake success — `cli/commands/unmount.sh` handed any
non-device argument straight to `anylinuxfs unmount` as if it were an already-resolved mount
path. It now rejects anything that isn't a `diskNsM` device or a `/Volumes/...` path (mirrors
`helper/HelperProtocol.swift`'s `isValidUnmountTarget()`, which already enforced this correctly
on the GUI side). Regression test: `tests/cli/unmount.bats` — "rejects a garbage target instead
of faking success".

Fixed: direct CLI `unmount` now self-elevates before removing the backend, matching direct CLI
`mount`. Security session records are root-owned `0700/0600`; an unprivileged unmount could remove
NFS first and then mistake the unreadable record for `NO_SESSION_STATE`, leaving a stale session.
The GUI path is unchanged because its privileged helper already enters the same script as root.
Regression test: `tests/cli/unmount.bats` — "self-elevates before direct CLI unmount".

Fixed: the standalone no-argument `pf-teardown.sh` recovery now resolves the installed
`anylinuxfs` binary before asking for authoritative backend status. Previously it always returned
`STATUS_UNAVAILABLE` unless a caller happened to inject the path, safely retaining stale state but
making installed reconciliation ineffective. Regression test: `tests/cli/teardown.bats` —
"standalone reconciliation resolves anylinuxfs".

Expected: mount succeeds read-write (unless the drive genuinely has a dirty NTFS journal, in
which case it must fail closed with Windows recovery guidance — see "force a dirty-journal test" below if you want to
verify that path specifically), the write/read/remove round-trips, `diagnose --json` reports
`"healthy": true`, and unmount is clean.

### Verified Copy — disposable-data check

With the test volume mounted, keep the source and destination distinct and use a new destination
name; the command deliberately refuses overwrite:

```bash
verified_copy_fixture="$(mktemp -d)"
printf 'BinaryBears verified copy fixture\n' > "$verified_copy_fixture/source.txt"
/usr/local/ntfsmac/bin/ntfsmac copy --verify \
  "$verified_copy_fixture/source.txt" "/Volumes/<label>/ntfsmac-verified-copy-test.txt"
/usr/local/ntfsmac/bin/ntfsmac verify \
  "$verified_copy_fixture/source.txt" "/Volumes/<label>/ntfsmac-verified-copy-test.txt"
```

Expected: the copy reports that its SHA-256 manifest matched and publishes the final destination
only afterward. Change the destination bytes and confirm `verify` exits non-zero. For release
evidence, safely unmount, physically reconnect, and run `verify` again so the destination reread
crosses a real media cycle. A match validates bytes read at that time; permissions, ownership,
ACLs, extended attributes, resource forks, timestamps, hard links, sparse allocation, and future
media health are outside the contract. Remove only the named disposable fixture when finished.

The packaged GUI exposes the same operation under the verified read/write drive row's `…` menu.
Its source panel accepts one file/folder and its destination panel starts at that row's real mount;
an outside, existing, symlink-escaped, stale-volume, or read-only destination must be rejected.
During a large copy the compact card is the only added surface, mount lifecycle actions are
disabled, and Cancel must retain the source/failure partial without publishing the final name.

### P0 gate — mount truth and private NFS transport

Run this against the packaged candidate while the NTFS drive is mounted:

```bash
/usr/local/ntfsmac/bin/ntfsmac diagnose --json | python3 -m json.tool
./tests/live/verify-nfs-transport.sh
sudo ./tests/live/verify-security-transaction.sh
```

Diagnostic schema 6 must report `"network_helper": "vmnet"` and
`"nfs_transport_contract": "expected_vmnet"`. The live gate must pass; it independently rejects
gvproxy, a loopback port-2049 listener, an endpoint outside the anylinuxfs vmnet pool, a route that
does not use the private bridge, or an NFS mount without `soft`. Its output is privacy-safe and
contains only a mount count plus fixed contract tokens.

The security-transaction gate independently requires one protected state record per active
anylinuxfs session, the evaluated macOS `com.apple/*` anchor path, the exact per-session child
anchor, its PF enable reference, and a route that still resolves through the recorded bridge. It
also emits only a count and fixed tokens. Expected output while one drive is mounted:

```text
verify-security-transaction: PASS — 1 session(s), evaluated PF, private route, owned teardown state
```

Repeat both live gates with the VPN default route off and on. When a connected vmnet `/30` already
wins routing, `vpn_route=notRequired` is correct; when ntfsmac must add a host route, the session
must record `vpn_route=enforced` and remove only that host route on unmount. With two drives,
`sudo ./tests/live/verify-security-transaction.sh` must report two sessions; unmount one, rerun it,
and require one surviving session. After the final unmount, there must be no ntfsmac state file or
child anchor left. Do not disable the VPN or another network interface merely to force a case.

With the GUI kept open, also exercise the cross-surface matrix:

1. Mount in the GUI, unmount with the CLI, and confirm the green row disappears within five
   seconds without pressing Refresh.
2. Mount with the CLI and confirm the already-running GUI discovers that device and its real
   read-only/read-write state within five seconds.
3. Repeat both directions using Refresh, then perform a safe external unmount/hot-unplug and
   confirm the GUI never remains green when host evidence disappears.
4. With two test drives mounted, remove only one and confirm the surviving row stays verified.
5. If either evidence source is intentionally made unavailable, confirm the affected state is
   yellow/unknown with a reason code, never green.

Record packaged-app results separately from unit-test results. Do not mark the roadmap hardware
gate complete until VPN off/on, teardown, helper recovery, restart recovery, and concurrent mounts
have all passed on the release artifact.

### Recorded packaged P0 result — 2026-08-11

The packaged 2.1 (090826) candidate was installed on Apple Silicon macOS 26.6.1 and exercised with
one real NTFS USB device while a VPN owned the default route. Privacy-safe retained evidence:

- GUI mount completed read/write only after a newly measured private `/30` bridge, exact endpoint
  route, and per-session PF policy were active. This run originally exposed and then verified the
  fix for the pre-NFS VPN ordering deadlock.
- `verify-nfs-transport.sh` passed with one vmnet/private/soft mount and no loopback listener.
  Intended NFS and mountd ports were reachable through the private endpoint; unrelated tested
  bridge ports were blocked or closed.
- A 32 MiB random payload had identical source and destination sizes, SHA-256
  `29efb03c7cc5be106c13f321e212b997e445e37430ff4329fdcb1f9099434bc8`, and byte comparison.
  Only the generated test pair was deleted afterward; pre-existing USB content was untouched.
- App Unmount removed the NFS mount, anylinuxfs session, private VM/bridge, and owned exact route.
- Finder **Disconnect** on the synthetic NFS share and a later external NFS unmount were each
  detected by the open app; helper reconciliation completed the same VM/PF/route cleanup and the
  GUI returned to a detected, unmounted drive without retaining a green state.
- The maintainer ran the root-only security-transaction gate, but its stdout was not captured in
  the agent transcript. Do not substitute that report for a retained gate output in a release PR.
- Not tested in this session: VPN-off, CLI→GUI mount discovery, helper/crash restart, physical
  hardware eject or hot-unplug, and concurrent devices. Those roadmap cells remain open.

After replacing the helper/runtime binary during local development, macOS may require toggling
the helper's existing Full Disk Access entry off and on so TCC refreshes the changed executable.
The installer now uses fresh inodes plus atomic rename for signed runtime files; it does not alter
Full Disk Access, Gatekeeper, SIP, quarantine, or signing policy.

### App unmount, Finder disconnect, and hardware eject are different operations

- **App Unmount** is the canonical transaction. It asks the privileged helper to stop the
  anylinuxfs export/VM and NFS mount, then releases only that session's PF token and exact route;
  the GUI waits for observed host state before publishing unmounted success.
- Finder **Disconnect** on `diskNsN.local` removes the macOS NFS client mount outside the app.
  The open app detects the authoritative disappearance and asks the helper to finish backend,
  PF, and route cleanup. This recovery path passed live, but App Unmount is more deterministic
  because one owner drives the entire transaction from the start.
- Finder **Eject** on the physical USB disk is a Disk Arbitration whole-device action, not an NFS
  share disconnect. While ntfsmac is active, the physical NTFS partition has already been detached
  from macOS and the visible mounted volume is the network share. Unmount in ntfsmac first, wait
  until the GUI shows the drive as detected/unmounted, and only then eject the physical device.
  Soft NFS and reconciliation reduce failure impact; they are not evidence that physical eject or
  hot-unplug was tested in this session.

```
$ NTFSMAC_PREFIX/bin/ntfsmac diagnose
diagnose: ntfsmac version: 1.0 (1)
diagnose: macOS version: <version>
diagnose: architecture: arm64
diagnose: privileged helper: installed
diagnose: vendor binaries missing: 3
diagnose:   missing components: gvproxy vmnet-helper vmproxy
diagnose: quarantined binaries: 0
diagnose: kernel pin: unknown
diagnose: vmnet bridge: down
diagnose: VPN default route: not detected
diagnose: current NFS mount count: 0
diagnose: overall: degraded
```

Fixed: not a separate bug — downstream of the VM-boot/probe environment mismatch above (nothing
ever mounted, so nothing to report). Re-check after re-running Part A from the bare Apple Silicon
Mac.

If any step fails, capture the exact stdout/stderr and bring it back rather than re-running
blindly — this is genuinely the first time this path has run against real hardware outside the
sandbox.

```
$ NTFSMAC_PREFIX/bin/ntfsmac uninstall
security_teardown=notRequired reason=NO_SESSION_STATE
uninstall: removed <tmp-prefix>
uninstall: removed ~/.anylinuxfs (rootfs cache + config.toml)
uninstall: not running as root — the GUI's privileged helper (if installed) was left in place.
uninstall: re-run with 'sudo' to remove it too, or use the GUI's own Uninstall control in Preferences.
uninstall: done
$ NTFSMAC_PREFIX/bin/ntfsmac diagnose
zsh: no such file or directory: <tmp-prefix>/bin/ntfsmac
```

Fixed: not a bug — expected. `uninstall` removed the prefix, so `ntfsmac` (which lived under it)
is legitimately gone; `diagnose` erroring with "no such file" afterward is the correct outcome.



Fixed: verified — `helper/HelperProtocol.swift`'s `isValidUnmountTarget()` already enforced the
disk-regex/`/Volumes/` rule on the GUI/helper side independently of the CLI. The CLI wrapper was
the one that had drifted (see the `unmount help` fix above); both now agree.

### Part B — GUI

Do this only after Part A succeeds — it exercises the exact same underlying scripts, just
through the popover instead of `ntfsmac` directly, so a CLI failure will fail here too.

**Prerequisite:** full Xcode.app must be installed and selected — `sudo xcode-select -s
/Applications/Xcode.app/Contents/Developer`. SwiftUI's `@State`/`@Observable` macro plugin ships
inside Xcode.app, not standalone Command Line Tools; building with only CLT selected fails with
"external macro implementation type ... could not be found" (see the fixed build failure below).

Always test the packaged application, because the privileged helper cannot be installed from a
raw SwiftPM executable:

```bash
cd <repo>
./build.command gui
open dist/ntfsmac.app
```

Fixed: root cause identified for the build failure below — the failing build was running against
the standalone Command Line Tools, with no Xcode.app toolchain in play. The `@State` macro
plugin ships inside Xcode.app, not CLT, so `@State` failed to expand:

```
error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
```

Confirms the CLT-only diagnosis. Not an ntfsmac code bug; select full Xcode per the prerequisite
above and re-run.

1. Click the menu-bar icon, then close it and run `ntfsmac opengui`; both actions must reveal the
   same popover without Accessibility permission or a simulated click. If the privileged helper
   isn't installed yet, the app must first explain why it is needed and that macOS will request
   an administrator password. A real `SMJobBless` prompt may appear only after the explicit
   **Install Helper…** action. The packaged app then stages its
   bundled CLI/runtime through the helper; no separate Homebrew or manual CLI install is required
   for this GUI pass.
2. Popover should show your drive in the list (the same filtered `anylinuxfs list` data Part A's
   `list` command showed, including MBR `Windows_NTFS`). Click `[Mount]` and confirm the default
   is still `ntfs-3g`. In a separate disposable-data run, open the adjacent compact menu, select
   `NTFS3 (Experimental)…`, verify the Windows shutdown/Fast Startup/`chkdsk` preflight, and
   confirm diagnostics record `ntfs3` with no silent fallback.
   Before Mount becomes available, the setup gate performs a non-mutating one-block raw-device
   access check. If Full Disk Access is required, macOS lists the component as
   `com.khr898.ntfsmac.helper`; this is the technical service name of **ntfsmac Helper**, not an
   unrelated package. Enable that exact entry and return to ntfsmac; the gate must recheck and
   reveal the normal popover automatically, so the first Mount is not lost to authorization.
3. Icon should pulse blue while mounting, then turn green with the drive shown as mounted, a
   per-drive Unmount action, and measured **Private VM link**, **VPN-safe route**, and **PF policy
   enforced** rows. Their state/reason codes must match CLI diagnostics; unavailable or malformed
   evidence must stay unknown/non-green. Confirm `Open` reveals this exact drive's observed mount
   point in Finder. No speed row should appear.
4. Click `Diagnose` in the footer — the panel should match Part A's `diagnose --json` output in
   plain language. Hide and reopen it to confirm a fresh run still works.
5. Hold Command (⌘) and click `Diagnose`. The same diagnostic summary should run, followed by a
   native save panel proposing `ntfsmac-diagnose-<timestamp>.json`. Save it to a temporary
   location, confirm it is valid privacy-safe JSON, then remove only that test export. Canceling
   the save panel must create no file and no network upload should occur.
6. Click `Unmount` — icon returns to its system-adaptive idle state and the drive drops off the
   mounted row.
7. Click the gear icon — Settings replaces the popover content. Confirm the current app
   release/build appears directly below `Settings`. Confirm Notifications defaults off; permission
   is requested only when explicitly enabled. Exercise Launch at login if appropriate, use Back,
   and reopen Settings.
8. As the final cleanup check, click `Uninstall…` in Settings. Confirm the destructive prompt stays
   inside the popover; cancel once, reopen it, then confirm. A freshly installed helper must uninstall
   on the first confirmed attempt, the UI must reach `Uninstalled`, and the uninstall action must
   remain disabled afterward.
9. Click `Quit` — app should exit; `mount | grep nfs` back in Terminal should show nothing
   ntfsmac-related left mounted.

### Force a dirty-journal refusal test, optional and disposable-media only

Use only a sacrificial NTFS device and the controlled Windows dirty-bit procedure from the
BinaryBears acceptance runbook; do not pull a device during writes or force-shutdown a machine to
manufacture this state. On macOS, both default `ntfs-3g` and explicit NTFS3 must refuse a writable
mount, show concise Windows `chkdsk`/Fast Startup/full-shutdown guidance, publish no green row, and
leave no VM/PF/security-session residue. Repair it with Windows `chkdsk`, fully shut down Windows,
then repeat the normal clean mount. This is optional and drive-specific; Part A/B remain primary.

---

## What's fully testable today, no drive, no new code

```bash
cd <repo>
swift test
```

If you hit `error: input file '...runner.swift' was modified during the build` — real,
already-documented SPM/network-share fsync race (when the repo lives on a path-with-spaces
network volume, same class of quirk `build/AUDIT.md` documents for `v-alpine-rootfs`). Work
around it with a local build cache:

```bash
swift test --build-path /tmp/ntfsmac-build
```

Require the complete Swift test run to pass. The exact case count is printed by Swift Testing and
changes when focused regression coverage is added; do not use a stale hard-coded count as a gate.

```bash
tests/run-all.sh   # full bats suite: lock/preflight/submodule/audit/fetch-prebuilt/gvproxy/
                    # rootfs/build-all/verify-vendor/pf-rules/route-guard/teardown/
                    # security-status/validate-device/mount/fs-driver/mount-diagnostics/unmount/
                    # verified-copy/opengui/diagnose/install/signing/formula
```

---

## Uninstall — CLI and GUI, verify no leftovers

Do this *after* the end-to-end walkthrough above, once you've confirmed mount/unmount work —
you want something real to uninstall, not an empty install.

### CLI

Fixed: `ntfsmac uninstall` now self-elevates via `sudo` automatically (same pattern as
`mount`'s self-elevation) — one command, one password prompt, and it's fully done, including
the GUI's privileged helper. It used to leave the helper in place and tell you to re-run with
`sudo` yourself; `resolve_invoker_home()` (`cli/commands/uninstall.sh`) makes sure `~/.anylinuxfs`
and `~/Library/Logs` still resolve to *your* home once elevated, not root's. Regression tests:
`tests/cli/uninstall.bats` — "self-elevates via sudo" and "resolve_invoker_home ... not root's
own HOME".

```bash
NTFSMAC_PREFIX=/usr/local/ntfsmac   # or wherever you installed to
export NTFSMAC_PREFIX
ntfsmac uninstall                   # unmounts nothing itself — refuses if a drive is still
                                     # mounted; run `ntfsmac unmount <device>` first. Prompts
                                     # for your password once, removes everything including
                                     # the GUI's privileged helper.
ls "$NTFSMAC_PREFIX"                # expect: No such file or directory
ls ~/.anylinuxfs                    # expect: No such file or directory (rootfs cache + config)
ls ~/Library/Logs/anylinuxfs*.log 2>&1   # expect: No such file or directory
sudo launchctl print system/com.khr898.ntfsmac.helper   # expect: Could not find service
ls /Library/LaunchDaemons/com.khr898.ntfsmac.helper.plist        # expect: No such file
ls /Library/PrivilegedHelperTools/com.khr898.ntfsmac.helper      # expect: No such file
```

`ntfsmac help` lists every command, including `uninstall` — run it if anything above is
unfamiliar.

### GUI

Preferences → "Uninstall ntfsmac" → confirm the dialog. This routes through the *already*
privileged helper (no new auth prompt — it's already running with the trust the first-run
install granted it) to remove `$installPrefix` + your real `~/.anylinuxfs`/logs, then un-bless
itself (`launchctl bootout` + delete its own launchd plist/binary). Verify the same way as the
CLI `sudo` path above (`launchctl print`, `ls` on both `/Library` paths). Once that's done,
dragging `ntfsmac.app` to the Trash should leave nothing else on disk — check `~/Library/
Preferences/com.khr898.ntfsmac.settings.plist` too if you want to confirm even the stored
Preferences are gone (the uninstall flow doesn't currently clear `UserDefaults` — a real,
minor, non-blocking gap: run `defaults delete com.khr898.ntfsmac` manually if you want that too).

**Real safety property to spot-check:** if you have a drive mounted, "Uninstall ntfsmac" should
refuse (same active-mount check the CLI makes) rather than silently ripping the helper out from
under a live mount.

---

## Swift conventions

Project-wide Swift conventions for the GUI (`gui/`) and helper (`helper/`):

- **Test framework:** Swift Testing (`import Testing`) with `@Test` and `#expect` — see
  `gui/Tests/`. Each test owns its state via `init`/`deinit`; no shared mutable state between
  tests. Use parameterized `@Test(arguments:)` to cover input variants in one test.
- **Immutability:** prefer `let` over `var`; default to `struct` with value semantics, reach
  for `class` only when identity/reference semantics are required.
- **Concurrency:** Swift 6 strict concurrency. Prefer `Sendable` value types across isolation
  boundaries, actors for shared mutable state, structured concurrency (`async let`, `TaskGroup`)
  over unstructured `Task {}`.
- **Logging:** no `print()` in production paths — use `os.Logger`.
- **Secrets:** Keychain Services for anything sensitive (tokens/passwords/keys), never
  `UserDefaults`. Build-time secrets via environment variables or `.xcconfig`. Never hardcode
  secrets in source.
- **Transport:** keep App Transport Security enabled; validate server certificates.
- **Build caveat:** SPM on a path-with-spaces volume can hit the `runner.swift modified during
  the build` race — build off-volume with `--build-path /tmp/ntfsmac-build` (see
  `build/AUDIT.md`).

---

## Priority order

Use the ordered acceptance checklist linked at the top. Its safe single-drive tests come first;
concurrent-drive, Windows-state, low-space, interruption, and hot-unplug fault tests run only after
the baseline has passed and only on disposable media.
