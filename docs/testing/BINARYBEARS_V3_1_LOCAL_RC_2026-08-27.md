# BinaryBears v3.1.0 local release-candidate evidence — 2026-08-27

This record covers the privacy-safe local gate for the `upgrade/v3.1.0` candidate before any
publication. Raw samples, temporary applications, Accessibility traces, and removable-media test
files stay local and are not part of the repository.

## Scope and remaining boundary

- Host: Apple Silicon MacBook Air, Apple M5, 24 GB RAM, macOS 26.6.2 (25G83), AC power.
- Candidate: version/build 3.1.0, standard `SMAppService` and Legacy `SMJobBless` distributions.
- Local artifacts use the BinaryBears Developer ID Application identity.
- Local signing is not notarization. GitHub Actions must still notarize and staple the tagged
  artifacts, create a draft, and leave both downloaded draft DMGs for a final human smoke test.
- The local-only DMG interface tester and raw measurement lab are excluded from the tracked tree.

## Automated and packaging gate

| Gate | Result |
| --- | --- |
| Shell/Bats matrix | 335/335 passed |
| Rust `common-utils` | 8/8 passed |
| Rust `anylinuxfs` | 41/41 passed |
| Rust `vmproxy` | 9/9 passed |
| Swift standard distribution | 306 tests passed; the documented macOS 26.6.2 runner skip applies only to the compiled 13-case off-screen render suite |
| Swift Legacy distribution | 306 tests passed; same documented render-runner exception |
| Automatic GUI builder | Standard and Legacy app/DMG/checksum outputs passed |
| Release verifier | Nested Developer ID identities, entitlements, arm64 structure, quarantine state, DMG integrity, naming, and checksum sidecars passed for both variants |
| Workflow/static site | Workflow YAML, tracked-script ShellCheck, HTML parsing, JavaScript syntax, desktop/mobile interaction, reduced-motion CSS, and accessible impact labels passed |

Final local DMG checksums:

```text
f4698378ed3bff1ade8f20e1f3ce522da87a0fe073d850979a033e0704361871  ntfsmac-3.1.0-Apple-Silicon.dmg
6b32cc27759c377fd86bbbe7e12ea728ae4f30f442a864ae4738a0810802b875  ntfsmac-3.1.0-Legacy-Apple-Silicon.dmg
```

The full shell matrix initially exposed one fixture whose “no helpers installed” case inherited a
real Legacy helper from the host. The diagnostic now has a narrower Legacy-path test override, so
modern registration and complete absence are tested independently of host state. The focused
diagnostic suite passed 34/34 and the complete rerun passed 335/335.

## Live packaged behavior

### Standard

- The exact packaged app mounted, wrote, reread, and unmounted a clean NTFS partition through the
  standard helper with healthy schema-6 CLI diagnostics and enforced private-link evidence.
- The final app copied from the Standard DMG reported version/build `3.1.0`, variant `modern`,
  passed deep strict code-signature verification, and matched the packaged app byte-for-byte.
- After explicit Login Items approval, the final app registered the bundled 3.1.0 service, mounted
  from the GUI, wrote a fresh 64 MiB payload, and produced SHA-256
  `672f74cfb92cbab385b05b5fa1f94983fc1bce81e3c038de0aa3771de56d693b`. The same byte count and
  digest were observed after GUI unmount and remount.
- Twenty GUI mount/unmount cycles passed. An independent host monitor recorded the same transitions
  and the final host/runtime state contained no stale mount.
- Pointer reopen/click behavior remained responsive. Pointer activation did not leave the thick
  external focus halo; Tab produced one thin in-bounds keyboard focus treatment and pointer input
  cleared it.
- Refresh, Diagnose, Hide, Settings alignment, and the mounted-drive Quit confirmation passed.
- On the final packaged app, Diagnose presented only the four user-facing categories and all were
  `OK`; Hide removed the whole section. `Unmount and Quit` then removed the host mount and private
  runtime before the app exited.

### Legacy

- The packaged Legacy helper registered and ran under its compatibility identity without removing
  the already healthy standard helper.
- A fresh 64 MiB payload was written and reread from the NTFS volume; byte count and SHA-256 matched.
- Ten GUI mount/unmount cycles passed and an independent host monitor recorded exactly ten down and
  ten up transitions.
- Mounted Quit exposed `Unmount and Quit`, `Quit Anyway`, and `Cancel`; Cancel preserved the mount,
  and `Unmount and Quit` removed the host mount and runtime before exit.
- The live Legacy pass preceded the final rebuild. The only later executable-path change was the
  diagnostic fixture override described above; normal unset-environment behavior is unchanged.
  The final Legacy DMG then passed the complete automated and release-verifier gates.

### Legacy-to-standard migration

- The standard helper was running and its XPC/service version was healthy before cleanup began.
- The retired Legacy launchd job, process, privileged tool, and launchd plist were all absent after
  migration. A pre-v3 helper identity was absent as well.
- A newly replaced app copy correctly remained on `Approval required` while its persistent Login
  Items permission was off. After explicit approval, the same exact DMG app reached the normal GUI,
  registered a healthy modern helper, and completed the mounted smoke above. Legacy state remained
  absent throughout the final pass.

### Update check

- A temporary copy of the validated Standard app was changed only to display version 2.9.9,
  re-signed locally, installed in `/Applications`, and launched with the helper-registration screen
  harness so it could not register or replace a production helper.
- Settings reported `Version 2.9.9`; the icon-only manual action detected the latest stable GitHub
  release as 3.0.0, changed to `Update available`, and requested that release page.
- The synthetic app and its temporary directory were removed. The real Standard 3.1.0 app was
  restored and later replaced by the exact final Standard DMG; no fixture is tracked or published.

## Resource impact

Measurements used local 10- and 30-minute samples with cumulative process CPU time, physical
footprint, resident memory, and wakeups. No telemetry was added to the product.

| Scenario | App CPU average | App physical memory average | Start-to-end change | Wakeups per second (package / interrupt) |
| --- | ---: | ---: | ---: | ---: |
| Standard, idle, popover closed, 10 min | 0.00125% | 29.80 MiB | -1.06 MiB | 0.278 / 0.473 |
| Standard, popover open, 10 min | 0.00589% | 33.45 MiB | -0.56 MiB | 0.436 / 0.956 |
| Standard, mounted/no I/O, popover closed, 30 min | 0.00175% | 37.46 MiB | -1.42 MiB | 0.496 / 0.932 |
| Legacy, mounted/no I/O, popover closed, 30 min | 0.00181% | 37.70 MiB | -1.20 MiB | 0.485 / 0.950 |

The mounted private filesystem runtime averaged approximately 132.4 MiB for Standard and
153.3 MiB for Legacy. The modern helper stayed near 14.7 MiB resident; the Legacy helper settled
near 14.2 MiB. Ten Refresh/Diagnose cycles returned to a final 60-second app baseline of about
0.0058% CPU and 35.7 MiB physical memory.

The original regression was measurable: a permanently attached hidden SwiftUI `repeatForever`
transaction drove the app to roughly 0.114% CPU and 50–65 wakeups per second. The final view creates
that animation only while mounting, so removing the conditional child tears the animation down.
Hidden polling was also reduced to a 60-second drive scan and 30-second mount reconciliation;
opening the popover immediately switches to the 15/5-second interactive cadence.

Repeated UI inspection is not a valid memory-soak instrument on this host. A control run with 120
Accessibility tree reads and no mount activity raised the app footprint from about 15.1 to
31.0 MiB by itself; a fresh-app leak check reported zero leaks. Mount-cycle counts therefore prove
functionality and host truth, while the untouched 10/30-minute samplers provide the resource claim.

The website rounds these results up to a simpler consumer summary: about 30 MiB idle, 34 MiB with
the menu open, and 200 MiB for the complete mounted stack, all below one percent of the 24 GB test
Mac. Battery wording is explicitly an estimate from measured CPU activity and wakeups, not a
battery-life guarantee.

## Publication gate

The local release-candidate gate is complete. The exact rebuilt Standard-DMG approval and mounted
smoke passed, the removable-media test directory was deleted, and the temporary installed-app
backups were moved to Trash. The final repository privacy/staged-tree audit passed before
publication. Signed-tag verification, GitHub Actions notarization/stapling, and smoke-testing both
downloaded draft DMGs remain separate mandatory remote gates.
