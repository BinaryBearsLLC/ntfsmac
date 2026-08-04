# ntfsmac GUI — Feature & Button Plan

> Custom SwiftUI menu-bar app (no Dock icon). Wraps the CLI + pf security layer via an XPC helper.
> Companion to `PLAN.md` Phase 3 — that covers engineering scaffolding; this covers what the user sees and taps.

## Design principles

- **One job, zero clutter.** Pick a drive, mount it, get out of the way.
- **Status at a glance.** Menu-bar icon colour tells the whole story without opening the popover.
- **Never lie about safety.** If a drive mounts read-only (dirty journal), say so loudly before the user trusts a write.

---

## App shape

Menu-bar agent → click icon → popover. Settings is a page inside that same popover; the only
separate system UI is the first-run helper authorization prompt.

### Menu-bar icon states

| Colour | Meaning |
|--------|---------|
| System-adaptive | Idle, nothing mounted |
| Blue (pulsing) | Mounting |
| Green | Mounted read/write |
| Yellow | Mounted **read-only** (dirty journal) |
| Red | Error |

The idle SF Symbol is an AppKit template image, so macOS supplies the same contrasting tint used
by native menu-bar apps. This keeps the icon visible across light and dark menu-bar backgrounds
without adding a preference or first-run animation. Saturated colours remain reserved for real
mounting, mounted, warning, and error states.

---

## Features

**v1 (MVP — ship with the GUI):**
1. Auto-detect compatible drives (polls `anylinuxfs list`).
2. One-click mount / unmount.
3. Live mount status + transfer speed.
4. Dirty-drive read-only detection + warning.
5. Security indicators (isolated network ✓, VPN-bypass ✓).
6. Open mounted volume in Finder.
7. Diagnose (runs the CLI diagnostic, shows result).
8. First-run helper install (one auth prompt, via SMJobBless).

**v2 (later):**
- Launch at login toggle.
- Per-drive default mount options (ro/rw, mount point).
- Multi-drive mounts (gated on upstream vmnet-helper / concurrent-mount support).
- Notifications on mount/unmount/error.
- Eject-all.

---

## Button & control plan

### Popover — idle (no mount)

| Control | Action | Enabled when |
|---------|--------|--------------|
| Drive row `[Mount]` | Mount that drive r/w via XPC helper | A compatible drive is detected |
| Refresh (↻) | Re-scan drives now | Always |
| `Diagnose` | Run CLI diagnostic, show summary | Always |
| `⌘`-click `Diagnose` | Run the same read-only diagnostic and save its JSON for developer support | Always |
| ⚙ (gear) | Navigate to Settings in the popover | Always |
| `Quit` | Exit app, tear down network state | Always |

### Popover — mounted

| Control | Action | Enabled when |
|---------|--------|--------------|
| `Open in Finder` | Reveal mount point | Mounted |
| `Unmount` | Safe unmount + pf/route teardown | Mounted |
| Speed bar | Live throughput (read-only display) | Mounting / mounted |
| ⚙ / `Quit` | As above | Always |

### Read-only (dirty) state — extra

| Control | Action |
|---------|--------|
| Warning banner | "Mounted read-only — drive has an unclean journal. Eject safely in Windows to enable writing." (non-dismissable while RO) |
| `Mount read/write anyway` | Re-mount r/w **only after** an explicit confirm dialog spelling out corruption risk |

### Error state

| Control | Action |
|---------|--------|
| Error message | Plain-language cause (helper not installed, binary missing, mount failed) |
| `Retry` | Re-attempt last action |
| `Diagnose` | Jump to diagnostics |
| `⌘`-click `Diagnose` | Save the same read-only diagnostic JSON for developer support |

### Diagnostic summary

Diagnostic rows distinguish confirmed health, expected or transitional information, actionable
warnings, and unavailable context. A stopped vmnet bridge is informational while ntfsmac is idle
or starting a mount; it becomes a warning only when a drive is already mounted and the private NFS
network is expected to be active. Unknown or malformed values are shown neutrally rather than as
confirmed failures. Short explanations remain available through native help and accessibility
text without widening the popover.

### Diagnostic panel

The diagnostic box includes a compact `Hide` action in its header. Hiding changes only panel
visibility: it does not clear the last result, cancel an in-progress run, or touch mount/helper
state. Selecting `Diagnose` again always reopens the box and starts one fresh diagnostic run.
`Hide` remains keyboard-reachable and available for result, error, and running states.

### Contextual help

Controls and statuses whose purpose is not immediately obvious expose concise native macOS help
on hover. Tooltip copy does not replace accessibility labels or hints, does not duplicate long
paragraphs across views, and must not change layout, focus order, or the macOS 13.0 target.

### Settings page

The gear replaces the main popover content with Settings. A keyboard-reachable `Back` action
returns to the previous application content. Normal, first-run, and CLI-repair screens all use the
same route and the same long-lived Settings/helper objects; navigation does not open an `NSWindow`
or recreate in-flight state. The title includes the app release/build directly underneath in
small secondary text; it is informative and never competes visually with the `Settings` heading.

| Control | Type | Default |
|---------|------|---------|
| Launch at login | Toggle | Off |
| Default mount mode | Segmented: Read-only / Read-write | Read-write |
| Default mount point | Path picker | `/Volumes/<label>` |
| Show speed in menu bar | Toggle | Off |
| Reinstall privileged helper | Button | — |
| Uninstall ntfsmac | Destructive button with in-popover confirmation and progress | — |

Uninstall confirmation stays inside the transient menu-bar popover. Cancel returns to Settings;
confirming consumes that confirmation once, disables duplicate starts, and keeps the current
removal phase or final error visible until completion.

The diagnostic panel renders the same privacy-safe schema exported by Command-click Diagnose:
release/build, macOS and architecture, helper presence, fixed runtime component failures,
kernel/bridge state, a yes/no VPN tunnel signal, and the active NFS mount count. It never displays
or exports usernames, serials, volume/device identity, local paths, VPN identity, addresses, DNS,
or routes.

---

## Control → privilege boundary (non-negotiable)

Every control that mounts, unmounts, or touches pf/route goes through the **SMJobBless XPC helper** — never a raw `sudo` shell-out from the UI. Device names are validated against `^disk[0-9]+s[0-9]+$` in *both* the UI and the helper before any shell call. (Mirrors `PLAN.md` §4.2.)
