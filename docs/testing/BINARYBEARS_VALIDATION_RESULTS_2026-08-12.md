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
| BB-01 | IN PROGRESS | Installed app, helper, bundled CLI, version/build and command surface were confirmed. Rebuilt commit `004e76e` exposed a root-owned cached `vmproxy` after its privileged update and failed. Replacement commit `db3aacf` then passed the affected upgrade: staging repaired that file to the invoking user without a manual ownership command; installed payload hashes match the candidate; ordinary and Microsoft-only backend scans both exited `0`; and the popover visibly showed the same two NTFS rows as `diskutil`. A deliberately blank clean-install replay remains. |
| BB-02 | PASS | The original package failed cold placement. Rebuilt commit `004e76e` passed cold and warm opening beneath the menu-bar icon, three simultaneous requests with exit `0`, exactly one GUI process, and invalid-argument exit `2` without another process or Accessibility permission. |
| BB-03 | IN PROGRESS | Mounted/Settings/Diagnostics light UI, Back, overflow-only copy action and Launch at login enable/disable passed. The cold-placement failure is tracked in BB-02; dark, full keyboard and safe warning/error states remain. |
| BB-P0-01 | PASS | The original package passed the default `ntfs-3g` RW round trip, diagnostic truth, vmnet/private/soft transport gate and root security transaction gate with one real session. Replacement commit `db3aacf` first stopped fail-closed while its replaced helper's Full Disk Access toggle was off. After the operator enabled exactly that entry, the GUI mounted MobileData RW with `ntfs-3g`; GUI, anylinuxfs status, host NFS table, diagnostic schema 6, and public security summary agreed on one mount/session with private vmnet, `soft` transport, PF evaluated, and no required route. A fixed-name write/reread SHA-256 round trip and exact test-artifact cleanup passed; the live NFS transport gate passed. Root security transaction verification and canonical teardown remain for this candidate. |
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
| BB-P1-02 | PASS | The original installed package retained a recoverable partial because destination-only AppleDouble metadata changed the manifest. Replacement commit `db3aacf` copied and published the same 505-entry nested/Unicode/symlink tree, then its installed CLI independently verified the destination manifest. The destination contained 1010 physical entries because of 505 AppleDouble sidecars, all correctly outside the byte-integrity contract without ignoring real source sidecars. |
| BB-P1-03 | PASS | The working-tree check and replacement commit `db3aacf` installed CLI both passed. The packaged copy was interrupted as one process group after a 25 MiB payload appeared, exited `130`, preserved the 4 GiB source, left the final name absent, and retained exactly one named partial for inspection. |
| BB-P1-04 | NOT RUN | Physical reconnect follows clean teardown. |
| BB-P1-05 | BLOCKED | Windows-side hash/playback comparison requires Windows and the same media. |
| BB-P1-06 | NOT RUN | Same-device explicit NTFS3 comparison remains. |
| BB-P1-07 | BLOCKED | Requires Windows-prepared clean/dirty/Fast Startup/error states. |
| BB-P1-08 | IN PROGRESS | One MBR device and interrupted/normal workloads recorded; the broader device/controller/OS/low-space inventory remains. |
| BB-P3-01 | IN PROGRESS | The original installed artifact targeted the observed mount but showed no Finder window. Replacement commit `db3aacf` visibly opened a Finder window titled MobileData from that row's Open action while status independently reported `/Volumes/MobileData`. The second concurrently mounted row still must open its own path before this cell passes. |
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
MobileData Finder window from its mounted row on 2026-08-13. The second-drive row remains required
before the complete two-drive cell passes.

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
label, size, and unmounted controls. A live mount/unmount cycle and deliberately blank install
remain before BB-01 closes.

## Next operator checkpoints

1. Complete one default mount/unmount cycle on replacement commit `db3aacf` and recheck ownership.
2. Retest the rebuilt P1 tree and P3 Finder/two-drive cells.
3. Perform only the requested physical, VPN, Windows and final-uninstall actions.

The first `db3aacf` Mount attempt is currently paused at the expected macOS privacy boundary:
System Settings shows exactly `com.khr898.ntfsmac.helper` with Full Disk Access off after helper
replacement. ChatGPT, Codex Computer Use, and Terminal remain off. The application did not create
a backend session or mount and did not misreport success.
