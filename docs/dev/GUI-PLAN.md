# ntfsmac GUI — Feature & Button Plan

> Custom SwiftUI menu-bar app (no Dock icon). Wraps the CLI + pf security layer via an XPC helper.
> Companion to `PLAN.md` Phase 3 — that covers engineering scaffolding; this covers what the user sees and taps.
> Current BinaryBears priorities and incomplete integrations live in
> [`../BINARYBEARS_ROADMAP.md`](../BINARYBEARS_ROADMAP.md).

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

## Feature status

This table describes the current integrated GUI, not the original aspirational phase list.

| Status | Capability |
| --- | --- |
| Shipped | Auto-detect NTFS, MBR `Windows_NTFS`, ext2, ext3, and ext4 partitions |
| Shipped | One-click mount/unmount and multiple concurrent drive rows |
| Shipped | Dirty-volume read-only detection, warning, and confirmed read/write retry |
| Shipped | Diagnose summary, inline Hide, and Command-click privacy-safe JSON export |
| Shipped | First-run helper/CLI staging, helper reinstall, and confirmed complete uninstall |
| Shipped | In-popover Settings with Back, canonical version/build, Launch at login, contextual help, and adaptive menu-bar icon |
| Partial | Three SECURITY rows render honestly as `unknown` and provide Hide/Show; live PF/route evidence is not wired yet |
| Partial | `FinderOpener` is implemented and tested, but no current multi-drive row exposes Open in Finder |
| Partial | `ThroughputMonitor` and `SpeedBar` exist, but transfer speed is not presented by the current multi-drive UI |
| Partial | NTFS3 is supported by CLI/helper internals, but has no GUI choice or completed hardware qualification |
| Planned | Verified Copy, evidence-backed SECURITY state, notifications, and Eject All |

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
| Per-drive `Unmount` | Safely unmount that drive | That drive is mounted |
| Other-device `Mount` | Mount another compatible partition | Another compatible drive is detected |
| Refresh (↻) | Re-scan while preserving mounted rows | Always |
| SECURITY rows | Display current state; currently `unknown` because live evidence is not wired | One or more drives mounted |
| SECURITY `Hide` / `Show` | Collapse or restore only the SECURITY presentation | One or more drives mounted |
| ⚙ / `Quit` | As above | Always |

`Open in Finder` and transfer speed are intentionally recorded as partial rather than shipped:
their implementation foundations remain in the tree, but the current popover does not expose
those controls. Wiring or removing them is a focused roadmap decision, not documentation fiction.

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

The mounted SECURITY section follows the same presentation-only rule. `Hide` collapses its three
rows to a compact `SECURITY · Show` header; `Show` restores the unchanged statuses. Neither action
mounts, unmounts, reconnects the helper, or changes any measured security state.

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
| Reinstall privileged helper | Button | — |
| Uninstall ntfsmac | Destructive button with in-popover confirmation and progress | — |

The app version and build number appear below the Settings title. Default mount mode, custom mount
point, and menu-bar speed are not current Settings controls; older planning text that listed them
as available was superseded by the implemented, smaller Settings surface.

The destructive uninstall confirmation is rendered inside the Settings page so selecting it does
not dismiss the transient menu-bar popover before the operation starts. Cancel consumes no action;
confirm can start the flow only once, and the control remains disabled while removal is active or
after it completes. The helper XPC connection is created lazily on the first privileged request,
not merely because the app launched.

The diagnostic panel renders the same privacy-safe schema exported by Command-click Diagnose:
release/build, macOS and architecture, helper presence, fixed runtime component failures,
expected and detected host-runtime versions, audited source commits, the approved Alpine
tag/digest, selected cache state, installed Alpine and guest-package versions, kernel/bridge
state, a yes/no VPN tunnel signal, and the active NFS mount count. It never displays
or exports usernames, serials, volume/device identity, local paths, VPN identity, addresses, DNS,
or routes.

### Planned controls

- **Experimental NTFS3 driver choice** — one-mount opt-in with explicit compatibility warnings,
  shipped only after the roadmap hardware gate passes.
- **Verified Copy** — app-managed, SHA-256-verified copy after the CLI/core contract is stable.
- **Open in Finder** — per mounted drive, using the existing tested opener.
- **Notifications and Eject All** — focused follow-up work with per-drive results.

---

## Control → privilege boundary (non-negotiable)

Every control that mounts, unmounts, or touches pf/route goes through the **SMJobBless XPC helper** — never a raw `sudo` shell-out from the UI. Device names are validated against `^disk[0-9]+s[0-9]+$` in *both* the UI and the helper before any shell call. (Mirrors `PLAN.md` §4.2.)
