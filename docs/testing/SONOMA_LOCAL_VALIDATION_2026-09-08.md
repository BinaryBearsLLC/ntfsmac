# macOS 14 compatibility — local qualification in progress

Branch: `Update/3.1.3`, candidate version 3.1.3 (31301). The `3.1.2` rollback branch and `dev` are unchanged.
No remote service, paid resource, push, release, or notarization is part of this run.

## Build change

The candidate now sets Swift and the app manifest to macOS 14.0. Host Rust builds
receive an explicit deployment target; the Go/CGO `init-rootfs` build also sets the
C compiler and external-linker minimum explicitly. The SDK may remain newer.

`build/lib/macos-target.sh` verifies arm64 Mach-O minimum-version metadata for all
four host runtime executables. Vendor verification and app packaging fail if a
binary requires a version above 14.0 or has unrecognized metadata. Packaging also
checks the compiled GUI and helper. Guest Linux binaries are not macOS executables
and are intentionally outside this load-command check.

The gate reproduced the existing `init-rootfs` minimum of 26.0 before rebuilding.
A full Rust static-library plus Go rebuild now passes with minimum 14.0. No
dependency version, filesystem driver, entitlement, or newer-OS feature was removed.

## Local results so far

- Host: Apple M5, macOS 26.6.2. These are **not** Sonoma execution results.
- Seven minimum-version regression tests pass, including real Mach-O fixtures
  compiled for 14.0 and 26.0 (the latter must be rejected).
- Standard Swift suite: 324 tests passed with deployment target 14.0. The existing
  macOS 26.6.2 render-suite exclusion remains; skipped rendering is not a pass.
- All four existing/rebuilt host runtime binaries pass the new minimum-version gate.
- The initial isolated Alpine preparation reported `start vm error: Invalid
  argument (errno 22)`. Inspection found that the setup runner copied the unsigned
  compiler output instead of the signed vendor artifact. The runner now copies
  the signed artifact without changing any entitlements. A regression test verifies
  that selection. Retesting completed actual guest package installation, and the
  resulting database matches all 70 locked base/add-on package versions exactly.
- Full shell run: 391 tests, 389 passed and two failed (full build and an obsolete
  assertion requiring version 3.1.2). The version assertion is corrected and its
  four-test suite passes. A full build in a separate directory passes, including
  all 61 Rust tests and exact guest package verification. The full-build Bats case
  also passes when rerun in the original build location with failure output enabled
  (`/tmp/ntfsmac-sonoma-build-bats-recheck.log`). Both failed cases therefore pass
  on retest. The original build failure did not retain detailed output, so its
  cause is not established. Do not describe that initial full-suite run as green.
- The real Standard 3.1.3 (31301) app was built at
  `dist/ntfsmac-3.1.3-sonoma-local.app`; deep/strict ad-hoc signature verification and
  minimum-version checks for the GUI, helper, and four runtime executables pass.
  It has not replaced the installed physical-host app and is not notarized.

Private logs: `/tmp/ntfsmac-sonoma-rootfs-build.log`,
`/tmp/ntfsmac-sonoma-swift.log`, `/tmp/ntfsmac-sonoma-bats.log`.
The signed-run retest is `/tmp/ntfsmac-sonoma-rootfs-signed.log`.

## Standard-only packaging follow-up

The local builder and official release orchestration now select only Standard.
Obsolete `INCLUDE_LEGACY=true` requests fail before credential access; old local
Legacy artifacts are preserved but excluded from release assets. Legacy source
and helper-migration tests remain. README, contributor, release, and testing
instructions describe this distinction.

Twelve focused builder/release tests pass, including a mocked orchestration run
that verifies one Standard packaging call, app/DMG notarization call selection,
and preservation of historical artifacts. This is **not** a real notarization run.
Repository shell scripts pass ShellCheck at warning severity; `git diff --check`
passes.

The real ad-hoc candidate was wrapped in
`dist/ntfsmac-3.1.3-sonoma-local-Apple-Silicon.dmg`. `verify-release.sh` passes:
app/helper identity, arm64 architecture, nested signatures and entitlements,
DMG mount/content/layout metadata, and checksum sidecar. Gatekeeper/notarization
were deliberately not claimed (`REQUIRE_NOTARIZATION=0`). No physical-host app
replacement or USB write occurred in this packaging follow-up.

The release verifier additionally checks the macOS 14 manifest and Mach-O floor
for GUI, helper, and host runtime, both in the input app and the actual app mounted
from the DMG. Two negative tests reject a 26.0 manifest and a real GUI fixture
compiled for 26.0 before signing checks. The real local DMG passes this strengthened
verification; this still proves packaging metadata, not execution on Sonoma.

Private packaging logs: `/tmp/ntfsmac-313-standard-only-dmg.log` and
`/tmp/ntfsmac-313-standard-only-verify.log`. The first follow-up complete shell
run passed 392 tests with exit 0 (`/tmp/ntfsmac-313-standard-only-bats.log`). Tests
were added during that execution, so it was followed by a fresh stable-source run.

On source commit `1f3a134`, the complete shell suite passed **395/395 tests across
49 files**, exit 0, with no source edits during the run. Log:
`/tmp/ntfsmac-313-stable-all-bats.log`. Both Swift variants also passed **324 tests
each**, exit 0, on that commit. Logs:
`/tmp/ntfsmac-313-stable-modern-swift.log` and
`/tmp/ntfsmac-313-stable-legacy-swift.log`. The existing macOS 26.6.2
`PopoverStateRenderTests` exclusion remains and is not counted as execution.

These runs close the automated local source gate for this commit. They do not
close actual Sonoma guest execution, GUI/rendering QA, final candidate physical
USB acceptance, or official signing/notarization. `dev` and `3.1.2` remain at
`b0ff6cd`; no branch push or publication was performed.

## Newer-system behavior retained

The pinned anylinuxfs source still selects privileged vmnet below macOS 26,
rootless vmnet from 26, and automatic TSO/checksum offload from 26.2. Targeting 14
does not remove these runtime checks. The reviewed privileged helper remains the
app's control path on all versions. Native newer-OS regression testing and Sonoma
runtime qualification must both complete before a support claim is finalized.

Local binary/SDK inspection also confirms that the new vmnet network APIs are
weak imports in the bundled helper. The strongly imported TSO and checksum keys
are declared available since macOS 11 and 12 respectively; `hv_vm_config_create`
is available since 13. libkrun resolves its optional EL2 APIs dynamically only
when nested mode is requested. These checks support the fallback design but do
not replace execution on Sonoma.

## Local virtual machine attempt

Parallels Desktop 27 is already installed. Sonoma 14.6.1 (23G93) was downloaded
directly from Apple's CDN into `Parallels/NTFSMac-Test-Media`. Apple's
`VZMacOSRestoreImage` reports `isSupported=true` and a supported hardware model on
this M5. This disproves the assumption that the M5 necessarily prevents local
Sonoma VM installation.

`prlctl create` successfully created `NTFSMac Sonoma 14 Test`, UUID
`92317191-3d42-4a5e-b408-163db90e7a61`, configured with 2 CPUs and 4 GiB RAM. The
installation completed and a Sonoma desktop was observed through the VM's own
screenshot command. The existing Windows 11 VM remains stopped and unchanged.

Automatic volume/camera sharing is disabled. Only the dedicated
`Parallels/NTFSMac-Guest-Tests` folder is configured for read-only sharing, but
Parallels still reports folder sharing inactive. After the user installed Tools
27.0.0-58625 and restarted the guest, default `prlctl exec` works as guest root;
the first `--current-user` call completed only after a long delay. The 119 MiB test kit was transferred over
the guest command channel into a newly created guest-only temporary directory,
without exposing other host folders or attaching physical USB drives.

## Actual Sonoma guest results

Guest `sw_vers` confirms macOS **14.6.1 (23G93), arm64**. After the transfer finished:

- The actual 3.1.3 (31301) app passes deep/strict signature verification in Sonoma.
- All four bundled host executables load and execute their help/version paths:
  anylinuxfs 0.19.0, init-rootfs, gvproxy, and vmnet-helper. These are real Sonoma
  execution results, not simulated OS checks or build metadata alone.
- The GUI launches as the guest's standard account, remains running, and displays
  its menu-bar icon. Popover contents, setup, helper registration, and full UI QA
  are not yet validated. The physical-host app was not replaced.
- The signed Hypervisor/Virtualization probe executes in Sonoma but returns
  `virtualizationSupported=false` and `hypervisorCreateResult=-85377009`.
  This is **0xfae9400f / HV_UNSUPPORTED**, confirmed against Apple's SDK header.
  Parallels still reports nested virtualization enabled after the reboot; that
  setting does not provide working guest Hypervisor access in this configuration.
- No rootfs boot or filesystem read/write result is claimed inside this guest.
  The preflight exits 2 for unavailable nested virtualization, not for binary-load
  failure. This VM limitation does not establish a failure on a native Sonoma Mac.

Private log: `/tmp/ntfsmac-sonoma-guest-preflight.log`; initial GUI capture:
`/tmp/ntfsmac-sonoma-app-first-launch.png`. An earlier preflight during incomplete
copy was discarded and rerun only after the transfer exited successfully.

A Sonoma guest can provide GUI/API evidence if supported by the host. Full driver
acceptance additionally requires the guest to expose Hypervisor.framework to
libkrun. This must be checked explicitly, not inferred from a booted desktop.
Neither a simulated OS-version decision nor USB tests on macOS 26 replace it.

A locally compiled and ad-hoc-signed diagnostic using Apple's Virtualization and
Hypervisor frameworks reports `VZVirtualMachine.isSupported=true` and successful
`hv_vm_create`/`hv_vm_destroy` (both return 0) on the native host. Probe output:
`/tmp/ntfsmac-sonoma-restore-check.log`; creation/start logs:
`/tmp/ntfsmac-sonoma-parallels-create.log` and
`/tmp/ntfsmac-sonoma-parallels-start.log`.
