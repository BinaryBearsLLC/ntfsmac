# ntfsmac GUI — Feature & Button Plan

> BinaryBears keeps the visible application name **ntfsmac**. Settings also includes a minimal
> GitHub release check; it never downloads or installs software. The standard macOS 13+ build uses
> an SMAppService helper; the explicitly labelled Legacy build retains SMJobBless compatibility.

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
same popover; the only separate system UI is helper authorization/approval (including Login Items
for the standard build). The CLI
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
| Integrated candidate — live v3.1.0 gate pending | Diagnose renders four plain-language, fail-closed macro categories with semantic text/symbol/colour, inline Hide, and Command-click privacy-safe JSON export; the CLI schema remains unchanged |
| Integrated candidate — live v3.1.0 gate pending | Consent-first standard/Legacy helper install, explicit Login Items approval state for the standard build, progress-backed CLI staging, pre-mount Full Disk Access verification, helper repair, and complete-uninstall flows |
| Integrated candidate — live v3.1.0 gate pending | In-popover Settings with a balanced Back/title/update-icon header, canonical version/build, Launch at login, contextual help, and adaptive menu-bar icon |
| Integrated candidate — live v3.1.0 gate pending | Connection protection appears only inside a freshly run Diagnose result. There is no standalone SECURITY row group or collapsed Show placeholder; missing evidence remains non-green. |
| Shipped | Each verified mounted-drive row exposes Open in Finder and uses that row's observed mount point |
| Resolved | Global transfer telemetry was removed because bridge-wide counters cannot truthfully attribute concurrent traffic per drive; the minimal UI shows no speed row |
| Shipped — extended matrix incomplete | NTFS3 has an explicit one-mount menu choice, Experimental warning/preflight, no silent fallback, privacy-safe driver/result diagnostics, and a passing dirty-refusal/repair/clean-write/Windows-reread cycle; broader devices and OS versions remain resource-gated. |
| Shipped — extended matrix incomplete | Live mount-state reconciliation pairs physical inventory, host NFS truth, and bounded runtime probes, polls every five seconds, refreshes on lifecycle actions, and fails closed to yellow/unknown on disagreement. GUI/CLI unmount, external NFS/Finder disconnect, restart, concurrent devices, and selective physical hot-unplug pass on the installed package; broader hardware remains resource-gated. |
| Shipped — extended media check blocked | Verified Copy is a per-drive overflow action for verified read/write mounts. It validates the exact destination volume, invokes the unprivileged CLI with literal argv, shows compact progress/result state, and cancels the whole process group; cross-OS hash proof passes, while controlled TV playback remains resource-gated. |
| Shipped | Default-off local mount/unmount/error notifications, persisted only after macOS grants permission |
| Shipped | Eject All attempts every drive, reports per-drive results, and retains recovery controls for failures |
| Integrated candidate — live v3.1.0 gate pending | Mounted-drive Quit confirmation with safe `Unmount and Quit`, `Quit Anyway`, Cancel, safe-only persistence, and Command-click reset; active copy/mount/unmount disables Quit |
| Integrated candidate — visual gate pending | Pointer input suppresses stale focus presentation; deliberate keyboard traversal uses one in-bounds one-point outline on macOS 14+ and preserves the native accessible focus behavior on macOS 13 |

---

## v3.1.0 refinement contract — integrated candidate

The behavior below is implemented in the `upgrade/v3.1.0` candidate. It remains subject to the
complete local Standard/Legacy and packaged visual/live gates, and is not a claim about the current
published `v3.0.0` release. Official DMG branding is still asset-blocked.

### 0.1 DMG rebrand asset gate

The standard and Legacy DMGs receive a new installer presentation based only on official
BinaryBears logo assets supplied by the maintainer. Until those source assets arrive this item is
blocked, not approximated: no generated substitute, traced logo, temporary mark, or modified
unapproved artwork may enter the candidate. Both DMGs use the same official brand system while
only the compatibility artifact says `Legacy`. The visible app remains `ntfsmac`.

Before release, visually inspect the mounted DMG at its real 720×460 size and verify logo clarity,
spacing, drag direction, app/Applications alignment, legibility, hidden-window chrome, and both
standard and Legacy naming. Automated packaging checks continue to verify the app, Applications
symlink, background reference, architecture, signatures, and image integrity.

### Button chrome and keyboard focus

The v3.0 controls could show two superimposed rectangles:

- the subtle rounded fill/stroke belongs to the custom button style and is visible in the normal
  pointer state;
- the thicker blue outline is the native macOS keyboard-focus indicator produced for explicitly
  focusable controls when Full Keyboard Access moves focus to that button.

The v3.1.0 candidate removes the stacked-frame appearance, not keyboard accessibility. A control
may have at most one deliberate default-state container. Icon-only secondary controls are
borderless at rest and gain background treatment on hover/press; primary row actions may retain a
single restrained affordance.

Opening/reopening the popover does not autofocus an action. Pointer hover, pointer activation,
state refresh, and asynchronous view updates must not move focus or leave a blue ring behind.
Focus becomes visible only after deliberate keyboard navigation such as Tab/Shift-Tab while Full
Keyboard Access is active. Its custom visual treatment is a subtle, high-contrast outline no more
than 1.5 points thick, does not stack with a second decorative stroke, and never changes layout.
Reverse traversal, returning from Settings, Diagnose completion, and list insertion/removal must
preserve predictable order without jumping to an unrelated control. macOS 13 retains the system's
native accessible focus effect because the public focus-effect suppression API starts on macOS 14;
no private AppKit hook is used.

### Settings update control

The text `Software update` row is replaced by an icon in the Settings header. The header is one
balanced three-column layout: Back is leading, `Settings` remains optically centred over the full
popover, and the update icon is trailing. Back and update occupy matched side geometry and share
the title's vertical alignment so loading/badging never shifts `Settings`. The version/build label
remains centred directly below the title. The update icon keeps a stable hit target and has all of
the following states without adding a second text row:

| State | Presentation and behavior |
| --- | --- |
| Idle | Update/check symbol, native tooltip, `Check for updates` VoiceOver label |
| Checking | Non-blocking compact progress state; repeated activation disabled |
| Up to date | Brief success acknowledgement, then return to idle |
| Update available | Distinct badge/accent; activation opens the verified GitHub Release page |
| Unavailable/error | Neutral warning state and concise help; no false `up to date` result |

The existing once-per-24-hours automatic check and manual-only navigation/download policy do not
change.

### GUI Diagnose information architecture

The CLI output and privacy-safe JSON remain unchanged. The GUI derives a separate presentation
model from that same report and shows user-facing macro categories rather than a long flat list:

| Macro category | User-facing scope |
| --- | --- |
| App readiness | `Ready`, `Setup needed`, or `Repair needed`, with one direct next action |
| Drive status | Drive detected/mounted, safe read/write state, or required recovery action |
| Connection protection | Plain-language protected/attention/unavailable result; no internal network terms |
| Permissions | Whether macOS permission is ready and exactly where the user must act |

Every category displays a status word, symbol, one-sentence explanation, and—only when useful—a
specific next action. The normal GUI has no technical disclosure and does not mention helper
identifiers, XPC, runtime pins, VM state, PF, routes, digests, or raw diagnostic keys. Those details
remain available to support/developers through the unchanged CLI and existing Command-click JSON
export.

| Semantic state | Colour role | Meaning |
| --- | --- | --- |
| Idle | Secondary neutral | Not currently required, for example no active mount |
| Checking | Blue accent | A fresh read-only diagnostic is running |
| OK | Green | All evidence required for this category is positively confirmed |
| Attention | Amber | Usable or recoverable, but the user should review an action |
| Failed | Red | A required condition is confirmed broken |
| Unavailable | Neutral with explicit text | Evidence is missing/malformed; never green |

Colour is always paired with text and a symbol. Category aggregation is fail-closed: confirmed
failure outranks attention, attention outranks OK, and missing required evidence becomes
Unavailable rather than passing. `Idle` is reserved for evidence that is genuinely not expected
in the current state; it is not an alias for unknown.

### Protection status integrated into Diagnose

There is no standalone SECURITY section, row group, placeholder, or collapsed `Show` header in the
v3.1.0 GUI. Running Diagnose reveals the freshly measured `Connection protection` macro category
inside the same user-friendly diagnostic presentation. Selecting `Hide` dismisses the complete
Diagnose presentation, including protection status, without changing helper, mount, or network
state. Running Diagnose again reveals a fresh complete result. This replaces the published v3.0
always-mounted SECURITY `Hide`/`Show` presentation in the v3.1.0 candidate.

### Quit with mounted drives

Quit remains immediate when no drive is mounted and no storage operation is active. With one or
more verified mounts, an in-popover confirmation must stay visible and offer:

1. `Unmount and Quit` — safe default; attempts every mounted drive, reports failures, and quits
   only after the defined teardown postcondition is reached.
2. `Quit Anyway` — exits without requesting unmount only if the architecture can keep the mounted
   filesystem and its required services valid; otherwise the implementation must not offer a
   misleading option.
3. `Cancel` — consumes no action and preserves all state.

`Don't show again` is available only with `Unmount and Quit` and persists only that safe action.
There is no Settings toggle or reset row. Command-clicking Quit clears the saved choice; when a
drive is mounted it immediately restores and shows the confirmation. This shortcut is documented
in the README and repository UI contract. With no mounted drive, Command-click still clears the
saved choice and then follows the normal immediate-Quit path.

Verified Copy and in-flight mount/unmount are stronger safety states in the candidate: Quit is
disabled while they run, they are never covered by the saved preference, and they are not
interrupted silently.

### Resource-impact acceptance

Measurements are local-only and add no analytics or telemetry. Capture three comparable runs and
report the median plus worst observed value for the app, privileged helper, VM/runtime processes,
and their combined total. Use the same hardware, OS, power mode, drives, polling interval, and
sample duration before and after the work.

| Scenario | Required evidence |
| --- | --- |
| App idle, popover closed | Average/peak CPU, resident memory, wakeups over 10 minutes |
| Popover open, no drive | Same metrics while normal five-second reconciliation runs |
| Refresh and Diagnose | Ten cycles; transient peak and time to return to baseline |
| One clean mounted drive | Separate app/helper/runtime totals over 30 minutes without I/O |
| Repeated mount/unmount | Ten safe cycles; final memory versus initial memory |
| Standard versus Legacy | Same scenario matrix and explained differences |

Before implementation, freeze numeric pass budgets from the pre-change measurements. At minimum,
the release gate rejects unexplained sustained idle CPU, monotonic memory growth, failure to return
near baseline after Diagnose, or a material regression between the pre-change and final candidate.

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
| `Quit` | Exit immediately when no drive is mounted | No storage operation or Verified Copy is active |
| `⌘`-click `Quit` | Clear the saved safe action, then follow normal Quit policy | No storage operation or Verified Copy is active |

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
| `Diagnose` | Reveal the four freshly measured macro categories, including Connection protection | No Diagnose or Verified Copy is active |
| `Hide` | Dismiss the complete Diagnose result, leaving no collapsed placeholder | A Diagnose presentation is visible |
| `Quit` | Show the mounted-drive confirmation or execute the remembered safe unmount action | No storage operation or Verified Copy is active |
| ⚙ | Navigate to Settings | No Verified Copy is active |

The mounted row intentionally stops at two primary actions: Open and Unmount. Verified Copy is the
single secondary item in its small overflow menu, and its card exists only while a job/result
exists. Eject All appears only when it is useful for multiple drives. No transfer-speed row is
shown: the removed sampler observed bridge-wide traffic and could not provide honest per-drive
telemetry for concurrent mounts. Mount lifecycle, Settings, and Quit controls remain disabled
while Verified Copy owns a write; Quit also stays disabled during mount/unmount/eject operations.

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
returns to the previous application content. Normal, helper-install, CLI-repair, and Full Disk
Access setup screens all keep that gear reachable and use the same route plus the same long-lived
Settings/helper objects; navigation does not open an `NSWindow` or recreate in-flight state. The
title includes the app release/build directly underneath in small secondary text; it is
informative and never competes visually with the `Settings` heading.

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

Every control that mounts, unmounts, or touches pf/route goes through the reviewed **XPC helper** — SMAppService in the standard build, SMJobBless in Legacy, and never a raw `sudo` shell-out from the UI. Device names are validated against `^disk[0-9]+s[0-9]+$` in *both* the UI and the helper before any shell call. (Mirrors `PLAN.md` §4.2.)
