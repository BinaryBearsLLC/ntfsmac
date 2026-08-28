# ntfsmac GUI contract

This document describes the current SwiftUI menu-bar app. Historical design and implementation
detail lives in Git history and dated evidence files.

## Product shape

- Visible name: **ntfsmac**.
- Apple Silicon, macOS 13+, `MenuBarExtra`/popover, no Dock icon or main window.
- Standard builds use `SMAppService`; the labelled Legacy build uses `SMJobBless`.
- App-initiated privileged operations go through the reviewed XPC helper. The UI never invokes
  `sudo` or mutates PF/routes directly.
- Settings stays inside the popover. macOS authorization and Full Disk Access are the only external
  setup screens.

## Status states

| State | Menu-bar presentation | Meaning |
| --- | --- | --- |
| Idle | System-adaptive | Nothing mounted |
| Mounting | Pulsing blue | A mount is in progress |
| Mounted read/write | Green | Host and guest both confirm read/write |
| Mounted read-only | Green | Read-only was requested and confirmed |
| Warning/unknown | Yellow | State is incomplete, inconsistent, dirty, or unavailable |
| Error | Red | An operation failed and needs attention |

Colour is always paired with text or an accessible label. Missing evidence never becomes green.

## Setup and discovery

The first-run order is helper approval, CLI staging, drive discovery, and Full Disk Access
verification against a real partition. The first disk check initializes the pinned runtime once,
with a visible **Preparing ntfsmac…** state. With no supported drive, the normal idle UI then
reports **No drives found**; absence of media is not incomplete setup. When a partition appears,
the app probes Full Disk Access for that launch before enabling Mount.

Automatic drive and mount polling remains stopped until the current helper has accepted the
bundled CLI tree and its executables have been verified. An older installed CLI is never used
during helper replacement.

If discovery fails, a dedicated **Drive runtime** state shows **Unable to check connected drives**
with **Try Again**. It never uses the Full Disk Access header. Raw output remains in the developer
diagnostic only because it can contain personal paths. Settings and Quit stay reachable.

## Idle controls

| Control | Behavior |
| --- | --- |
| Drive row / Mount | Mount with `ntfs-3g` through the helper |
| Drive menu / NTFS3 | Show the Experimental warning and preflight, then opt in once |
| Refresh | Rescan drives and reconcile observed mounts |
| Diagnose | Run a fresh privacy-safe diagnostic summary |
| Command-click Diagnose | Export the developer JSON report |
| Settings | Navigate to the in-popover Settings page |
| Quit | Exit immediately when no storage operation is active |

## Mounted controls

Each verified mount gets its own row and observed mount point.

| Control | Behavior |
| --- | --- |
| Open | Open that verified mount in Finder |
| Unmount | Safely unmount only that drive |
| Verified Copy | Copy to that writable volume, flush, reread, and compare SHA-256 |
| Eject All | Attempt every mounted drive and retain recovery controls for failures |
| Other drive / Mount | Mount another compatible partition independently |

Mount/unmount/copy work disables conflicting actions. One failed drive must not hide or invalidate a
healthy sibling.

## Diagnose

The normal UI summarizes the same CLI evidence into four categories:

- App readiness
- Drive status
- Connection protection
- Permissions

Each category has a semantic status, short explanation, and a next action only when useful.
With no drive, Permissions reports **Checked when needed** instead of inventing an authorization
problem.
Technical identifiers, paths, IP details, runtime pins, PF/routes, and raw keys remain outside the
normal UI. **Hide** changes presentation only; running Diagnose again produces a fresh result.

## Settings

Settings contains:

- release/build and manual update check;
- Launch at login;
- notification opt-in;
- helper repair/reinstall;
- complete uninstall with in-popover confirmation.

Back and the update action use balanced header geometry. Pointer interaction must not leave a stale
keyboard-focus halo; deliberate keyboard traversal remains visible and accessible.

## Quit policy

- No mounted drive: quit immediately.
- Mounted drive: offer **Unmount and Quit**, **Quit Anyway**, and **Cancel**.
- Only **Unmount and Quit** may be remembered.
- Command-click Quit clears the remembered safe action and restores confirmation when mounted.
- Quit is disabled during mount, unmount, or Verified Copy.

## Truth and safety rules

- Accept only partition identifiers matching `diskNsN`.
- Default to `ntfs-3g`; NTFS3 remains explicit and experimental.
- Refuse unsafe writable NTFS when Windows Fast Startup, hibernation, or dirty state is indicated.
- NFS remains `soft` to avoid an indefinitely blocked macOS filesystem call after hot-unplug.
- Publish read/write only when physical inventory, guest state, and host NFS state agree.
- Discover CLI-created mounts and converge after CLI/Finder/external unmounts.
- Keep per-session PF/route state independent and fail closed when reconciliation is unavailable.
- Diagnostics and exports omit user, disk, volume, mount-path, and network identity.

## Validation

Automated and packaged checks live in [TESTING.md](TESTING.md). Full evidence is retained in the
dated files under `docs/testing/` and `docs/audits/`; this contract intentionally avoids duplicating
those reports.
