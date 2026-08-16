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
- Current installed candidate also includes mount-watchdog correction commit `3a3faab`; its
  bundled and staged watchdog hashes match, and the complete gates pass shell `294/294` and Swift
  `251/251`.
- Professional-DMG packaging candidate built on 2026-08-14 from the unchanged packaged app:
  SHA-256 `6c08067e431791b3e8be983c16c80f5a14a539c3b2a90c6ab30594f19b724b24`.
  `hdiutil verify` and strict app signature verification pass; the packaging source passes Bats
  `295/295`, Swift remains `251/251`, and the changed shell script passes ShellCheck.
- Source-only blocker correction commit `3c4f23a` was completed on 2026-08-15. Bats pass
  `297/297`; its original Swift gate passed `259/259`, including a clean vendored-component
  rebuild. It does not by itself change any acceptance-row status.
- The first installed BB-03 repeat of that candidate reached only Diagnose and Quit while Full
  Keyboard Access was active; Open, Unmount, the overflow menu, Refresh, Security Show, and
  Settings were skipped. BB-03 therefore remains `FAIL`. Follow-up source commit `864abd8` adds
  explicit focus participation to every interactive popover surface and passes Swift `260/260`;
  its DMG was built and verified from documentation head `2e0ae09` with SHA-256
  `bdfcd62b8a7070639a4476301461ca4f630d7b1ade5edfe150161c1e28292fed`.
- On 2026-08-16 the installed follow-up candidate passed forward and reverse Full Keyboard Access
  traversal for the exercised mounted popover and Settings surface: Open, Unmount, the drive
  overflow control, Refresh, Security Show/Hide, Settings/Back, Diagnose, and Quit all accepted
  focus. The native blue focus indicator was visible only as keyboard accessibility state. The
  subsequent Launch-at-login enable/readback/disable cycle also passed independently, closing
  BB-03.
- BB-01 clean-install preparation then passed: the in-app complete uninstall removed the CLI
  prefix/link, helper binary/plist/job, runtime cache/logs, NFS mounts, and VM/network processes.
  An authenticated check returned `BB-01-CLEAN: PASS` with no session-state files or PF child
  anchors. The still-running app bundle and its user preferences were deliberately retained, as
  specified by the uninstall UI. BB-01 remains `FAIL` until this same process quits, the app is
  replaced from the candidate DMG, and the first empty-cache mount succeeds without a relaunch.
- That clean replay then exposed a second first-run failure: the normal Mount control was visible
  before the helper had Full Disk Access. Clicking it opened the permission path, but enabling the
  helper did not resume the consumed Mount request. Source commit `33ce2af` now requires explicit
  helper-install consent, renders helper/CLI progress, performs a read-only one-block raw-device
  permission preflight, polls after System Settings opens, and hides Mount until access is proven.
  Its XPC protocol revision also forces replacement of an older helper with the same CLI payload.
  Bats `297/297` and Swift `269/269` pass; this is source evidence only until a rebuilt DMG repeats
  the clean first-run/mount/unmount/zero-state sequence.
- Candidate DMG SHA-256 `f02a2c0de0a635516e20928b2e69245f761fa4a1518010e637eac3938549c5e2`
  was built from documentation head `3ef125e`; the app passes strict deep signature verification
  and the image passes `hdiutil verify`. BB-01 remains `FAIL` until this artifact is installed and
  completes the consent, progress, FDA, first-Mount, unmount, and authenticated zero-state gates.
- The installed candidate then passed the consent/progress/FDA sequence and started a real ntfsmac
  NFS session on the first Mount click. Host truth identified `diskNsM.local:/mnt/...` over NFS;
  paired anylinuxfs truth identified the guest NTFS mount as `ro,norecover`. A scoped write was
  refused, proving the volume was not read/write. The GUI nevertheless stayed green after Refresh
  because it used only the host NFS client's writable option. GUI Unmount removed the host mount,
  runtime session, bridge, and public security session; no test payload was created. Commit
  `06dcd03` fixes the two-layer reconciliation and adds the exact rw-NFS/ro-guest regression case;
  the complete source gates pass at Bats `297/297` and Swift `270/270`. This is source evidence
  pending a rebuilt package and authenticated root teardown, so BB-01 remains `FAIL`.
- Corrected DMG SHA-256 `e9a5494c44e8fe68ea07a0cbef1afbf3880b1dc32c92edd1504d89164bafbdc5`
  was then built from documentation head `73d3d08` with source fix `06dcd03`. The app is arm64 and
  passes strict deep ad-hoc signature verification; the DMG passes `hdiutil verify`. This is the
  exact installed-test candidate, not a ledger PASS.
- The installed GUI executable matched that candidate byte-for-byte. Its first Mount click created
  `diskNsM.local:/mnt/...` over NFS with one enforced private security session while paired
  anylinuxfs status reported the guest as `ntfs,ro,norecover`. The corrected popover immediately
  showed yellow `Mounted read-only` plus concise Windows `chkdsk`/Fast Startup/full-shutdown
  guidance; it never published green. No write was attempted. GUI Unmount removed the host and
  guest mounts, lowered the bridge, and returned diagnostics/public evidence to zero sessions.
  The packaged read-only-truth sub-gate passes; authenticated PF/state teardown and a known-clean
  read/write round trip remain before BB-01 can pass.
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
| BB-01 | FAIL | Installed app, helper, bundled CLI, version/build and command surface were confirmed. Rebuilt commit `004e76e` exposed a root-owned cached `vmproxy` after its privileged update and failed. Replacement commit `db3aacf` then passed the affected upgrade: staging repaired that file to the invoking user without a manual ownership command; installed payload hashes match the candidate; ordinary and Microsoft-only backend scans both exited `0`; the popover visibly showed the same two NTFS rows as `diskutil`; and a full mount/unmount cycle preserved user ownership and enumeration. On 2026-08-14 the deliberately blank replay removed the helper, CLI/runtime, app and only the `com.khr898.ntfsmac` preferences after exporting a backup. Reinstalling DMG SHA-256 `d68a69a27e461fa28d6e88d284a1229b94e5dd00504ffe03106a6dc486a37da9` required the expected helper authorization once, then produced exactly one launchd plist/binary pair, healthy schema-6 diagnostics, CLI help containing `copy --verify`, `verify`, `diagnose`, and `opengui`, and matching GUI/diagnostic version `2.1` build `090826`. The first scan briefly showed no drives while helper startup settled, then converged without a second authorization to the authoritative mounted row. A later complete uninstall/reinstall exposed the untested empty-cache first-mount boundary: the helper set `HOME` and `SUDO_UID/GID` but not `USER`, so anylinuxfs `init-rootfs` failed before touching the NTFS volume with `user.Current requires cgo or $USER set in environment` and `backend_failed`. The fresh Settings view also exposed `Launch at login is unavailable for this app bundle`. Those source defects were corrected. Candidate `f02a2c…c5e2` then passed explicit helper consent, preparation, FDA unlock, and first-click session startup, but exposed a second truth defect: host NFS was rw while the guest NTFS was `ro,norecover`, yet the GUI stayed green and a write was refused. Commit `06dcd03` reconciles both layers and passes Swift `270/270`. Installed corrected candidate `e9a549…fbdc5` then presented the same rw-NFS/ro-guest fixture as yellow `Mounted read-only` with concise recovery guidance and clean diagnostic teardown. BB-01 remains FAIL only until a known-clean RW round trip and authenticated state/PF teardown pass. |
| BB-02 | PASS | The original package failed cold placement. Rebuilt commit `004e76e` passed cold and warm opening beneath the menu-bar icon, three simultaneous requests with exit `0`, exactly one GUI process, and invalid-argument exit `2` without another process or Accessibility permission. |
| BB-03 | PASS | Light/Dark presentation, warning/error truthfulness, minimal Settings/Back flow, and overflow-only secondary actions passed. The first keyboard repeat exposed incomplete focus traversal and the blank-install replay exposed unavailable Launch at login. Installed follow-up DMG `bdfcd6…92fed` then passed forward/reverse Full Keyboard Access traversal for every exercised mounted-popover and Settings control. Launch at login remained enabled after registration; macOS Background Task Management independently reported the `/Applications/ntfsmac.app` record as `enabled, allowed, notified`. After disabling it, the same record advanced generation and reported `disabled, allowed, notified`, while the privileged helper remained registered. Both corrected sub-gates therefore pass on 2026-08-16. |
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
| BB-P1-00 | PASS | The normal row remained Open/Unmount and exposed only Verified Copy in `…`. On rebuilt commit `3a3faab`, the exact 38-byte `gui-source.bin` opened a destination panel at the MobileData root; Cancel created no state, and a deliberate outside-volume destination was rejected with `Choose a destination inside this mounted drive` before any process or partial. Fresh `gui-small.bin` then published with the compact green `SHA-256 manifest matched. Destination published.` card and independently matched the source at `889d1118a6263150c0e7632dc569c6710c6b4e8a7f22d2d12674ee6c85eba2c4`. Repeating that destination produced NSSavePanel's standard Replace warning, but accepting it still reached ntfsmac's authoritative `The destination already exists. Verified Copy never overwrites it.` refusal; the hash remained unchanged and no partial appeared. This is safe, with the intermediate native Replace wording retained as a minor UX follow-up. A first 2 GiB active-copy attempt completed too quickly and independently matched; it was preserved as `gui-cancel-fast-success-2GiB.bin`. The required repeat used a fresh 16 GiB source: the active card exposed Cancel while Unmount, the other drive's Mount, Settings, and Quit were visibly disabled; Cancel stopped the isolated process group, preserved the 16 GiB source, left the final name absent, retained exactly one named recoverable partial (`.gui-cancel.bin.ntfsmac-partial.S6kZFS`), and returned an explicit interrupted result while mount/security remained healthy. The active and final screenshots are retained locally with SHA-256 values `7eb8a032f3576884953ad852825db2e71ced709bf7c660049d12195d90fecdab` and `a5bf0152032124ca57e464fc493ceec175463901f149f2fb8279853aefb01295`. |
| BB-P1-01 | PASS | 256 MiB copy and reread SHA-256 matched; overwrite was refused without hash change; a controlled mutation was detected. |
| BB-P1-02 | PASS | The original installed package retained a recoverable partial because destination-only AppleDouble metadata changed the manifest. Replacement commit `db3aacf` copied and published the same 505-entry nested/Unicode/symlink tree, then its installed CLI independently verified the destination manifest. The destination contained 1010 physical entries because of 505 AppleDouble sidecars, all correctly outside the byte-integrity contract without ignoring real source sidecars. |
| BB-P1-03 | PASS | The working-tree check and replacement commit `db3aacf` installed CLI both passed. The packaged copy was interrupted as one process group after a 25 MiB payload appeared, exited `130`, preserved the 4 GiB source, left the final name absent, and retained exactly one named partial for inspection. |
| BB-P1-04 | PASS | After the complete GUI/root teardown, the operator physically disconnected MobileData, waited, and reconnected it to the same port. The GUI remounted it RW with `ntfs-3g`; the installed CLI independently verified the existing 256 MiB destination manifest, and both fresh SHA-256 values matched at `54ca03f1af5eeb02ca7e562f93a33b2bb77ceaf62f035d51e40142dd330e12b5`. Diagnostics and the settled GUI security rows agreed on one enforced session. |
| BB-P1-05 | BLOCKED | On 2026-08-14 Windows mounted the same data volume and independently reread `BinaryBears-Acceptance-20260812-190259\copied-256MiB.bin`. PowerShell reported exactly 268435456 bytes and SHA-256 `54ca03f1af5eeb02ca7e562f93a33b2bb77ceaf62f035d51e40142dd330e12b5`, matching the retained Mac source and closing the cross-OS byte-integrity subcell. The controlled same-source/same-device/same-port TV playback comparison requires the external television and an operator-observed run; it was not performed in this checkpoint and is explicitly blocked rather than left in progress or inferred from the hash. |
| BB-P1-06 | FAIL | The 2026-08-14 same-device comparison used USB_8GB first with default `ntfs-3g`, then with explicit NTFS3 after the packaged preflight. Diagnostics proved the requested driver with no fallback and one enforced private session in both cases. A 256 MiB file matched SHA-256 `54ca03f1af5eeb02ca7e562f93a33b2bb77ceaf62f035d51e40142dd330e12b5`; 505 regular entries plus create, copy, overwrite, append, rename, move, delete, Unicode, safe unmount/remount, and post-remount verification passed under both drivers. The full 506-entry tree did not pass the portability gate: NTFS3 exposed an `ntfs-3g` symlink as a 46-byte regular `IntxLNK` file, while a fresh NTFS3 Verified Copy of that symlink failed with `Invalid argument`/`Operation timed out`. Verified Copy correctly withheld the final destination and retained exactly one recoverable partial, so no silent publication occurred. NTFS3 remains experimental and is not eligible to replace `ntfs-3g`; a focused preflight/error-message correction is required before this cell can pass. |
| BB-P1-07 | FAIL | Windows identified the disposable USB_8GB as healthy NTFS `H:`, 15930486784 bytes, MBR, on a Generic SD/MMC device. Before any state mutation, the operator copied both Mac driver test directories to `%USERPROFILE%\Desktop\BinaryBears-USB8GB-Backup-20260814`: `robocopy` retained 1024 files/258.02 MiB from the `ntfs-3g` run and 1026 files/258.03 MiB from the NTFS3 run with zero failed or skipped entries. Windows enumerated the `ntfs-3g` `film-link` payload as a regular 46-byte file, independently corroborating that the POSIX link representation is not portable as a Windows symlink. The fresh Windows clean-state matrix then created/copied/overwrote/appended/renamed/moved/deleted regular and Unicode test data in a new directory; its 268435456-byte copy matched SHA-256 `54ca03f1af5eeb02ca7e562f93a33b2bb77ceaf62f035d51e40142dd330e12b5`. Read-only CHKDSK processed 2176 file records and 2252 index entries, reported zero bad sectors and no problems/actions required, exited `0`, and `fsutil dirty query` reported `H:` not dirty with exit `0`. After the documented `USER` workaround initialized the empty cache, the current package mounted that exact state with default `ntfs-3g`, enforced private transport, and green GUI SECURITY. A fresh 256 MiB copy reached the expected size and regular/Unicode mutations were issued, but a subsequent access to the new `operations` directory failed with `Operation timed out`; the independent Mac SHA-256 reread could not complete, while the GUI remained green. The stop condition prevented the NTFS3 attempt and all further writes. Normal GUI Unmount then recovered to zero mounts/sessions/processes with the bridge down. Windows subsequently reread both the Windows source and Mac destination at exactly 268435456 bytes and the expected SHA-256, enumerated every retained regular/Unicode mutation, and again reported a clean non-dirty filesystem, zero bad sectors, and CHKDSK exit `0`. This proves payload integrity and isolates the failure to the NFS/backend path and fail-closed presentation rather than on-media corruption. Windows then deliberately set and confirmed the NTFS dirty bit before a safe eject. On macOS, explicit NTFS3 performed no fallback and no host mount; diagnostics retained `selected_fs_driver=ntfs3`, zero mounts/sessions, and bridge down, but the GUI exposed a long raw Linux mount transcript instead of deterministic dirty-volume guidance. Default `ntfs-3g` then mounted that same dirty volume read/write with one enforced private session and a green GUI. No payload write was issued; immediate GUI Unmount returned the host mount count and security sessions to zero with the bridge down. The authenticated post-test check passed with no security state files or PF child anchors. Back on Windows, the pre-repair dirty query still reported the volume dirty while read-only CHKDSK found no structural problem or bad sector. `chkdsk /F /X` exited `0`; the following dirty query reported clean, and a final read-only CHKDSK again found no problem with exit `0`. This closes the controlled dirty-bit creation/recovery observation without media damage. Windows power preflight then confirmed the volume still clean, hibernation available, and Fast Startup unavailable because current system policy disables it (`HiberbootEnabled=0`); the Fast Startup cell is therefore `BLOCKED (test configuration unavailable)` rather than altered or credited. Windows was then explicitly hibernated with the USB attached. macOS initially saw the external volume through its native read-only NTFS path, but after that mount was removed the packaged app mounted it read/write with explicit NTFS3. Diagnostics proved `selected_fs_driver=ntfs3`, one enforced session, and no fallback. No Finder access or payload write occurred; normal GUI Unmount returned to zero mounts/sessions with the bridge down and the device was safely ejected. The authenticated Mac teardown found no security state file or PF child anchor. After reconnecting the device before Windows resumed, the dirty query remained clean and read-only CHKDSK again reported no problem or bad sector with exit `0`. This demonstrates that Windows cleanly closed this removable data volume during hibernation; it did not create the required hibernated-NTFS fixture, so that subcell is also `BLOCKED (fixture not reproduced)`, not a qualification pass. The behavior remains unaccepted in the current package: NTFS3 needs a concise classified refusal, and the compatibility driver must not silently advertise read/write for a known unsafe state without an explicit policy and recovery path. The actual-filesystem-error state and clean Mac retest remain open. |
| BB-P1-08 | BLOCKED | The current pool covers two capacities, an MBR map, repeated large-file work, CLI/GUI cancellation, two concurrent drives, and VPN off/on. It does not provide a disposable GPT/low-space replay after the retained evidence, every supported macOS major release, a permission-sensitive Windows system volume, or a controlled set of additional controllers/cables. Those unavailable combinations remain explicit resource-blocked qualification cells; none is promoted to a pass from the single-host evidence. |
| BB-P3-01 | PASS | The original installed artifact targeted the observed mount but showed no Finder window. Replacement commit `db3aacf` visibly opened Finder windows titled MobileData and USB_8GB from their respective concurrently mounted rows while status independently reported `/Volumes/MobileData` and `/Volumes/USB_8GB`. |
| BB-P3-02 | PASS | Default-off state and absence of unsolicited permission requests passed. The first installed package exposed an authorization-callback race and empty foreground presentation options; commit `d99c4ac` corrects both and passes `292/292` shell plus `249/249` Swift tests, including the observed first-grant race. Its installed GUI exactly matched the strictly verified candidate app from DMG `c7bacbbec54a303f3ee2541da49a916b9668b8ac78c825151fb0fdce5c0a8905`. The rebuilt package scheduled mount, foreground unmount, and controlled-failure notifications with banner and sound options; macOS muted only their visible presentation because the display was shared during assisted control. The controlled failure retained one authoritative mount and enforced security session until normal recovery. With the app preference disabled, a successful mount/unmount cycle left the ntfsmac Notification Center request count unchanged at five. After the operator revoked system permission, reopening Settings reconciled the app toggle off and displayed actionable System Settings guidance instead of claiming enabled. |
| BB-P3-03 | PASS | With MobileData and USB_8GB mounted concurrently, diagnostics first proved two NFS mounts and two enforced security sessions. Eject All attempted both rows and presented two explicit `Unmounted` results. Both rows returned to detected, diagnostics settled to zero mounts/sessions with the bridge down, and the operator-authenticated check found no security state files or PF child anchors. |
| BB-P3-04 | PASS | The original packaged attempt exposed a security postcondition defect and led to the authoritative host-mount check in commit `3caf812`. The rebuilt installed package passed the repeat: a safe read-only working-directory hold left MobileData accessible and reported `Failed`, USB_8GB reported `Unmounted`, all mutating actions and Quit were disabled during the batch, and closing the report changed presentation only. Host truth and diagnostics agreed on one remaining NFS mount with one enforced security session throughout the hold. After release, MobileData's normal Unmount returned both rows to detected and diagnostics to healthy with zero mounts/sessions and the bridge down; the operator-authenticated check found no security state files or PF child anchors. |
| BB-P3-05 | PASS | The professional DMG retains the native drag-to-Applications model and the unchanged ad-hoc-signed app. Its Finder layout opens at 720×460 with two 112-point icons, deliberate app/Applications alignment, hidden chrome, a restrained neutral background and centered drag cue. Automated packaging tests verify the app, exact `/Applications` symlink, persisted `.DS_Store` background reference, hidden 720×460 PNG, and missing-app hard stop. The real compressed UDZO image passes `hdiutil verify`; the app passes strict deep signature verification; Light and Dark visual checks passed with the host's original Automatic appearance restored. Local screenshots remain outside Git. |
| BB-F01 | FAIL | On 2026-08-14 USB_8GB was mounted with default `ntfs-3g`; diagnostics proved one enforced private session, and the live gate proved vmnet/private/`soft` NFS with no loopback listener. With no copy/verify process or Finder use, the operator physically removed only that disposable device. `diskutil list external` then showed only MobileData, but after more than 36 seconds the host NFS mount, anylinuxfs VM, vmnet helper, security session, and green GUI `Mounted read/write` row all remained. The `soft` contract avoided a system hang, but bounded transition away from green and automatic teardown failed. Authorized GUI Unmount on the stale row immediately removed NFS, VM, bridge, and security state; one manual Refresh was then required to remove the cached disconnected drive row. Recovery is therefore available but not automatic, and must be retested after a focused physical-device-presence reconciliation fix. |
| BB-F02 | PASS | On 2026-08-14 USB_8GB was remounted once with default `ntfs-3g`; the host NFS table, schema-6 diagnostics, GUI SECURITY rows, and the live transport gate agreed on one private vmnet/`soft` session with evaluated PF. GUI Unmount returned to zero mounts/sessions with the bridge down, then `diskutil eject /dev/disk4` succeeded and the physical disk disappeared from authoritative enumeration. The app retained its cached unmounted row after the logical eject and manual Refresh; that presentation defect is already covered by BB-F01 and did not leave backend state. In Settings, cancelling the complete-uninstall confirmation preserved the service, plist, helper, and CLI/runtime. Confirming it then reached `Uninstalled`, disabled the action against a second run, and removed the launchd service, `/Library/LaunchDaemons/com.khr898.ntfsmac.helper.plist`, `/Library/PrivilegedHelperTools/com.khr898.ntfsmac.helper`, and `/usr/local/ntfsmac`. No ntfsmac NFS mount, VM/network-helper process, or session-state file remained. The root-owned public diagnostics retained only privacy-safe zero-session/`NO_ACTIVE_MOUNTS` state; the app bundle and user preferences remain the separately removable user-level files described by the confirmation UI. The final operator-authenticated check found no security state files or PF child anchors. |

## Pause checkpoint — 2026-08-13

Validation is intentionally paused after closing packaged BB-P1-00. The implementation under test
is integrated in local `dev`; validation documentation is complete through commit `9959939` before
this checkpoint commit. No push was performed.

Closed on this host:

- BB-00, BB-02, every BB-P0 cell, BB-P1-00 through BB-P1-04, and every BB-P3 cell are `PASS`;
- Verified Copy now has packaged evidence for picker Cancel, volume-boundary refusal, successful
  publication, no-overwrite behavior, and active cancellation with a recoverable partial;
- the installed mount remains truthful and healthy after the cancelled 16 GiB copy.

Exact paused host state:

- MobileData (`disk6s1`) is the sole ntfsmac NFS mount, using `ntfs-3g`; diagnostics report one
  enforced security session, private vmnet transport, evaluated PF, the VPN default still active,
  and no copy/mount/unmount command in flight;
- the 16 GiB local source remains intact, the requested final `gui-cancel.bin` is absent, and the
  single recoverable `.gui-cancel.bin.ntfsmac-partial.S6kZFS` is intentionally retained on
  MobileData as evidence;
- USB_8GB (`disk7s1`) is not mounted by ntfsmac. macOS currently exposes it separately as a native
  read-only NTFS/FsKit mount at `/Volumes/USB_8GB`; do not confuse that with a tested ntfsmac
  driver session.

Results after resuming this checkpoint:

1. BB-P1-06 completed as `FAIL`: regular payload and mutation behavior passed under both drivers,
   but NTFS3 did not preserve the `ntfs-3g` symlink contract.
2. BB-03 completed as `FAIL`: Dark appearance and warning/error presentation passed, while
   keyboard traversal and fresh-install Launch at login availability failed and require fixes.
3. BB-F01 completed as `FAIL`: a no-I/O hot-unplug remained falsely green and retained backend
   state until manual recovery.
4. BB-01 is `FAIL`: install metadata and helper registration passed, but the later empty-cache first
   mount exposed a missing helper `USER` environment variable and failed before filesystem access.
5. BB-F02 completed as `PASS`: safe unmount/eject and cancel-then-confirm uninstall passed, with
   no helper, CLI/runtime, mount, VM, network-helper, session state, or PF child anchor left active.

After those Mac-local cells, Windows passed the BB-P1-05 independent hash subcell, but its controlled
TV comparison is `BLOCKED` on external operator-observed playback. BB-P1-07 has independent
clean-state Windows creation/reread evidence plus the intentionally dirty-volume observation on
macOS and remains `FAIL` pending focused corrections. BB-P1-08 is `BLOCKED` on unavailable
device/OS/GPT/low-space/system-volume resources. The live 240-second watchdog expiry also remains
unmeasured because the stalled condition did not recur.

## Validation closure checkpoint — 2026-08-14

No acceptance row remains `IN PROGRESS`. Of the 30 rows now defined by the runbook, 23 are `PASS`,
five are measured `FAIL`, and two are resource `BLOCKED`:

- failures: BB-01, BB-03, BB-P1-06, BB-P1-07, and BB-F01;
- blocked: BB-P1-05 controlled TV playback and the unavailable BB-P1-08 extended matrix;
- Fast Startup and a genuinely hibernated removable NTFS fixture are recorded inside BB-P1-07 as
  blocked subcells, while its observed dirty-volume policy/presentation remains a failure.

BB-P3-05 is the added passing professional-DMG cell. The local evidence directory and
disposable-volume contents remain outside Git. Public documents
retain only generalized device roles, reproducible sizes/hashes, privacy-safe reason codes, and
generic paths. The professional DMG was the only implementation authorized for this checkpoint and
is now complete. Every mount/helper/driver/GUI correction listed above remains deliberately
deferred and must be implemented and packaged in focused later changes.

## Post-correction checkpoint — 2026-08-16

BB-03 is now `PASS` on the installed `bdfcd6…92fed` candidate. The live ledger therefore contains
24 `PASS`, four measured `FAIL`, and two resource `BLOCKED` rows. Remaining failures are BB-01,
BB-P1-06, BB-P1-07, and BB-F01; the blocked rows remain BB-P1-05 controlled TV playback and the
BB-P1-08 extended resource matrix.

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
affected packaged upgrade on 2026-08-13: the cache file became owned by the invoking user and group, both backend list
modes returned both NTFS partitions with exit `0`, diagnostics were healthy with zero mounts or
security sessions, and the popover visibly reported `2 drive(s) detected` with the correct device,
label, size, and unmounted controls. The subsequent mount/unmount cycle preserved both enumeration
and ownership. The deliberately blank install passed its install-only checks on 2026-08-14, but the
later empty-cache first mount reopened BB-01 with the missing helper `USER` environment failure.

## Deferred correction checkpoints

1. Fix the helper invoker environment (`USER`/`LOGNAME`) and repeat a packaged, empty-cache first
   mount before reconsidering BB-01.
2. Reconcile physical-device presence and backend I/O failure into authoritative fail-closed GUI
   state, automatic security teardown, and stale-row removal; repeat BB-F01 and the BB-P1-07 clean
   timeout sequence.
3. Add deterministic dirty-volume policy/classification for both drivers, plus concise Windows-only
   recovery guidance; repeat the dirty subcell without payload writes.
4. Add NTFS3 symlink preflight/specific failure copy, then repeat BB-P1-06 on the same device.
5. Correct BB-03 keyboard traversal and packaged Launch at login availability.
6. Retain NSSavePanel's no-overwrite safety while replacing the misleading intermediate native
   `Replace` wording in a separate focused Verified Copy UX change.
7. Resume BB-P1-05/BB-P1-08 only when the external TV and missing test resources are available.

## Source correction ready for packaged retest — 2026-08-15

Commit `3c4f23a` implements the six deferred software corrections: complete helper invoking-user
environment; physical-presence and bounded backend-liveness reconciliation; fail-closed
`ntfs-3g norecover` dirty policy and concise Windows recovery copy; NTFS3 root/nested-symlink
preflight; initial keyboard focus plus actionable fresh Launch-at-login registration; and native
save-panel validation before an existing destination can offer Replace. Installed evidence then
showed that the keyboard correction covered only Diagnose and Quit. Commit `864abd8` completes the
focus path across the main, Settings, first-run/repair, diagnostics, and Verified Copy surfaces.

The five ledger failures remain unchanged until a new DMG passes the exact repeat. The next run
must record the new artifact hash/signature first, then execute BB-01, BB-03, BB-P1-06, BB-P1-07,
and BB-F01 in that order. No operator name, home path, device serial, local evidence path, Apple ID,
or signing secret belongs in this public document.

The first `db3aacf` Mount attempt paused at the expected macOS privacy boundary: System Settings
showed exactly `com.khr898.ntfsmac.helper` with Full Disk Access off after helper replacement.
ChatGPT, Codex Computer Use, and Terminal remained off. The application did not create a backend
session or mount and did not misreport success.

After the operator enabled that entry, the mounted candidate passed all non-root BB-P0-01 checks.
The operator then ran the root gate with explicit authentication; it passed with one session,
evaluated PF, a private route, and owned teardown state. No password was requested or captured by
the automated checks.
