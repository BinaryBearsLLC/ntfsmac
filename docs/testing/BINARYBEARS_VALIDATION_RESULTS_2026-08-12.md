# BinaryBears packaged validation results — 2026-08-12

This is the live ledger for the assisted acceptance run defined in
[`BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md`](BINARYBEARS_MANUAL_ACCEPTANCE_2026-08-12.md).
`IN PROGRESS` is an interim marker only: the completion rule still accepts only observed `PASS`,
`FAIL`, `BLOCKED`, or `NOT RUN` results.

## Candidate and evidence boundary

- Installed artifact under test: commit `f1152f110477ee8e1eb98f03049176917542ee40`, release
  `2.1`, build `090826`, arm64, ad-hoc signed.
- Host: Apple Silicon with Hypervisor support, macOS 26.6.1.
- Local evidence folder: `ntfsmac-acceptance-20260812-190259` on the operator's Desktop. It is
  intentionally not committed because it contains local volume/device identifiers.
- Drive A: one disposable MBR NTFS volume mounted by ntfsmac with the default `ntfs-3g` driver.
- Drive B was initially observed as FAT32 and was later independently prepared as a disposable
  MBR NTFS volume. It is now eligible for the two-drive cells after the rebuilt app is installed.
- Source fixes made after a packaged failure are recorded separately from the installed artifact.
  They do not convert that artifact's result into a pass; a rebuilt package must be retested.

## Ledger

| ID | Status | Evidence observed / remaining gate |
| --- | --- | --- |
| BB-00 | PASS | Exact artifact recorded; app signature, DMG verification, arm64, host and Hypervisor checks passed. |
| BB-01 | IN PROGRESS | Installed app, helper, bundled CLI, version/build and command surface confirmed. A deliberately blank clean-install replay remains. |
| BB-02 | FAIL | Warm open, three rapid requests, single-instance behavior and invalid-argument exit `2` passed. On cold recovery the installed app opened the correct compact popover at the lower-left of the screen instead of beneath its menu-bar icon. Source fix and rebuilt-package retest required. |
| BB-03 | IN PROGRESS | Mounted/Settings/Diagnostics light UI, Back, overflow-only copy action and Launch at login enable/disable passed. The cold-placement failure is tracked in BB-02; dark, full keyboard and safe warning/error states remain. |
| BB-P0-01 | PASS | Default `ntfs-3g` RW round trip, diagnostic truth, the vmnet/private/soft transport gate and the root security transaction gate all passed with one real session. |
| BB-P0-02 | PASS | GUI returned to two detected drives; NFS mounts and anylinuxfs sessions were empty; diagnostics reported bridge down and zero security sessions; the root check found no session state file or PF child anchor. |
| BB-P0-03 | NOT RUN | VPN-on mount requires the operator's VPN transition. |
| BB-P0-04 | NOT RUN | Mounted VPN route transition requires the operator. |
| BB-P0-05 | NOT RUN | Cross-surface mount/unmount matrix remains. |
| BB-P0-06 | NOT RUN | External NFS disconnect remains. |
| BB-P0-07 | PASS | Force-quitting only the GUI preserved the mount; `opengui` relaunched exactly one process, and the visible popover plus diagnostics both recovered the real RW/security state. Normal Unmount then passed the full BB-P0-02 cleanup. The detached cold-popover defect remains isolated in BB-02 and is fixed only in the working tree. |
| BB-P0-08 | NOT RUN | Root-authorized helper restart remains. |
| BB-P0-09 | NOT RUN | Two disposable NTFS volumes are now available; concurrent mounting follows rebuild. |
| BB-P0-10 | NOT RUN | Reversible root-authorized public-evidence permission fault remains. |
| BB-P1-00 | IN PROGRESS | The normal row remains Open/Unmount and exposes only Verified Copy in `…`; the destination panel began on the exact MobileData mount and Cancel created no file/status. Success/refusal/active-cancel flows remain. |
| BB-P1-01 | PASS | 256 MiB copy and reread SHA-256 matched; overwrite was refused without hash change; a controlled mutation was detected. |
| BB-P1-02 | FAIL | Installed package retained a recoverable partial because destination-only AppleDouble metadata changed the manifest. Source fix passes the same live 505-entry Unicode/symlink tree; rebuilt-package retest required. |
| BB-P1-03 | IN PROGRESS | Working-tree CLI interruption exited `130`, retained exactly one named partial, preserved the 4 GiB source and never published the final name. Rebuilt-package retest required. |
| BB-P1-04 | NOT RUN | Physical reconnect follows clean teardown. |
| BB-P1-05 | BLOCKED | Windows-side hash/playback comparison requires Windows and the same media. |
| BB-P1-06 | NOT RUN | Same-device explicit NTFS3 comparison remains. |
| BB-P1-07 | BLOCKED | Requires Windows-prepared clean/dirty/Fast Startup/error states. |
| BB-P1-08 | IN PROGRESS | One MBR device and interrupted/normal workloads recorded; the broader device/controller/OS/low-space inventory remains. |
| BB-P3-01 | FAIL | On the installed artifact, Open targeted the observed mount but no Finder window appeared. Source now asks Finder to reveal the path before fallbacks; rebuilt-package and two-drive retest required. |
| BB-P3-02 | IN PROGRESS | Default-off state and absence of unsolicited permission request confirmed. Grant/event/revoke matrix requires the operator. |
| BB-P3-03 | NOT RUN | Two disposable NTFS volumes are now available; run after rebuild. |
| BB-P3-04 | NOT RUN | Two disposable NTFS volumes are now available; run after rebuild. |
| BB-F01 | NOT RUN | No-I/O physical hot-unplug is intentionally near the end. |
| BB-F02 | NOT RUN | Final safe eject and uninstall are intentionally last. |

## Findings corrected in the working tree

### P1 directory verification and AppleDouble metadata

macOS stored excluded `com.apple.provenance` metadata as valid `._*` AppleDouble files on the
NFS-backed NTFS destination, including when `cp` received its no-xattr option. The verifier now
omits only a destination-only sidecar when it has AppleDouble magic, has a paired destination
entry, and has no same-path source entry. A real source file named `._something` remains in the
manifest and is verified byte-for-byte.

Focused Bats coverage passes `8/8`. The corrected working-tree CLI also passed the original live
tree: 505 source entries, nested paths, Unicode, 500 small files and a relative symlink. The 505
physical metadata sidecars remained on the filesystem but were correctly outside the documented
byte-integrity contract.

After the copy/Finder corrections, the complete automated gates passed Swift `245/245` and Bats
`286/286`. After the popover correction, Swift passes `247/247` and the focused `opengui` Bats
suite passes `4/4`; the shell implementation did not change. These prove the working tree, not
the still-installed pre-fix artifact.

### P3 Finder presentation

The installed app's generic Launch Services open returned success for the NFS path without
presenting a Finder window. The working tree now requests an exact Finder reveal first and uses
`/usr/bin/open` only as a fallback. This remains `FAIL` for the installed artifact until the rebuilt
app visibly opens the correct row's mount point.

### Cold `opengui` popover anchoring

The installed app recovered the surviving mount and displayed truthful controls after a forced GUI
restart, but AppKit placed the popover at the lower-left of the screen. The menu-bar button existed
before its hosting window had usable screen geometry, so the first cold URL request presented too
early. The working tree now coalesces requests and waits, for at most two seconds, until the button
has non-zero bounds and a real on-screen menu-bar position. A close or teardown cancels the wait;
no fallback detached window and no additional UI were added. New tests reject the observed
lower-left geometry and accept primary and secondary-display menu-bar anchors.

## Next operator checkpoints

1. Build and reinstall after the focused fixes are committed; retain this old evidence folder.
2. Retest cold/warm `opengui`, then the rebuilt P1 tree and P3 Finder/two-drive cells.
3. Perform only the requested physical, VPN, permission, Windows and final-uninstall actions.
