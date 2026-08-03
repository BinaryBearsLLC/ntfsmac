# ntfsmac — manual test guide

Run this from your own Terminal, on a real Apple Silicon Mac, outside the coding-agent sandbox.
Every item below either can't be verified from inside that sandbox, or (until this update)
couldn't be exercised because the GUI pieces were built unit-by-unit and never wired together.

---

## Gap 0 (closed): the GUI popover is now wired up

Was: `gui/App/NtfsmacApp.swift` rendered a placeholder `Text("ntfsmac")` — every Phase 3 feature
view (`DriveRow`, `SpeedBar`, `DirtyBanner`, `SecurityIndicatorsView`, `DiagnosePanel`,
`FirstRunView`, `PreferencesView`) existed but was unreachable from the running app, because no
unit in PLAN.md's §6 list ever assembled them.

Now: `gui/Views/PopoverContentView.swift` composes all of it, driven by `AppState`, and
`NtfsmacApp.swift` instantiates the real controllers (`DriveScanner`, `MountController`,
`ThroughputMonitor`, `RemountController`, `DiagnoseRunner`, `HelperInstaller`, `Settings`) and
wires them in — reviewed (`ecc:swift-reviewer`, approve), 77/77 tests still green. So:

- The popover now shows the first-run helper-install prompt until the XPC helper is installed,
  then the real drive list, mount/unmount buttons, speed bar, dirty-RO banner, security
  indicators (currently `.unknown`/`.unknown` — Phase 1 pf/route hardening state isn't surfaced
  by `diagnose.sh` yet, a separate, already-documented gap, not new here), Open in Finder,
  Diagnose panel, Refresh, and Quit (which tears down pf/route state via the helper first).
- A `Settings { PreferencesView(...) }` scene is now registered — the gear button in the popover
  footer opens it via `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)` (the standard
  macOS-13-compatible way to open a `Settings` scene; `@Environment(\.openSettings)` needs
  macOS 14+, which this project's floor doesn't allow).

**Known, deliberately out-of-scope limitations that remain** (don't report these as new bugs):
`Settings.defaultMountMode`/`defaultMountPoint` are stored but not yet threaded into the actual
mount call (`MountController.mount()` has no parameter for either yet — v1 has no
auto-mount-on-detect, only the manual `[Mount]` button, which always mounts read-write via
`ntfs-3g`). Security indicators show `.unknown` until a later unit surfaces Phase 1 state through
`diagnose.sh`.

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
- **Preferences window**: open via the gear button, compare against the Preferences screen
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

Verified, no fix needed: `anylinuxfs list --microsoft` (what the GUI's `DriveScanner` also calls)
already lists every "Windows Basic Data" partition — `diskutil` names GPT Windows partitions
`Microsoft Basic Data` and legacy MBR ones `Windows_NTFS`/`Windows_FAT_32`; vendor's own
`WINDOWS_PART_TYPES` filter (`vendor/src/anylinuxfs/anylinuxfs/src/diskutil/mod.rs:288-293`)
already matches all three, restricted to `ntfs`/`exfat`/`BitLocker` filesystems
(`WINDOWS_FS_TYPES`). Nothing to change here.

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

Expected: mount succeeds read-write (unless the drive genuinely has a dirty NTFS journal, in
which case it should land read-only — see "force a dirty-journal test" below if you want to
verify that path specifically), the write/read/remove round-trips, `diagnose --json` reports
`"healthy": true`, and unmount is clean.

```
$ NTFSMAC_PREFIX/bin/ntfsmac diagnose
diagnose: vendor binaries missing: 3
diagnose: quarantined binaries: 0
diagnose: kernel pin: unknown
diagnose: vmnet bridge: down
diagnose: current NFS mounts:
  (none)
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
pf-teardown: done
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

```bash
cd <repo>
swift build
swift run ntfsmac-gui
```

Fixed: root cause identified for the build failure below — the failing build was running against
the standalone Command Line Tools, with no Xcode.app toolchain in play. The `@State` macro
plugin ships inside Xcode.app, not CLT, so `@State` failed to expand:

```
error: external macro implementation type 'SwiftUIMacros.StateMacro' could not be found for macro 'State()'; plugin for module 'SwiftUIMacros' not found
```

Confirms the CLT-only diagnosis. Not an ntfsmac code bug; select full Xcode per the prerequisite
above and re-run.

(No `.app` bundle exists yet — packaging is separate, unbuilt work. Expect a Dock icon too,
since `LSUIElement` only takes effect inside a real `.app` bundle — not a bug, just unpackaged.
The menu-bar icon itself uses a placeholder SF Symbol for now — see "app icon" note below.)

1. Click the menu-bar icon. If the privileged helper isn't installed yet, you'll get a real
   `SMJobBless` auth prompt (admin password) — approve it. This installs to the fixed
   `/usr/local/ntfsmac` prefix (not the `$NTFSMAC_PREFIX` temp dir from Part A — the GUI's helper
   always uses the real install path, per `3-xpc-helper`'s design). If Part A's `./install.sh`
   only installed to a temp prefix, the GUI's helper won't find binaries there; either also run
   `NTFSMAC_PREFIX=/usr/local/ntfsmac ./install.sh` (real `sudo`-writable location, may need
   `sudo` for `/usr/local`) once, or tell me and I'll check what `HelperClient`/`HelperService`
   actually expect before you do anything destructive to `/usr/local`.
2. Popover should show your drive in the list (same `anylinuxfs list --microsoft` data Part A's
   `list` command showed). Click `[Mount]`.
3. Icon should pulse blue while mounting, then turn green with the drive shown as mounted, a
   live (if idle) speed bar, and security indicators.
4. Click `Open in Finder` — a real Finder window should reveal the mount point.
5. Click `Diagnose` in the footer, then the `Diagnose` button inside the panel that appears —
   should match Part A's `diagnose --json` output in plain language.
6. Click `Unmount` — icon returns to grey/idle, drive drops off the mounted row.
7. Click the gear icon — Preferences window opens (compare against Gap 2's screen). Toggle
   settings, close, reopen — confirm they persisted (backed by `UserDefaults`, should survive
   without even restarting the app).
8. Click `Quit` — app should exit; `mount | grep nfs` back in Terminal should show nothing
   ntfsmac-related left mounted.

### Force a dirty-journal (read-only) test, optional

If you want to specifically verify the yellow/read-only-with-banner path: mount the NTFS drive
in Windows (or via Boot Camp/a VM), don't cleanly eject it (pull it, or force-shutdown Windows
while it's mounted), then bring it back to macOS and mount via `ntfsmac`/the GUI — ntfs-3g's
dirty-journal check should kick in and mount read-only. This is optional and drive-specific,
skip if inconvenient — Part A/B above are the primary coverage.

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

Expect `Test run with 77 tests in 0 suites passed`.

```bash
tests/run-all.sh   # full bats suite: lock/preflight/submodule/audit/fetch-prebuilt/gvproxy/
                    # rootfs/build-all/verify-vendor/pf-rules/route-guard/teardown/
                    # validate-device/mount/fs-driver/unmount/diagnose/install/signing/formula
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

1. **Part A (CLI end-to-end)** — highest value, this is the very first real hardware test of
   the whole build.
2. **Part B (GUI end-to-end)** — same underlying path, confirms the wiring works for real.
3. **Gap 2 (visual parity)** — do this while you're already walking states in Part B.
4. **Uninstall (CLI + GUI)** — confirm no leftovers, both paths.
5. Optional dirty-journal repro, if you want full state coverage