# 3.1.3 installed-app checks — 8 September 2026

Candidate: 3.1.3 (31302), Standard, `Update/3.1.3`. This is local qualification, not a
published release or a claim of complete macOS 14+ coverage.

## Automated and packaging checks

- Complete shell suite: **397/397**, exit 0, across 49 Bats files.
- The complete suite ran on functional build 31301. After the build-number-only change to
  31302, packaging/diagnostic checks passed **48/48** and both Swift configurations passed
  **345 tests each** again.
- Standard and retained Legacy regression configurations: **345 Swift tests each**.
  The existing macOS 26.6.2 render-suite exclusion remains; it is not rendering evidence.
- Vendor verification passes, including exact source/version pins, signatures, kernel assets
  and the macOS 14 Mach-O minimum-version gate.
- The install-test app uses the existing BinaryBears Developer ID signing path. Deep/strict
  verification passes. This run did not notarize or publish the package.
- GUI executable SHA-256 in the package and physical `/Applications` installation:
  `f7b63159d4fec457377e33394587f3f5fb7df5a2f769de73e1ae5182bd6ee5f7`.
- Helper SHA-256: `828cb528ecbc68ffc06a6657db4da97272ba94b5901c8123c934abc6b369c839`.
- Final packaging ran sequentially after packaging tests: both temporarily generate the CLI
  manifest and must not run concurrently. The final embedded CLI tree hash was checked in
  both executables; the source manifest was restored to its checked-in placeholder.

Private logs: `/tmp/ntfsmac-313-final-all-bats.log`,
`/tmp/ntfsmac-313-notice-once-modern.log`, `/tmp/ntfsmac-313-notice-once-legacy.log`,
`/tmp/ntfsmac-313-final-vendor.log`, `/tmp/ntfsmac-31302-install-package-sequential.log`,
`/tmp/ntfsmac-31302-metadata-tests.log`, `/tmp/ntfsmac-31302-modern-swift.log`,
`/tmp/ntfsmac-31302-legacy-swift.log`.

## Physical M5 — macOS 26.6.2

The previous 31208 app was backed up before replacement. `/Applications/ntfsmac.app` now
contains 31302. The user completed the app's normal Install Helper action successfully;
the installed diagnostic reports schema 7, version 3.1.3, build 31302.

- First launch displays the unvalidated-OS notice with the fork issue tracker and existing
  Command-click Diagnose instructions. Continue stores acknowledgement. Quit/relaunch does
  not repeat the notice. The preference key does not depend on app or OS version.
  Acknowledgement also persisted through the 31301-to-31302 app replacement.
- Actual Settings inspection confirms centered Binary Bears LLC attribution and no additional
  diagnostic export button.
- With physical NTFS and ExFAT media connected together, the GUI offers only the NTFS volume.
  The ExFAT partition is not mislabelled NTFS despite its Microsoft Basic Data partition type.
- Using the GUI and current helper: mount NTFS, write a new 16 MiB test file, flush/fsync,
  verify SHA-256, unmount, remount, reread and verify the same SHA-256, delete only the test
  file, and unmount again. All stages passed on both 31301 and final 31302. The volume was not formatted.
- Mounted diagnostics report one NFS mount and `expected_vmnet`; idle diagnostics report zero.
  SHA-256 of the deterministic test payload:
  `341aacac661ccb210720bedaa9ead5d668fe5ea41a73532fc147c71e34040df1`.

Private final-build logs: `/tmp/ntfsmac-31302-host-final.json`,
`/tmp/ntfsmac-31302-host-mounted.json`, `/tmp/ntfsmac-31302-mobiledata-integrity.log`.

Earlier ext2/ext3/ext4, NTFS image and native-filesystem acceptance is retained in the
[mixed-filesystem record](MIXED_FILESYSTEM_VALIDATION_2026-09-08.md). It was not rerun on
this final installed package; do not relabel earlier results as a fresh 31302 matrix.

## Sonoma VM — macOS 14.6.1 (23G93)

The same signed package was copied into guest `/Applications/ntfsmac.app`. GUI and helper
hashes match the physical-host installation, and deep/strict signature verification passes
inside Sonoma. The one-time notice displays the correct guest OS and was acknowledged.
Acknowledgement persists through a guest reboot; the new app launches without repeating it.

The bundled read-only diagnostic emits schema 7 and correctly identifies `virtual_machine=true`,
`hardware_family=Apple_M5` and unavailable sysctl evidence as `unknown`. A separate signed
framework probe still reports `VZVirtualMachine.isSupported=false` and
`hv_vm_create=-85377009` (`HV_UNSUPPORTED`). `healthy` in the CLI diagnostic is not a VM
boot/read-write acceptance result.

The guest retains an SMAppService/Background Task Management registration pointing at a
previous test-app location, despite the current 31302 app being in Applications. The previous
app was archived before replacement. Normal repair, targeted approval and a guest reboot did
not complete helper setup. The final launchd log reports `Launch Constraint Violation` at the
cached retired test-app path, with exit 78 (`EX_CONFIG`). No signing constraints were disabled
and no global background-item reset was performed.

Consequently the guest's installed CLI still reports schema 6/build 31301: **updating the app
bundle did not complete the guest helper/CLI upgrade**. Schema 7 evidence above comes from
the bundled read-only diagnostic, not that stale installed CLI. This installation blocker and
the independently measured lack of guest Hypervisor access are separate failures. Build 31302
does not by itself fix registration. Details are retained locally in
`/tmp/ntfsmac-31302-sonoma-registration-detail.log` and
`/tmp/ntfsmac-31302-sonoma-final.json`.

No physical disk was attached to or formatted by this VM. Native Sonoma filesystem testing,
macOS 15 and other chips/OS patch releases remain unverified. See the
[Sonoma investigation](SONOMA_LOCAL_VALIDATION_2026-09-08.md) for earlier native view-rendering
and executable-load evidence.

## Documentation, site and repository state

README and the project website distinguish native M5 results, limited Sonoma guest evidence,
and untested combinations. Compatibility reports are invited with version/build, OS, chip
family, filesystem and completed operations; success reports and failures are both useful.
Reports must be reviewed for privacy. Community evidence is not labelled maintainer testing.

The local website was checked in a browser at desktop (1280 px) and mobile (390 px) widths:
no horizontal overflow or broken images; desktop compatibility cards were visually inspected.
The download button still resolves to the published 3.1.2 release, not an invented 3.1.3 asset.
Historical resource-use measurements are explicitly labelled as not repeated for 3.1.3.

The only obsolete local branch was `maintenance/dependency-refresh-2026-08` (`a7066b8`).
It was deleted after ancestry verification; every commit remains reachable from `Update/3.1.3`.
Retained: `main`, `dev`, `3.1.2`, `Update/3.1.3`. Both active worktrees are preserved.
`dev` and `3.1.2` remain at `b0ff6cd`. No push, merge into dev, release or website deployment.

GitHub is **not** yet a complete backup. Local-only commits, ignored build artifacts, caches,
installation backups, VM media and private test logs are not restored by cloning the remote.
Keep the checkout and VM until the version branch has been published and backups are checked.
