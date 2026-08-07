# anylinuxfs update policy

BinaryBears uses periodic, explicitly audited anylinuxfs pin updates. Neither the build nor an
automation follows `origin/main`, a floating branch, or the newest tag. A bot may report that a
candidate exists, but it must not merge or update the submodule automatically.

The source of truth remains `ANYLINUXFS_COMMIT` and `ANYLINUXFS_VERSION` in
[`build/sources.lock`](../../build/sources.lock), paired with the exact
`vendor/src/anylinuxfs` submodule commit. An accepted update is a dedicated review unit branched
from `dev`; an upstream proposal is rebuilt independently from `upstream/main`.

## Read-only candidate preflight

Fetch candidate objects explicitly, then run the repository preflight with a tag or commit:

```sh
git -C vendor/src/anylinuxfs fetch --prune origin
./build/audit-anylinuxfs-update.sh v0.19.0
```

The script requires a clean submodule at the currently locked commit. It verifies repository
identity and ancestry, reports the exact commits/files between the lock and candidate, separates
dependency-manifest drift from source-path drift, and applies ntfsmac's Alpine transformations to
a disposable candidate archive. It never checks out the candidate or changes the pin. A passing
result ends with `decision=pending_manual_review`; it is not approval.

## Required review checklist

Record every item below in `build/AUDIT.md` and in the pull-request description. Use `blocked` or
`not applicable` with a reason rather than silently omitting a gate.

1. **Identity and release scope**
   - Record current and candidate commit, tag, release URL/date, ancestry, and exact commit list.
   - Read the official release notes and distinguish the full release range from the smaller
     delta after BinaryBears' current in-between pin.
   - Confirm the source remote is exactly `https://github.com/nohajc/anylinuxfs.git`.
2. **Trust-boundary source review**
   - Inspect changes under `anylinuxfs/src`, `vmproxy/src`, `common-utils/src`, `vmrunner-sys`,
     `init-rootfs`, configuration files, and dependency-download scripts.
   - Review mount/unmount, raw-device probing, VM command transport, NFS export/client options,
     vmnet/gvproxy selection, filesystem detection, encryption, and cleanup separately.
   - Any change in these paths requires an explicit behavior note and cannot auto-merge.
3. **Dependency and lock review**
   - Review every Cargo/Go manifest and lock change, including transitive additions/removals,
     toolchain-floor changes, advisories, licenses, and the exact libkrun resolution.
   - Run the ecosystem vulnerability tools used by the project when available; record a missing
     tool as missing evidence, never as a clean result.
4. **Local patch and scope compatibility**
   - Require `local_patch_compatibility=pass` from the preflight.
   - Recheck the trimmed Alpine package list, dropped FreeBSD artifacts/features, static libblkid
     staging, immutable Alpine reference, vmnet-only mount argument, and `soft` NFS policy.
   - Do not expand supported filesystems or add a fetched artifact implicitly.
5. **Pin and audit update**
   - Only after review, update the submodule plus `ANYLINUXFS_COMMIT`,
     `ANYLINUXFS_VERSION`, and coupled component pins such as `VMPROXY_VERSION` in one commit.
   - Append accepted/rejected evidence to `build/AUDIT.md`; never rewrite older evidence.
6. **Automated gates**
   - Run `./tests/run-all.sh` and `./build.command gui` from the exact candidate tree.
   - Verify vendored architectures, entitlements, ad-hoc signatures, quarantine state, kernel
     pin, runtime digest scan, app bundle, and DMG.
   - Run targeted tests for any changed parser, command, dependency, or patch marker before the
     full gates.
7. **Hardware gates**
   - Exercise list, NTFS mount/write/read/unmount, restart recovery, external teardown, and
     privacy-safe diagnostics on real Apple Silicon hardware.
   - Re-run the vmnet route/listener/`soft` gate, VPN off/on, hot-unplug recovery, and concurrent
     mounts when the update touches or resolves code in those paths.
   - Use SHA-256 fixtures for copy-integrity claims. Healthy runtime diagnostics alone do not
     prove copied bytes.
8. **Decision and rollback**
   - Accept only with a named reviewer decision and complete evidence. Otherwise keep the old pin
     and record why the candidate was deferred or rejected.
   - Preserve the previous pin as the rollback target; runtime caches remain side-by-side and are
     never deleted as part of a source update.

## Dry-run: v0.19.0 evaluated 2026-08-08

- Current pin: `8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3` (`0.18.0` package version), already
  26 commits after the upstream `v0.18.0` tag.
- Candidate: `28d308bb9ed15611118fa51d998b988b3ee62459` (`v0.19.0`), four commits after the
  BinaryBears pin.
- Official release: [anylinuxfs-0.19.0](https://github.com/nohajc/anylinuxfs/releases/tag/v0.19.0),
  published 2026-07-20. Its notes cover the full `v0.18.0...v0.19.0` range; the behavioral
  FreeBSD/vmnet/libkrun work described there was already present before the current BinaryBears
  in-between pin.
- Exact remaining delta: package version `0.18.0` → `0.19.0`, `serde_with` `3.16.1` → `3.21.0`,
  Go `x/crypto` `0.51.0` → `0.54.0`, and related Go/Rust manifest/lock refreshes.
- Twelve files change: Cargo/Go manifests and locks only. No Rust/Go implementation source,
  default Alpine package list, download script, mount/NFS/vmnet code, or ntfsmac patch marker
  changes in the four-commit delta.
- The read-only preflight passes local Alpine patch compatibility and leaves the submodule/pin
  untouched.
- Decision: **deferred, not rejected**. This roadmap unit validates the audit workflow; it does
  not update the production pin. Candidate build, dependency-advisory review, and the required
  hardware matrix remain mandatory in a later dedicated pin-update branch.
