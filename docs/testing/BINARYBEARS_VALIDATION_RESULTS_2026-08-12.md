# BinaryBears packaged validation results — 2026-08-12

This is the live ledger for the assisted acceptance run defined in
[`BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md`](BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md).
`IN PROGRESS` is an interim marker only: the completion rule still accepts only observed `PASS`,
`FAIL`, `BLOCKED`, or `NOT RUN` results.

## Candidate and evidence boundary

- Installed artifact under test: commit `f1152f110477ee8e1eb98f03049176917542ee40`, release
  `2.1`, build `090826`, arm64, ad-hoc signed.
- Rebuilt artifact under retest: commit `004e76ee38c93e5a591c14f2cf965db56c06b64e`, release
  `2.1`, build `090826`, arm64, ad-hoc signed. The installed GUI executable SHA-256 matches the
  freshly built `dist/ntfsmac.app` executable.
- Runtime-cache replacement candidate installed on 2026-08-13: commit
  `db3aacf214085034942493739645d77658b0c532`, release `2.1`, build `090826`, arm64, ad-hoc
  signed. Installed GUI, bundled installer, and bundled anylinuxfs hashes match `dist/ntfsmac.app`;
  the staged `/usr/local` anylinuxfs also matches. DMG SHA-256 is
  `419235670feb5b6d0c3ad19328c6ba415f1efb2386db818300bbc872dc501e48`, and `hdiutil verify`
  passes.
- Current installed GUI candidate includes notification correction commit `d99c4ac`, release `2.1`,
  build `090826`, arm64, ad-hoc signed. Its installed GUI executable matches the verified app from
  DMG SHA-256 `c7bacbbec54a303f3ee2541da49a916b9668b8ac78c825151fb0fdce5c0a8905`.
- Host: Apple Silicon with Hypervisor support, macOS 26.6.1.
- Local evidence folder: `ntfsmac-acceptance-20260812-190259` on the operator's Desktop. It is
  intentionally not committed because it contains local volume/device identifiers.
- Rebuilt-artifact evidence folder: `ntfsmac-acceptance-rebuild-20260812-201045` on the operator's
  Desktop, kept under the same local-only privacy boundary.
- Drive A: one disposable MBR NTFS volume mounted by ntfsmac with the default `ntfs-3g` driver.
- Drive B was initially observed as FAT32 and was later independently prepared as a disposable
  MBR NTFS volume. It is now eligible for the two-drive cells after the rebuilt app is installed.
- Source fixes made after a packaged failure are recorded separately from the installed artifact.
  They do not convert that artifact's result into a pass; a rebuilt package must be retested.
- After Full Disk Access was enabled, macOS still enumerated both NTFS partitions but the rebuilt
  app showed no drives. The installed unprivileged `anylinuxfs list` failed before enumeration
  because an older privileged runtime update had left the cached guest `vmproxy` root-owned. This
  is a packaged upgrade regression, not missing hardware or a filesystem change.

## Ledger

| ID | Status | Evidence observed / remaining gate |
| --- | --- | --- |
| BB-00 | PASS | Exact artifact recorded; app signature, DMG verification, arm64, host and Hypervisor checks passed. |
| BB-01 | IN PROGRESS | Installed app, helper, bundled CLI, version/build and command surface were confirmed. Rebuilt commit `004e76e` exposed a root-owned cached `vmproxy` after its privileged update and failed. Replacement commit `db3aacf` then passed the affected upgrade: staging repaired that file to the invoking user without a manual ownership command; installed payload hashes match the candidate; ordinary and Microsoft-only backend scans both exited `0`; the popover visibly showed the same two NTFS rows as `diskutil`; and a full mount/unmount cycle preserved user ownership and enumeration. A deliberately blank clean-install replay remains. |
| BB-02 | PASS | The original package failed cold placement. Rebuilt commit `004e76e` passed cold and warm opening beneath the menu-bar icon, three simultaneous requests with exit `0`, exactly one GUI process, and invalid-argument exit `2` without another process or Accessibility permission. |
| BB-03 | IN PROGRESS | Mounted/Settings/Diagnostics light UI, Back, overflow-only copy action and Launch at login enable/disable passed. The cold-placement failure is tracked in BB-02; dark, full keyboard and safe warning/error states remain. |
| BB-P0-01 | PASS | The original package passed the default `ntfs-3g` RW round trip, diagnostic truth, vmnet/private/soft transport gate and root security transaction gate with one real session. Replacement commit `db3aacf` first stopped fail-closed while its replaced helper's Full Disk Access toggle was off. After the operator enabled exactly that entry, the GUI mounted MobileData RW with `ntfs-3g`; GUI, anylinuxfs status, host NFS table, diagnostic schema 6, and public security summary agreed on one mount/session with private vmnet, `soft` transport, PF evaluated, and no required route. A fixed-name write/reread SHA-256 round trip and exact test-artifact cleanup passed; both the live NFS transport gate and operator-authenticated root security transaction gate passed, followed by the complete BB-P0-02 teardown. |
| BB-P0-02 | PASS | The original and replacement candidates both returned the GUI to two detected drives with empty NFS mounts and anylinuxfs sessions; replacement diagnostics reported bridge down, no network helper, and zero security sessions while both backend enumeration and cache ownership remained healthy. The operator-authenticated replacement check confirmed no session state files and no PF child anchors. |
| BB-P0-03 | PASS | With the operator's VPN active and its local-network sharing disabled, diagnostics recorded the VPN default route before mount. The current packaged GUI mounted MobileData RW with default `ntfs-3g`; the fixed-name write/reread round trip passed, diagnostics remained healthy with one enforced session, and the privacy-safe transport gate passed one private vmnet/soft mount with no loopback listener. The NFS mount table independently showed `soft`. The VPN default remained on its original tunnel while ntfsmac added only its private bridge state; GUI SECURITY, schema 6, and the operator-authenticated transaction gate agreed on private-link/PF enforcement and an already-private route. |
| BB-P0-04 | PASS | With no copy active and the same RW mount preserved, the operator disabled only the VPN. Before and after manual Refresh, the GUI remained truthfully green; diagnostics changed `vpn_default_route` to false while retaining one enforced session, the ordinary Wi-Fi default returned, the fixed-name file reread passed, and both transport and operator-authenticated security gates passed. The operator then restored the same VPN configuration: its tunnel default returned, GUI state remained truthful automatically and after Refresh, the file reread and transport gate passed again, and a final authenticated transaction gate passed. The scoped test file was removed before GUI Unmount. Teardown left two detected devices, zero host mounts/sessions, the bridge down, the VPN default preserved, public evidence at `root:daemon 0644`, and the root check found no state files or PF child anchors. |
| BB-P0-05 | PASS | On the current notification-fix package, a GUI-created MobileData mount was independently proven by the host NFS table and diagnostic schema 6 with one enforced security session. Installed-CLI Unmount then returned success; without Refresh the running GUI converged to two detected rows in under one second, and diagnostics settled healthy with zero mounts/sessions and the bridge down. Repeating GUI mount -> CLI unmount followed by immediate Refresh preserved the same truthful idle state. The operator-authenticated installed CLI then mounted disk6s1 with enforced security while the app process remained open; the menu-bar popover naturally closed when Terminal gained focus, and reopening it showed the discovered MobileData RW state. Its Open action opened the exact Finder window `MobileData`; its Unmount action returned to healthy zero state. A final authenticated CLI mount followed by immediate GUI Refresh again showed disk6s1 RW with all three measured SECURITY rows truthful; final GUI Unmount left zero mounts/sessions and the bridge down. |
| BB-P0-06 | PASS | On the current installed package, MobileData was mounted RW with one measured/enforced security session and opened in Finder. Codex then selected the eject control for the synthetic `disk6s1.local` network share, not the physical USB device. At the first post-disconnect observation the host NFS table was empty, diagnostics were healthy with zero mounts/sessions and the bridge down, and the running GUI showed two detected devices with no green mount state. The package repeated the same behavior after the operator ran authenticated `/sbin/umount /Volumes/MobileData`: without Refresh, GUI and diagnostics again converged to two detected devices, zero NFS mounts/sessions, and bridge down. The final operator-authenticated inspection passed with no security state files or PF child anchors. |
| BB-P0-07 | PASS | On both tested candidates, terminating only the GUI preserved the real mount; `opengui` relaunched exactly one process, and the visible popover recovered the RW/security state. Replacement commit `db3aacf` repeated this after native-panel automation lost its accessibility bridge, then its normal GUI Unmount returned to both detected rows and passed the non-root BB-P0-02 cleanup. |
| BB-P0-08 | PASS | With no active mount, the operator successfully restarted the exact `system/com.khr898.ntfsmac.helper` job. Read-only launchd/process inspection found one running job record, one helper process (`pid 34218`), and the expected single plist/binary pair; diagnostics remained healthy at zero state. Without reinstalling or reauthorizing the helper, the first GUI mount reached verified MobileData RW with one enforced security session and the same sole helper process. Its first GUI Unmount returned diagnostics to healthy zero mounts/sessions with the bridge down, while exactly one helper process remained. |
| BB-P0-09 | PASS | Replacement commit `db3aacf` mounted MobileData and USB_8GB concurrently as two independent RW `ntfs-3g` rows, NFS mounts, VM sessions, and security sessions. A fixed-name write/reread SHA-256 round trip passed on USB_8GB. Unmounting only USB_8GB reduced diagnostics from two mounts/sessions to one while MobileData remained RW, enforced, and its 256 MiB payload independently verified. |
| BB-P0-10 | PASS | With MobileData mounted RW and one enforced security session, the operator reversibly changed only `/var/run/ntfsmac/security-status` from `root:daemon 0644` to `0666`. Before any manual Refresh, the periodic reconciliation changed all three GUI SECURITY rows from green to `unknown` with `STATUS_UNAVAILABLE`; CLI schema 6 simultaneously reported `healthy=false`, `security_active_sessions=null`, and the same unknown reasons while the real NFS mount remained present. Refresh preserved that fail-closed state. Restoring `0644` recovered all three measured GUI rows automatically before Refresh, and CLI diagnostics returned to `healthy=true` with one enforced session. Final GUI Unmount left diagnostics healthy with zero mounts/sessions, the bridge down, an empty matching host mount table, and the public file still `root:daemon 0644`. |
| BB-P1-00 | IN PROGRESS | The normal row remains Open/Unmount and exposes only Verified Copy in `…`. During replacement-candidate automation, the native source panel visually selected `gui-source.bin` but dispatched its parent `fixtures` directory, so that run is invalid rather than a product pass/fail; its isolated partial was stopped without damaging mount/security. The prior package later left a new GUI mount in pre-mount vmnet startup for about 150 seconds with no NFS mount or security session; scoped recovery returned to canonical zero state without disturbing the VPN. Rebuilt commit `3a3faab` was then installed, its bundled and staged watchdog hashes matched, and its first retry mounted MobileData RW with `ntfs-3g`, vmnet, evaluated PF, and one enforced security session after the expected Full Disk Access reauthorization. The live 240-second expiry did not recur naturally and remains unmeasured. On that rebuilt mount, human selection produced the exact 38-byte `gui-source.bin`; its destination panel began at the exact MobileData root with the expected name, and Cancel returned to the unchanged mounted row without creating a final or partial item. A deliberate destination in the local evidence folder was then rejected with the exact compact message `Choose a destination inside this mounted drive`; no final, partial, or copy process appeared, and the mount/security state remained enforced. Screenshot `BB-P1-00-outside-volume-refusal.png` is retained in the local-only evidence folder with SHA-256 `88c86b6c20d92a233e9804796edb7ce566e6b539dfb6cdb963004a264186ee90`. A fresh in-volume `gui-small.bin` was subsequently published at 38 bytes with no retained partial; its independent reread SHA-256 matched the source at `889d1118a6263150c0e7632dc569c6710c6b4e8a7f22d2d12674ee6c85eba2c4`, diagnostics remained healthy with one enforced session, and the final compact green card visibly reported `SHA-256 manifest matched. Destination published.` Repeating the same destination made NSSavePanel show its standard Replace warning; accepting that warning did not overwrite anything because ntfsmac then rejected the selection with `The destination already exists. Verified Copy never overwrites it.` The destination hash remained identical and no partial appeared. The behavior is safe, but the native intermediate Replace wording is a minor UX inconsistency to consider after qualification. Success/warning/refusal screenshots are retained locally with SHA-256 values `2da60a0f9618a911abf2386157e4eb743f08eb57fc7fa3b07781e8dba7c5f799`, `e5bb00761b54ebfbf7d7ae052602f7490e935e4b5e7daeccdfa697f091060605`, and `b33ef02ed1c8be12699d892f7fc3e4f8778548fbba7032cd60e7a9279c2eef92`. The first active-cancel attempt used a 2 GiB source: an isolated copy group and hidden partial were observed, but it completed before UI automation regained the popover. The independently reread source/destination hashes matched at `a7c744c13cc101ed66c29f672f92455547889cc586ce6d44fe76ae824958ea51`; that successful artifact was preserved as `gui-cancel-fast-success-2GiB.bin`, and a fresh 16 GiB source was prepared after rechecking free space for the required active Cancel repeat. |
| BB-P1-01 | PASS | 256 MiB copy and reread SHA-256 matched; overwrite was refused without hash change; a controlled mutation was detected. |
| BB-P1-02 | PASS | The original installed package retained a recoverable partial because destination-only AppleDouble metadata changed the manifest. Replacement commit `db3aacf` copied and published the same 505-entry nested/Unicode/symlink tree, then its installed CLI independently verified the destination manifest. The destination contained 1010 physical entries because of 505 AppleDouble sidecars, all correctly outside the byte-integrity contract without ignoring real source sidecars. |
| BB-P1-03 | PASS | The working-tree check and replacement commit `db3aacf` installed CLI both passed. The packaged copy was interrupted as one process group after a 25 MiB payload appeared, exited `130`, preserved the 4 GiB source, left the final name absent, and retained exactly one named partial for inspection. |
| BB-P1-04 | PASS | After the complete GUI/root teardown, the operator physically disconnected MobileData, waited, and reconnected it to the same port. The GUI remounted it RW with `ntfs-3g`; the installed CLI independently verified the existing 256 MiB destination manifest, and both fresh SHA-256 values matched at `54ca03f1af5eeb02ca7e562f93a33b2bb77ceaf62f035d51e40142dd330e12b5`. Diagnostics and the settled GUI security rows agreed on one enforced session. |
| BB-P1-05 | BLOCKED | Windows-side hash/playback comparison requires Windows and the same media. |
| BB-P1-06 | NOT RUN | Same-device explicit NTFS3 comparison remains. |
| BB-P1-07 | BLOCKED | Requires Windows-prepared clean/dirty/Fast Startup/error states. |
| BB-P1-08 | IN PROGRESS | One MBR device and interrupted/normal workloads recorded; the broader device/controller/OS/low-space inventory remains. |
| BB-P3-01 | PASS | The original installed artifact targeted the observed mount but showed no Finder window. Replacement commit `db3aacf` visibly opened Finder windows titled MobileData and USB_8GB from their respective concurrently mounted rows while status independently reported `/Volumes/MobileData` and `/Volumes/USB_8GB`. |
| BB-P3-02 | PASS | Default-off state and absence of unsolicited permission requests passed. The first installed package exposed an authorization-callback race and empty foreground presentation options; commit `d99c4ac` corrects both and passes `292/292` shell plus `249/249` Swift tests, including the observed first-grant race. Its installed GUI exactly matched the strictly verified candidate app from DMG `c7bacbbec54a303f3ee2541da49a916b9668b8ac78c825151fb0fdce5c0a8905`. The rebuilt package scheduled mount, foreground unmount, and controlled-failure notifications with banner and sound options; macOS muted only their visible presentation because the display was shared during assisted control. The controlled failure retained one authoritative mount and enforced security session until normal recovery. With the app preference disabled, a successful mount/unmount cycle left the ntfsmac Notification Center request count unchanged at five. After the operator revoked system permission, reopening Settings reconciled the app toggle off and displayed actionable System Settings guidance instead of claiming enabled. |
| BB-P3-03 | PASS | With MobileData and USB_8GB mounted concurrently, diagnostics first proved two NFS mounts and two enforced security sessions. Eject All attempted both rows and presented two explicit `Unmounted` results. Both rows returned to detected, diagnostics settled to zero mounts/sessions with the bridge down, and the operator-authenticated check found no security state files or PF child anchors. |
| BB-P3-04 | PASS | The original packaged attempt exposed a security postcondition defect and led to the authoritative host-mount check in commit `3caf812`. The rebuilt installed package passed the repeat: a safe read-only working-directory hold left MobileData accessible and reported `Failed`, USB_8GB reported `Unmounted`, all mutating actions and Quit were disabled during the batch, and closing the report changed presentation only. Host truth and diagnostics agreed on one remaining NFS mount with one enforced security session throughout the hold. After release, MobileData's normal Unmount returned both rows to detected and diagnostics to healthy with zero mounts/sessions and the bridge down; the operator-authenticated check found no security state files or PF child anchors. |
| BB-F01 | NOT RUN | No-I/O physical hot-unplug is intentionally near the end. |
| BB-F02 | NOT RUN | Final safe eject and uninstall are intentionally last. |

## Findings corrected in the working tree

### Mount watchdog descendant cleanup and timeout evidence

The current package already has a 240-second mount watchdog with 15-second progress heartbeats;
the assisted recovery above occurred before that bound expired, so it does not prove the packaged
watchdog itself failed. Source inspection did expose a narrower cleanup gap: the watchdog signalled
only its direct child, while anylinuxfs may create a VM supervisor and vmnet-helper in another
process group. The watchdog now snapshots the complete descendant tree before signalling it,
terminates the parent and every recorded descendant, and escalates surviving members after the
grace period. A timeout publishes the fixed privacy-safe `backend_timeout` diagnostic category,
and the minimal GUI replaces accumulated backend heartbeat text with one concise recovery message.

Focused shell coverage passes `36/36`, including a descendant that ignores `TERM`; the complete
gates pass shell `294/294` and Swift `251/251`. Installed commit `3a3faab` has matching bundled and
staged watchdog hashes and its first post-authorization retry mounted successfully with the expected
private transport and security state. The live 240-second expiry did not recur naturally, so expiry
cleanup remains unmeasured rather than being retroactively credited to either the earlier assisted
recovery or this successful retry.

### P1 directory verification and AppleDouble metadata

macOS stored excluded `com.apple.provenance` metadata as valid `._*` AppleDouble files on the
NFS-backed NTFS destination, including when `cp` received its no-xattr option. The verifier now
omits only a destination-only sidecar when it has AppleDouble magic, has a paired destination
entry, and has no same-path source entry. A real source file named `._something` remains in the
manifest and is verified byte-for-byte.

Focused Bats coverage passes `8/8`. The corrected working-tree CLI also passed the original live
tree: 505 source entries, nested paths, Unicode, 500 small files and a relative symlink. The 505
physical metadata sidecars remained on the filesystem but were correctly outside the documented
byte-integrity contract. Replacement commit `db3aacf` repeated that exact live case from the
installed package on 2026-08-13: copy/publish and a separate `verify` both passed, with 505 logical
source entries and 1010 physical destination entries including the expected 505 sidecars.

After the copy/Finder corrections, the complete automated gates passed Swift `245/245` and Bats
`286/286`. After the popover correction, Swift passes `247/247` and the focused `opengui` Bats
suite passes `4/4`; the shell implementation did not change. After the runtime-cache ownership
correction, the full source gates pass Swift `247/247`, Bats `289/289`, shellcheck at warning
severity, and a complete real runtime build including `41/41` anylinuxfs, `8/8` common-utils, and
`8/8` vmproxy Rust tests. These prove the source tree, not the still-installed pre-fix artifact.

### P3 Finder presentation

The installed app's generic Launch Services open returned success for the NFS path without
presenting a Finder window. The working tree now requests an exact Finder reveal first and uses
`/usr/bin/open` only as a fallback. Replacement commit `db3aacf` visibly opened the correct
MobileData and USB_8GB Finder windows from their respective concurrently mounted rows on
2026-08-13, completing the two-drive cell.

### Cold `opengui` popover anchoring

The original app recovered the surviving mount and displayed truthful controls after a forced GUI
restart, but AppKit placed the popover at the lower-left of the screen. The menu-bar button existed
before its hosting window had usable screen geometry, so the first cold URL request presented too
early. The fix coalesces requests and waits, for at most two seconds, until the button has non-zero
bounds and a real on-screen menu-bar position. A close or teardown cancels the wait; no fallback
detached window and no additional UI were added. Unit tests reject the observed lower-left geometry
and accept primary and secondary-display menu-bar anchors. Rebuilt commit `004e76e` passed the full
cold, warm, rapid, single-instance, invalid-argument, and no-Accessibility packaged check.

### Runtime cache ownership after privileged updates

After the helper permission was enabled, `diskutil` still reported both disposable MBR NTFS
partitions while the popover reported no drives. Both Microsoft and unfiltered backend list probes
failed with `Permission denied` while replacing the pinned runtime's cached `rootfs/vmproxy`.
Directory ownership was already the invoking user's; only that file was `root:wheel`, proving the
failure came from the privileged replacement path rather than USB discovery.

The source correction has two layers. The bundled installer safely repairs only regular
non-symlink `rootfs/vmproxy` cache entries using the XPC peer's kernel-derived UID/GID, allowing
an affected upgrade to self-heal without a manual `chown`. The scratch-built anylinuxfs update
path now restores the same invoker ownership immediately after a privileged replacement while
retaining the guest-visible root ownership metadata. The pinned submodule is unchanged: the build
patch applies only to its disposable source copy and hard-stops if the upstream shape drifts.

Focused installer tests prove repair and symlink refusal; build tests prove one idempotent ownership
patch; the complete build and regression suites pass. Replacement commit `db3aacf` passed the
affected packaged upgrade on 2026-08-13: the cache file became `andrea:staff`, both backend list
modes returned both NTFS partitions with exit `0`, diagnostics were healthy with zero mounts or
security sessions, and the popover visibly reported `2 drive(s) detected` with the correct device,
label, size, and unmounted controls. The subsequent mount/unmount cycle preserved both enumeration
and ownership. Only the deliberately blank install remains before BB-01 closes.

## Next operator checkpoints

1. Retest the remaining GUI P1 and P3 two-drive cells.
2. Perform only the requested VPN, Windows and final-uninstall actions.

The first `db3aacf` Mount attempt paused at the expected macOS privacy boundary: System Settings
showed exactly `com.khr898.ntfsmac.helper` with Full Disk Access off after helper replacement.
ChatGPT, Codex Computer Use, and Terminal remained off. The application did not create a backend
session or mount and did not misreport success.

After the operator enabled that entry, the mounted candidate passed all non-root BB-P0-01 checks.
The operator then ran the root gate with explicit authentication; it passed with one session,
evaluated PF, a private route, and owned teardown state. No password was requested or captured by
the automated checks.
