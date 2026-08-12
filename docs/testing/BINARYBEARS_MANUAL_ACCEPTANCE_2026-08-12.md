# BinaryBears packaged manual acceptance — 2026-08-12

This is the executable hardware checklist for the P0, P1, and P3 software now present on the
BinaryBears branch. It does **not** turn an automated pass into a hardware pass. Every row remains
`NOT RUN` until its action, expected result, and evidence have been observed on the packaged
candidate.

The active session ledger is
[`BINARYBEARS_VALIDATION_RESULTS_2026-08-12.md`](BINARYBEARS_VALIDATION_RESULTS_2026-08-12.md).

P2 (`SMAppService`) is deliberately absent. The installed helper must remain the current
`SMJobBless` implementation throughout this matrix.

## How we will run it together

- Codex prepares one bounded step at a time, reads the available command output, checks it against
  the acceptance rule, and updates the session ledger.
- The human operator handles USB connection/removal, administrator authentication, Full Disk
  Access, notification permission, VPN state, Finder actions, and Windows preparation.
- We record `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN`; an unavailable device or OS is `BLOCKED`, never
  silently treated as a pass.
- We do not proceed after a stop condition. We preserve evidence first, then diagnose.

## Safety and stop conditions

Use only backed-up, disposable NTFS media. Two drives are needed for the concurrent/Eject All
tests. A Windows machine or Windows installation is needed for the clean/dirty/Fast Startup and
Windows-side hash cells.

Stop immediately if any of these occurs:

- a SHA-256 value differs after an unmount/reconnect;
- the GUI remains green more than ten seconds after both host mount evidence and the anylinuxfs
  session disappear;
- Unmount reports success while the NFS mount remains present;
- either live security gate fails;
- an unexpected volume, partition, route, PF anchor, or non-test file would be changed;
- macOS reports an I/O error, the device repeatedly disconnects, or the only copy of data is on
  the test drive.

Never reformat a drive, run `ntfsfix`, disable SIP/Gatekeeper, or change a network interface as a
troubleshooting shortcut. Windows filesystem repair, when actually required, uses `chkdsk` after
we have preserved the failing evidence.

## Session setup and evidence

Before changing system state, we will resolve every placeholder and show the exact command. Do
not paste placeholder text literally.

```bash
export BB_REPO="/Users/andrea/Documents/GitHub/ntfsmac"
export BB_CLI="/usr/local/ntfsmac/bin/ntfsmac"
export BB_APP="/Applications/ntfsmac.app"
export BB_DMG="$BB_REPO/dist/ntfsmac.dmg"
export BB_RUN_ID="$(date +%Y%m%d-%H%M%S)"
export BB_EVIDENCE="$HOME/Desktop/ntfsmac-acceptance-$BB_RUN_ID"
mkdir -p "$BB_EVIDENCE"

# Resolve together after `diskutil list external physical`.
export BB_DISK_A="diskNsN"
export BB_VOLUME_A="/Volumes/label-a"
export BB_DISK_B="diskNsN"
export BB_VOLUME_B="/Volumes/label-b"
export BB_REMOTE_A="$BB_VOLUME_A/BinaryBears-Acceptance-$BB_RUN_ID"
export BB_REMOTE_B="$BB_VOLUME_B/BinaryBears-Acceptance-$BB_RUN_ID"
```

For each test retain:

1. the test ID and timestamp;
2. candidate Git commit plus app release/build;
3. macOS version, Mac model/architecture, USB device/controller, partition map, VPN state, and
   chosen filesystem driver;
4. exact exit status and unedited output for commands;
5. a screenshot for visible GUI states;
6. hashes/manifests and the post-unmount cleanup result where applicable.

The diagnostic JSON is privacy-safe by contract, but all other local Terminal evidence can still
contain volume labels and device identifiers. Keep the evidence folder local unless it has been
reviewed.

## Ordered test ledger

| ID | Test | Required setup | Acceptance summary |
| --- | --- | --- | --- |
| BB-00 | Candidate and host identity | No drive | Exact packaged candidate, valid signature, Apple Silicon, Hypervisor available |
| BB-01 | Clean install and first run | No drive, admin available | Helper and bundled CLI install; no Homebrew dependency or policy weakening |
| BB-02 | `opengui`, cold and warm | Installed app | Popover opens reliably without Accessibility or synthetic clicks |
| BB-03 | Minimal visual surface | Installed app | Light/dark, keyboard, Settings/Back, no speed or no-op preference controls |
| BB-P0-01 | Default mount, VPN off | Drive A clean | Verified `ntfs-3g` RW/RO truth plus both live security gates |
| BB-P0-02 | Canonical teardown | BB-P0-01 mounted | NFS/session/PF/route state is removed; GUI returns to idle/detected |
| BB-P0-03 | Default mount, VPN on | Drive A clean, VPN on | Same gates pass without altering the VPN default route |
| BB-P0-04 | Route change while mounted | No I/O in progress | State remains truthful and private route still passes after VPN transition |
| BB-P0-05 | GUI/CLI cross-surface truth | Drive A | GUI→CLI and CLI→GUI converge within ten seconds |
| BB-P0-06 | External NFS disconnect | Drive A mounted | GUI loses green state and helper cleans the orphaned backend transaction |
| BB-P0-07 | App crash/restart recovery | Disposable Drive A | Relaunch discovers the real surviving state and can unmount it safely |
| BB-P0-08 | Helper reconnect | No active mount | Restarted helper reconnects; next mount/unmount succeeds once |
| BB-P0-09 | Two concurrent drives | Drives A+B | Two independent verified rows/security sessions; one teardown preserves the other |
| BB-P0-10 | Fail-closed security evidence | Mounted, no I/O | Insecure/unreadable public evidence becomes unknown, never green, then recovers |
| BB-P1-00 | Minimal GUI Verified Copy | Drive A verified RW | Overflow-only flow stays on exact volume; success, refusal, and Cancel are truthful |
| BB-P1-01 | Verified single-file copy | Drive A RW | Publish only after SHA-256 match; overwrite refused; mutation detected |
| BB-P1-02 | Verified directory tree | Drive A RW | Nested/Unicode/many-small-file/symlink manifest matches deterministically |
| BB-P1-03 | Interrupted copy recovery | Disposable free space | Source retained, final name absent, named partial retained and reported |
| BB-P1-04 | Physical reconnect hash | BB-P1-01 complete | Hash still matches after safe unmount, disconnect, reconnect, and reread |
| BB-P1-05 | Windows-side hash/playback | Same media/source/port | Independent Windows hash matches; controlled TV comparison is repeatable |
| BB-P1-06 | Same-device NTFS3 comparison | Clean disposable Drive A | Explicit NTFS3, no fallback, same operations/data/manifests as `ntfs-3g` |
| BB-P1-07 | NTFS state matrix | Windows-prepared spare | Clean/dirty/Fast Startup/error states fail or mount exactly as reported |
| BB-P1-08 | Extended workload matrix | Spare media/time | Low-space, cancellation, long copy, controller/map/OS coverage is recorded |
| BB-P3-01 | Per-drive Open in Finder | Drives A+B mounted | Each Open action reveals that row's observed mount point |
| BB-P3-02 | Opt-in notifications | Permission controllable | Default off; explicit grant only; events shown; revoke/disable fails closed |
| BB-P3-03 | Eject All success | Drives A+B mounted | Every drive attempted, two successes reported, all backend state removed |
| BB-P3-04 | Eject All partial recovery | Two disposable drives | Failure is per-drive; successful drive leaves; failed row remains actionable |
| BB-F01 | No-I/O hot-unplug recovery | Disposable Drive A only | No hang/false green; bounded reconciliation and cleanup; no writes in flight |
| BB-F02 | Safe eject and uninstall | No active mount | Physical eject follows app unmount; complete uninstall leaves no helper/runtime |

## BB-00 — candidate and host identity

Run read-only checks:

```bash
cd "$BB_REPO"
git rev-parse HEAD | tee "$BB_EVIDENCE/BB-00-git.txt"
/usr/bin/shasum -a 256 "$BB_DMG" | tee "$BB_EVIDENCE/BB-00-dmg.sha256"
/usr/bin/uname -m | tee -a "$BB_EVIDENCE/BB-00-host.txt"
/usr/bin/sw_vers | tee -a "$BB_EVIDENCE/BB-00-host.txt"
/usr/sbin/sysctl kern.hv_support | tee -a "$BB_EVIDENCE/BB-00-host.txt"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$BB_APP"
/usr/bin/plutil -extract CFBundleShortVersionString raw "$BB_APP/Contents/Info.plist"
/usr/bin/plutil -extract CFBundleVersion raw "$BB_APP/Contents/Info.plist"
```

Pass only when the commit is the intended candidate, architecture is `arm64`,
`kern.hv_support: 1`, the strict signature check exits zero, and release/build match Settings and
`ntfsmac diagnose --json`.

## BB-01 — clean install and first run

This checkpoint changes system state and starts only after the existing install has no active
mount. Use the candidate DMG, drag the app to `/Applications`, then right-click **Open** if macOS
requires explicit approval. Approve only the expected `com.khr898.ntfsmac.helper` authorization.

Pass when:

- the first-run flow reaches the normal popover;
- `/usr/local/ntfsmac/bin/ntfsmac help` lists `copy`, `verify`, `diagnose`, and `opengui`;
- `sudo launchctl print system/com.khr898.ntfsmac.helper` finds exactly one service;
- Settings and diagnostic JSON report the same release/build;
- no global Gatekeeper/SIP change, Accessibility permission, Homebrew install, or manual `sudo`
  mount shim was required.

If Full Disk Access is requested, enable exactly the helper service shown by the app, return to the
popover, and retry. A denial or cancel must remain recoverable rather than showing a false install.

## BB-02 — `opengui` cold and warm

1. Quit ntfsmac and verify no app process remains.
2. Run `"$BB_CLI" opengui`; require `opengui: popover requested`, one app instance, and the visible
   popover within roughly two seconds. It must be anchored directly beneath its own menu-bar icon;
   a detached popover or lower-left fallback is a failure.
3. Close only the popover, run the same command again, and require the existing instance to reveal
   it.
4. Run the command three times quickly. Require one app instance and one usable, correctly anchored
   popover.
5. Run `"$BB_CLI" opengui unexpected`; require exit status `2` and no new app instance.

Accessibility permission must not appear in any step.

## BB-03 — minimal visual surface

Inspect light and dark appearance at idle, mounting, mounted RW, warning/unknown, and error when a
real safe reproduction exists. Confirm:

- no Dock icon, extra Settings window, global speed row, default mount-point field, or persisted
  read-only control;
- Settings replaces the popover and Back restores it;
- text is not clipped at the normal menu-bar width;
- keyboard focus reaches gear, Back, Mount/Open/Unmount, the per-drive overflow menu, Verified
  Copy Cancel/dismiss, Diagnose, notification toggle, Eject All, report dismissal, and Quit;
- native help appears without changing layout.

## P0 live mount and security tests

### BB-P0-01 / BB-P0-03 — default mount with VPN off, then on

Run the same steps twice, recording VPN state before the mount. Do not disable Ethernet or Wi-Fi.
Only the VPN control changes, and only when no copy is active.

1. Resolve Drive A with `diskutil list external physical`; require a partition identifier matching
   `disk[0-9]+s[0-9]+`, never a whole disk.
2. In the GUI select the normal **Mount** button. It must use `ntfs-3g`; do not select NTFS3.
3. Require a blue mounting state followed by a verified green RW state, or a truthful yellow RO
   state if the NTFS journal is unclean.
4. When RW, create, reread, and retain one uniquely scoped test file:

   ```bash
   mkdir -p "$BB_REMOTE_A"
   printf 'BinaryBears P0 round trip\n' > "$BB_REMOTE_A/p0-round-trip.txt"
   printf 'BinaryBears P0 round trip\n' \
     | /usr/bin/cmp - "$BB_REMOTE_A/p0-round-trip.txt"
   ```

5. Run:

```bash
"$BB_CLI" diagnose --json \
  | tee "$BB_EVIDENCE/BB-P0-vpn-state-diagnose.json" \
  | /usr/bin/python3 -m json.tool
"$BB_REPO/tests/live/verify-nfs-transport.sh"
sudo "$BB_REPO/tests/live/verify-security-transaction.sh"
/sbin/mount -t nfs
/usr/bin/nfsstat -m
```

Pass only when diagnostics identify `ntfs-3g`, `network_helper=vmnet`, the expected vmnet transport
contract, and measured security state; both gates exit zero; the NFS mount is `soft`; and no
loopback/gvproxy transport is accepted. With VPN on, ntfsmac may add only the exact private host
route it owns and must not replace the VPN default route.

### BB-P0-02 — canonical teardown

Click the row's **Unmount** and wait for observed host truth. Pass when the GUI returns to
detected/idle, `/sbin/mount -t nfs` has no ntfsmac entry, anylinuxfs has no matching session,
diagnostics show zero active security sessions, and:

```bash
sudo /usr/bin/find /var/run/ntfsmac/security -type f -name '*.state' -print 2>/dev/null || true
sudo /sbin/pfctl -s Anchors 2>/dev/null | /usr/bin/grep 'com.apple/ntfsmac-' || true
```

prints no surviving per-session state or child anchor. Run this after each teardown, not only once
at the end.

### BB-P0-04 — VPN route transition while mounted

Mount while no file operation is running, capture both live-gate passes, then enable or disable
only the VPN. Wait ten seconds, select Refresh, rerun diagnostics and both gates, and perform a
small read. The GUI must remain green only if host/security evidence remains verified. Any unknown
state is acceptable while evidence is genuinely unavailable; a false green or route outside the
measured bridge is a failure. Return the VPN to its initial state and rerun the gates before
unmounting.

### BB-P0-05 — GUI/CLI cross-surface truth

1. GUI mount → `"$BB_CLI" unmount "$BB_DISK_A"`: row must disappear within ten seconds without
   Refresh.
2. CLI mount → already-open GUI:

   ```bash
   "$BB_CLI" mount "$BB_DISK_A"
   ```

   The correct row and observed RW/RO state must appear within ten seconds.
3. Repeat each direction with an immediate GUI Refresh.
4. Verify `Open` and `Unmount` still target the discovered CLI mount rather than cached paths.

### BB-P0-06 — external NFS disconnect

With no I/O running, use Finder **Disconnect** on the synthetic network share, not Eject on the
physical USB device. The GUI must stop showing green and the helper must remove the orphaned VM,
session PF policy, and exact route. Repeat once with `sudo /sbin/umount "$BB_VOLUME_A"` as the
external actor. Allow up to two polling intervals, then apply the BB-P0-02 cleanup checks.

### BB-P0-07 — app crash/restart recovery

On disposable media, mount Drive A and wait for both gates to pass. With no write in progress,
force-quit only the GUI process. The NFS/backend may remain active; that is the state being tested.
Run `"$BB_CLI" opengui`. The relaunched app must discover the existing mount and its verified
RW/RO state within ten seconds, then its normal Unmount must pass BB-P0-02. Never kill the helper,
VM, or USB connection during this test.

### BB-P0-08 — helper reconnect

With no active mounts, restart the existing helper service:

```bash
sudo /bin/launchctl kickstart -k system/com.khr898.ntfsmac.helper
```

Keep the app open. The next one-drive GUI mount and unmount must succeed without reinstalling or
creating a duplicate service. If the service label differs, stop and inspect; do not guess another
launchd target.

### BB-P0-09 — concurrent drives

Mount A, then B. Require two independent verified rows and:

- both live gates pass with count `2`;
- Open A and Open B reveal different correct mount points;
- unmounting A leaves B green/verified and the security gate count becomes `1`;
- remounting A restores count `2`;
- no result, notification, or diagnostic mixes device labels or paths.

### BB-P0-10 — fail-closed public evidence

This is a reversible fault test. While both live gates already pass and no I/O is active, make the
public summary insecure, refresh, then restore it:

```bash
stat -f '%Su %Sg %Lp' /var/run/ntfsmac/security-status
sudo /bin/chmod 0666 /var/run/ntfsmac/security-status
# Select Refresh: all three SECURITY rows must become unknown/non-green.
sudo /bin/chmod 0644 /var/run/ntfsmac/security-status
# Select Refresh again: the measured rows must recover.
stat -f '%Su %Sg %Lp' /var/run/ntfsmac/security-status
```

The owner must remain `root` and final mode `644`. Do not mount, unmount, or alter the root-only
per-session files while the public file has the test mode.

## P1 Verified Copy and NTFS3 qualification

### BB-P1-00 — minimal GUI Verified Copy

Mount Drive A read/write and wait until its row is independently verified. The normal row must
still show only **Open** and **Unmount** as primary actions; open its small `…` menu and select
**Verified Copy…**.

```bash
export BB_FIXTURE="$BB_EVIDENCE/fixtures"
mkdir -p "$BB_FIXTURE" "$BB_REMOTE_A"
printf 'BinaryBears GUI verified copy fixture\n' > "$BB_FIXTURE/gui-source.bin"
```

1. Choose `"$BB_FIXTURE/gui-source.bin"`. The destination panel must begin at
   Drive A's observed mount point. Cancel this first picker pass: no status or file is created.
2. Repeat, then deliberately choose a fresh path outside Drive A if the panel permits navigation.
   The app must reject it with `Choose a destination inside this mounted drive`; no process or
   partial starts.
3. Repeat with the fresh destination `"$BB_REMOTE_A/gui-small.bin"`. Require one compact status
   card, a final green success state, and the published file only after the SHA-256 match.
4. Select the same existing destination again. Require an explicit no-overwrite refusal and the
   original destination hash unchanged.
5. After checking local and Drive A free space, create a disposable large source with
   `/usr/sbin/mkfile 2g "$BB_FIXTURE/gui-cancel-large.bin"` and select the fresh destination
   `"$BB_REMOTE_A/gui-cancel.bin"`. While the card is active, verify
   Mount/Unmount/Eject All/Settings/Quit cannot start, then select **Cancel**. Require the source to
   remain, the final name to remain absent, the card to report cancellation, and any hidden
   `.gui-cancel.bin.ntfsmac-partial.*` to remain recoverable beside the requested destination. If
   2 GiB finishes before Cancel can be selected, record that successful run and repeat with a
   larger disposable source only after rechecking free space.

The overflow action must be absent for a read-only, dirty, or unverified row. Closing and reopening
the popover through `ntfsmac opengui` while a copy is active must show the same in-flight card,
never start a second copy, and never expand the normal interface into a permanent copy page.

### BB-P1-01 — verified single-file copy

Create the source only in the local evidence folder and the destination only inside the unique
test directory on Drive A:

```bash
export BB_FIXTURE="$BB_EVIDENCE/fixtures"
mkdir -p "$BB_FIXTURE" "$BB_REMOTE_A"
/bin/dd if=/dev/urandom of="$BB_FIXTURE/source-256MiB.bin" bs=1048576 count=256
/usr/bin/shasum -a 256 "$BB_FIXTURE/source-256MiB.bin" \
  | tee "$BB_EVIDENCE/BB-P1-01-source.sha256"

"$BB_CLI" copy --verify \
  "$BB_FIXTURE/source-256MiB.bin" "$BB_REMOTE_A/copied-256MiB.bin"
"$BB_CLI" verify \
  "$BB_FIXTURE/source-256MiB.bin" "$BB_REMOTE_A/copied-256MiB.bin"
```

Require the exact success message that the SHA-256 manifest matched and the destination was
published. Run the copy command again to the same destination: it must refuse overwrite and leave
the existing hash unchanged.

For mutation detection, copy a second tiny fixture, append a known test line to only that
destination, and require `ntfsmac verify` to exit non-zero with `differs`. Do not mutate the
256 MiB artifact reserved for reconnect/Windows verification.

### BB-P1-02 — deterministic directory tree

Create a local tree with nested directories, spaces, Unicode, 500 small files, and a relative
symlink:

```bash
mkdir -p "$BB_FIXTURE/source tree/nested/deep"
printf 'video fixture\n' > "$BB_FIXTURE/source tree/nested/film one.mkv"
printf 'unicode\n' > "$BB_FIXTURE/source tree/caffè.txt"
for n in $(/usr/bin/jot 500 1); do
  printf 'small file %s\n' "$n" > "$BB_FIXTURE/source tree/nested/deep/item-$n.txt"
done
/bin/ln -s 'nested/film one.mkv' "$BB_FIXTURE/source tree/film-link"

"$BB_CLI" copy --verify \
  "$BB_FIXTURE/source tree" "$BB_REMOTE_A/copied tree"
"$BB_CLI" verify \
  "$BB_FIXTURE/source tree" "$BB_REMOTE_A/copied tree"
/bin/test -L "$BB_REMOTE_A/copied tree/film-link"
/usr/bin/readlink "$BB_REMOTE_A/copied tree/film-link"
```

Pass only when the link remains a symlink with target `nested/film one.mkv` and the complete
manifest matches. Permissions, ownership, ACLs, xattrs, resource forks, timestamps, hard links,
and sparse layout remain explicitly outside this contract and must not be reported as verified.

### BB-P1-03 — interrupted copy recovery

Use a disposable large source and a fresh destination name. Start `copy --verify`, interrupt it
once with Control-C while the copy is visibly active, and require:

- exit status `130`;
- the local source still exists;
- the final destination name does not exist;
- exactly one hidden `.<name>.ntfsmac-partial.*` directory is printed and retained;
- its contents can be inspected, but are never mistaken for a published success.

If the copy finishes before interruption, that run is a valid successful copy but does not pass
this test; repeat with a larger disposable source. Remove only the exact printed partial after its
evidence is captured.

### BB-P1-04 / BB-P1-05 — independent media-cycle verification

Safely unmount, wait for BB-P0-02, physically disconnect and reconnect the same device, remount
with the same driver, then rerun `verify` against `copied-256MiB.bin`. Record a fresh destination
SHA-256. On Windows, fully unmount from ntfsmac first, attach the same device, and run:

```powershell
certutil -hashfile "X:\BinaryBears-Acceptance-<run-id>\copied-256MiB.bin" SHA256
```

The Windows value must equal the retained Mac source hash. For the reported TV-artifact
investigation, repeat macOS-managed and Windows-managed copies with the same source, drive, port,
and TV input; keep run order, playback timestamps, and hashes. Different media or unmatched hashes
cannot support a filesystem-driver conclusion.

### BB-P1-06 — same-device `ntfs-3g` versus NTFS3

Run on a clean, Windows-safely-ejected disposable volume. First complete the dataset under default
`ntfs-3g`; then unmount cleanly and select **NTFS3 (Experimental)** for one mount. Confirm the
preflight names full Windows shutdown, Fast Startup, and `chkdsk`, and says there is no automatic
fallback.

For each driver, use a fresh driver-named test directory and perform: create, Verified Copy,
overwrite of a disposable file, append, rename, move between two test subdirectories, delete,
directory-tree verification, safe unmount, remount, and post-remount verification. Diagnostics
must report the requested driver. If NTFS3 fails, it must report a fixed failure category and must
not silently mount through `ntfs-3g`.

Record duration as observational data only; reliability and hash results decide acceptance.

### BB-P1-07 — Windows-prepared filesystem states

Use a dedicated spare and prepare each state separately on Windows. Preserve the data before the
dirty/error cells.

| State | Required observation |
| --- | --- |
| Clean, fully shut down | Both explicit driver attempts and full operation matrix |
| Dirty journal | Truthful RO/refusal/error; never false RW and never silent fallback |
| Fast Startup/hibernated | NTFS3 refusal or behavior matches the pinned warning; recovery guidance is Windows-only |
| Filesystem error | Deterministic failure category; repair with Windows `chkdsk`, then repeat clean state |

Do not intentionally dirty valuable data. An expected refusal is a pass only when state,
diagnostic category, and recovery guidance are all accurate.

### BB-P1-08 — extended workload and coverage inventory

Repeat the same manifest-backed operation set where the test pool permits:

- long/repeated large-file copies and both CLI and GUI cancellation;
- low free space on a dedicated test volume;
- multiple USB controllers/cables and capacities;
- GPT and MBR NTFS partition maps;
- every supported macOS major release available on Apple Silicon;
- non-system data and permission-sensitive Windows-system-volume reads;
- two concurrent drives and VPN off/on.

Each unavailable combination is recorded as `BLOCKED (test resource unavailable)`. A single Mac,
device, controller, or partition map cannot close the project-wide qualification gate.

## P3 focused UX tests

### BB-P3-01 — exact per-drive Open in Finder

With A and B mounted, click **Open** on A, note the Finder location, close that window, then click
**Open** on B. Each must reveal the mount point shown by host truth for that row. Open is disabled
when a row is unverified. No aggregate/first-drive shortcut may open the wrong volume.

### BB-P3-02 — notifications are genuinely opt-in

1. With a fresh/default Settings state, Notifications is off. Mount/unmount once: no ntfsmac
   notification should appear.
2. Enable it. macOS permission is requested only now; the toggle persists only after a grant.
3. Mount and unmount: require concise volume/result notifications with no raw helper output,
   device ID, path, IP, or security internals.
4. Generate one safe, controlled mount/unmount failure during a disposable test; require a concise
   failure notification and the full recovery control to remain in the app.
5. Disable notifications and repeat a successful action: no notification.
6. Re-enable, revoke permission in System Settings, reopen Settings, and require the toggle to
   reconcile off with actionable guidance instead of claiming enabled.

### BB-P3-03 — Eject All success

Mount A and B, prove security count `2`, then select **Eject All**. While it runs, per-drive mutating
actions and Quit are disabled. Pass when both helper operations are attempted, the compact report
shows two `Unmounted` results, both rows leave, and BB-P0-02 shows no backend/PF/route residue.

### BB-P3-04 — Eject All partial failure and recovery

This test is attempted only on disposable data. In a second Terminal, start a read-only working-
directory hold on A:

```bash
/bin/zsh -c 'cd "$1" && printf "hold active — press Return after Eject All\n" && read -r' \
  _ "$BB_VOLUME_A"
```

Leave that Terminal waiting, then select Eject All while B is idle. After the report appears, press
Return in the hold Terminal. If the backend still unmounts both, record that the safe failure
injection was ineffective rather than inventing a failure. Do not pull a cable to manufacture this
UI state.

When one unmount genuinely fails, require:

- B is still attempted and can succeed;
- the report has one result per original row;
- A remains visible, non-green/unverified as appropriate, with its own Open/Unmount recovery
  controls after the batch ends;
- closing the report changes presentation only;
- after releasing the safe hold, A's normal Unmount succeeds and clears the stale report.

The deterministic partial-failure path is also a mandatory automated regression test, even when
the packaged environment cannot safely force one.

## Final fault and cleanup tests

### BB-F01 — no-I/O hot-unplug recovery

Run last, on a disposable drive, with no write, copy, open Finder window, or shell working
directory on the volume. Capture both live-gate passes, then physically remove the device without
using ntfsmac Unmount. Require bounded UI transition away from green, no indefinite filesystem
hang, and eventual helper/PF/route cleanup. Any I/O error or lingering state is preserved as a
failure. This does not test data safety during an active write and must never be described that
way.

### BB-F02 — safe eject and complete uninstall

Remount once, use ntfsmac Unmount, wait for BB-P0-02, and only then physically eject the disk.
With no active mounts, exercise the in-popover Uninstall confirmation: cancel once, then confirm.
Pass when the UI reaches `Uninstalled`, the action cannot run twice, and these checks find no
helper/runtime:

```bash
sudo /bin/launchctl print system/com.khr898.ntfsmac.helper
/bin/ls /Library/LaunchDaemons/com.khr898.ntfsmac.helper.plist
/bin/ls /Library/PrivilegedHelperTools/com.khr898.ntfsmac.helper
/bin/ls /usr/local/ntfsmac
```

All four are expected to report absence after confirmed uninstall. The app bundle and its small
`UserDefaults` domain are separate user files; remove/reset them only if the goal is a truly blank
next-install test.

## Completion rule

- P3 can be marked packaged-validated after BB-02, BB-03, BB-P3-01 through BB-P3-04, and relevant
  teardown checks pass; a safely uninducible partial failure retains its automated evidence and is
  recorded explicitly.
- P0 hardware qualification closes only when VPN off/on, route transition, cross-surface truth,
  external teardown, crash/helper recovery, concurrent mounts, no-false-green, and cleanup cells
  pass on the release artifact.
- P1 packaged software acceptance requires BB-P1-00 through BB-P1-03. Hardware qualification
  closes only when media-cycle/Windows hashes and the same-device `ntfs-3g`/NTFS3 matrix pass,
  with the available OS/device/controller inventory stated honestly.
- P2 remains deferred regardless of these results.
