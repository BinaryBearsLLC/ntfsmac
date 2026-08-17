# ntfsmac GUI — Feature & Button Plan

> Custom SwiftUI menu-bar app (no Dock icon). Wraps the CLI + pf security layer via an XPC helper.
> Companion to `PLAN.md` Phase 3 — that covers engineering scaffolding; this covers what the user sees and taps.
> Current BinaryBears priorities and incomplete integrations live in
> [`../BINARYBEARS_ROADMAP.md`](../BINARYBEARS_ROADMAP.md).

## Design principles

- **One job, zero clutter.** Pick a drive, mount it, get out of the way.
- **Status at a glance.** Menu-bar icon colour tells the whole story without opening the popover.
- **Never lie about safety.** Refuse unsafe dirty/hibernated writable mounts and explain the
  Windows recovery path before the user can trust a green state.

---

## App shape

Menu-bar agent → click icon or run `ntfsmac opengui` → popover. Settings is a page inside that
same popover; the only separate system UI is the first-run helper authorization prompt. The CLI
uses a registered URL event handled by the app's thin AppKit status-item shell, with no simulated
mouse click or Accessibility permission.

### Menu-bar icon states

| Colour | Meaning |
|--------|---------|
| System-adaptive | Idle, nothing mounted |
| Blue (pulsing) | Mounting |
| Green | Mounted read/write |
| Yellow | State unknown, backend unresponsive, or externally observed read-only mount |
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
| Shipped — extended matrix incomplete | Dirty NTFS fails closed with no read/write override and concise Windows recovery guidance; Fast Startup and a genuinely hibernated removable-volume fixture remain resource-gated |
| Shipped | Diagnose summary, inline Hide, and Command-click privacy-safe JSON export |
| Shipped | Consent-first helper install, progress-backed CLI staging, pre-mount Full Disk Access verification, helper reinstall, and confirmed complete uninstall |
| Shipped | In-popover Settings with Back, canonical version/build, Launch at login, contextual help, and adaptive menu-bar icon |
| Shipped — matrix incomplete | Three compact SECURITY rows consume the live transaction's fixed states/reasons and provide Hide/Show. Missing, malformed, or unavailable evidence fails closed to `unknown`; the remaining packaged hardware matrix is tracked in the roadmap. |
| Shipped | Each verified mounted-drive row exposes Open in Finder and uses that row's observed mount point |
| Resolved | Global transfer telemetry was removed because bridge-wide counters cannot truthfully attribute concurrent traffic per drive; the minimal UI shows no speed row |
| Shipped — extended matrix incomplete | NTFS3 has an explicit one-mount menu choice, Experimental warning/preflight, no silent fallback, privacy-safe driver/result diagnostics, and a passing dirty-refusal/repair/clean-write/Windows-reread cycle; broader devices and OS versions remain resource-gated. |
| Shipped — extended matrix incomplete | Live mount-state reconciliation pairs physical inventory, host NFS truth, and bounded runtime probes, polls every five seconds, refreshes on lifecycle actions, and fails closed to yellow/unknown on disagreement. GUI/CLI unmount, external NFS/Finder disconnect, restart, concurrent devices, and selective physical hot-unplug pass on the installed package; broader hardware remains resource-gated. |
| Shipped — extended media check blocked | Verified Copy is a per-drive overflow action for verified read/write mounts. It validates the exact destination volume, invokes the unprivileged CLI with literal argv, shows compact progress/result state, and cancels the whole process group; cross-OS hash proof passes, while controlled TV playback remains resource-gated. |
| Shipped | Default-off local mount/unmount/error notifications, persisted only after macOS grants permission |
| Shipped | Eject All attempts every drive, reports per-drive results, and retains recovery controls for failures |

---

## Button & control plan

### Popover — idle (no mount)

| Control | Action | Enabled when |
|---------|--------|--------------|
| Drive row `[Mount]` | Mount that drive r/w via XPC helper | A compatible drive is detected |
| Drive row `…` → `NTFS3 (Experimental)…` | Show preflight, then opt this NTFS mount into NTFS3 once | An unmounted NTFS drive is detected |
| Refresh (↻) | Re-scan drives now | Always |
| `Diagnose` | Run CLI diagnostic, show summary | Always |
| `⌘`-click `Diagnose` | Run the same read-only diagnostic and save its JSON for developer support | Always |
| ⚙ (gear) | Navigate to Settings in the popover | Always |
| `Quit` | Exit app, tear down network state | Always |

### Popover — mounted

| Control | Action | Enabled when |
|---------|--------|--------------|
| Per-drive `Open` | Open that drive's reconciled mount point in Finder | That mounted drive is independently verified |
| Per-drive `Unmount` | Safely unmount that drive | That drive is mounted |
| Per-drive `…` → `Verified Copy…` | Choose one source and a fresh destination on that exact volume; copy, flush, reread, and compare SHA-256 | That drive is independently verified read/write and no copy is active |
| Verified Copy status / `Cancel` | Show only the active/result state; cancel the CLI and all copy/hash children while retaining any partial | A copy is active; dismissal is available after completion |
| `Eject All` | Try every mounted drive and show each result without hiding failed rows | Two or more drives are mounted |
| Other-device `Mount` | Mount another compatible partition | Another compatible drive is detected |
| Refresh (↻) | Re-scan drives and reconcile mounted rows against host truth | Always |
| SECURITY rows | Display measured private-link, VPN-route, and PF-policy states/reasons; fail closed to `unknown` | One or more drives mounted |
| SECURITY `Hide` / `Show` | Collapse or restore only the SECURITY presentation | One or more drives mounted |
| ⚙ / `Quit` | As above | Always |

The mounted row intentionally stops at two primary actions: Open and Unmount. Verified Copy is the
single secondary item in its small overflow menu, and its card exists only while a job/result
exists. Eject All appears only when it is useful for multiple drives. No transfer-speed row is
shown: the removed sampler observed bridge-wide traffic and could not provide honest per-drive
telemetry for concurrent mounts. Mount lifecycle, Settings, and Quit controls remain disabled
while Verified Copy owns a write.

### Mount-state truth contract

The GUI and CLI are two controls over one real host mount state. The macOS mount table plus
ntfsmac-owned anylinuxfs session evidence are authoritative; `MountController.mountedDrives` is a
cache for presentation, never proof by itself.

The packaged 2.0 (050826) build violates this contract: after a successful CLI unmount, the GUI
continued to show a green `Mounted read/write` row and `Unmount` button. Refresh did not converge
it, while the GUI's own Diagnose panel reported an inactive bridge and zero NFS mounts.

The P0 remediation implements this contract in source: helper success is provisional, the app
reconciles at launch/popover open/every five seconds/Refresh/after helper completion, and an
incomplete or inconsistent snapshot preserves recovery controls in yellow `unknown` rather than
publishing green. On 2026-08-11 one packaged device passed GUI unmount, Finder network-share
disconnect, and an external NFS unmount with complete VM/PF/route reconciliation. The later
packaged matrix also passed CLI-to-GUI discovery, restart recovery, concurrent devices, and
selective physical hot-unplug: the absent device left the GUI and backend automatically while the
live sibling and its enforced security session remained. Broader device/controller/OS coverage
remains resource-gated rather than being inferred from the tested host.

Writability is also a two-layer fact. The host NFS client and the guest filesystem beneath its
export can disagree: a writable NFS client does not make a guest `ntfs,ro` mount writable. The
2026-08-16 installed replay exposed exactly that false-green state. Commit `06dcd03` preserves the
guest mode from anylinuxfs status and combines it with the paired host mount table; read-only at
either layer must prevent a green read/write row.

Required behavior:

- reconcile on launch, popover open, periodic poll, Refresh, and after helper completion;
- discover CLI-created mounts and remove CLI/external-unmounted rows within a bounded interval;
- verify both paired host NFS and guest filesystem read/write state before publishing green;
- represent disagreement explicitly as warning/unknown, never as mounted read/write;
- keep multiple mount rows independent across partial failure and teardown;
- derive header, icon, controls, and Diagnose context from the same reconciled snapshot.

The detailed live evidence and acceptance matrix are in
[`../audits/LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md`](../audits/LIVE_MOUNT_STATE_AND_NFS_TRANSPORT_AUDIT_2026-08-06.md)
and
[`../audits/LIVE_P0_SECURITY_TRANSACTION_AUDIT_2026-08-11.md`](../audits/LIVE_P0_SECURITY_TRANSACTION_AUDIT_2026-08-11.md).

### Unsafe dirty/hibernated state

| Control | Action |
|---------|--------|
| Warning banner | Explain that ntfsmac refused writable mounting and requires Windows repair/full shutdown |
| Unsafe Windows state | Never offer a read/write override. Refuse with `norecover`/driver policy and direct the user to Windows `chkdsk`, Fast Startup off, and a full shutdown |

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

With macOS Full Keyboard Access enabled, every interactive control has an explicit focus stop and
uses the native blue focus indicator. That indicator is intentionally visible only while keyboard
focus is active; it is accessibility state, not a permanent decorative border.

### Settings page

The gear replaces the main popover content with Settings. A keyboard-reachable `Back` action
returns to the previous application content. Normal, first-run, and CLI-repair screens all use the
same route and the same long-lived Settings/helper objects; navigation does not open an `NSWindow`
or recreate in-flight state. The title includes the app release/build directly underneath in
small secondary text; it is informative and never competes visually with the `Settings` heading.

| Control | Type | Default |
|---------|------|---------|
| Launch at login | Toggle | Off |
| Notifications | Toggle requesting macOS permission on first enable | Off |
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
state, the selected filesystem driver and fixed failure category, measured security reasons, a
yes/no VPN tunnel signal, and the active NFS mount count. It never displays
or exports usernames, serials, volume/device identity, local paths, VPN identity, addresses, DNS,
or routes.

### Deliberately omitted controls

There is no permanent copy page, global transfer-speed row, or saved no-op read-only/mount-point
preference. Verified Copy uses the mounted row's overflow menu and a transient card so the normal
surface remains focused on Mount, Open, and Unmount.

---

## Control → privilege boundary (non-negotiable)

Every control that mounts, unmounts, or touches pf/route goes through the **SMJobBless XPC helper** — never a raw `sudo` shell-out from the UI. Device names are validated against `^disk[0-9]+s[0-9]+$` in *both* the UI and the helper before any shell call. (Mirrors `PLAN.md` §4.2.)
