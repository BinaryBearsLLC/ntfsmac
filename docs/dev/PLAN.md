# Architecture

ntfsmac provides a native macOS interface to a pinned Linux filesystem runtime.
The 3.1.3 line targets Apple Silicon and macOS 14+. See [testing](TESTING.md)
for measured coverage and [the GUI contract](GUI-PLAN.md) for current behavior.

## Components

| Component | Responsibility |
| --- | --- |
| `gui/` | SwiftUI menu-bar app, discovery, presentation and XPC client |
| `helper/` | Reviewed privileged operations and bundled CLI installation |
| `cli/` | Device validation, mount lifecycle, diagnostics and security transactions |
| `vendor/` | Pinned anylinuxfs runtime, kernel and supporting executables |
| `build/` | Source transformations, reproducible inputs, packaging and verification |
| `tests/`, `gui/Tests/`, `helper/Tests/` | Shell, GUI and helper regression coverage |

## Mount lifecycle

1. Discover the filesystem using a probe for the exact partition. A partition-map
   type such as Microsoft Basic Data is not proof of NTFS.
2. The app requests a mount through XPC. The helper independently validates the
   partition identifier and checks its caller before executing privileged operations.
3. anylinuxfs launches the libkrun microVM with the selected block device. The
   pinned Alpine guest mounts NTFS with ntfs-3g, or a supported ext filesystem.
4. The guest exports the filesystem over NFS; macOS mounts it through a dedicated
   vmnet `/30` link. Per-session PF and route ownership belong to the mount transaction.
5. Unmount reconciles host and guest state and removes only that session's resources.

The transport remains NFS with `soft` client mounts. vmnet uses shared mode;
strict isolation claims require measured PF and routing evidence. The existing
`rsize=1048576,wsize=1048576,readahead=16` defaults tune transfer size and prefetch;
they do not enable asynchronous exports. `async` remains absent by default.

## Privilege and data safety

The GUI never invokes raw `sudo`, mount, PF or route mutations. App-initiated
privileged actions use the reviewed helper. Partition identifiers must match
`^disk[0-9]+s[0-9]+$` at both UI and execution boundaries. Read-only diagnostics
must not initialize a VM, elevate privileges or upload information.

Drive inventory remains unprivileged. The separate `probeFilesystem` XPC method can read
the superblock of one validated partition using the existing helper's raw-device access.
Its fixed native command is bounded to five seconds and bypasses runtime/configuration,
mounting, decryption and volume assembly. GUI responses must match the requested identifier;
failed or missing metadata cannot establish a filesystem. The CLI exposes the same operation
as `ntfsmac filesystem <device>` (JSON; administrator access may be required).

ntfs-3g is the default; NTFS3 is explicitly experimental. Unsafe writable NTFS is
refused, not overridden. Missing filesystem or security evidence stays unknown.
Copy success requires flush and reread verification, not just a successful write.

## Distribution and dependencies

Standard uses SMAppService. Legacy SMJobBless source remains solely for migration
and regression coverage; 3.1.3 does not distribute a Legacy installer.
Local builds may be ad-hoc; official releases use the existing Developer ID and
notarization path. See [release instructions](../RELEASE.md).

Exact inputs are in `build/sources.lock`, package manifests and source locks.
[Dependency policy](ANYLINUXFS_UPDATE_POLICY.md) and `build/AUDIT.md` record
review decisions. FreeBSD executables are not distributed; do not remove retained
Cargo features or Alpine packages without checking their actual dependencies.

The original phased implementation plan and session diaries are available at
commit `90388df` in Git history. They are not current build or product instructions.

## Self-contained runtime — Beta 3 implementation

The owner requires first-run initialization and mounting without downloads from third parties.
The release candidate tracks the Alpine OCI base, the exact 54 APKs and the NFS entrypoint
under `vendor/runtime/`, and include them in both the app and CLI distribution. The installed
location is `lib/ntfsmac-runtime` beneath the existing installation prefix. GitHub stores the
actual payload files; Git LFS pointers or third-party download fallbacks do not satisfy this.
Development toolchains and source-build downloads are distinct from the end-user runtime.

`SHA256SUMS` lists every payload file. Its own hash is pinned in `build/sources.lock`, and the
initializer embeds the verified manifest at compile time. Verify files and reject symlink/path
escapes before modifying a runtime cache. Import the local OCI image with its existing pinned
platform digest, stage local APKs, verify their hashes and Alpine signatures, and install them
with `apk --no-network`. Copy the versioned NFS entrypoint locally. Missing or corrupt payloads
must fail with a reinstall instruction; they must never trigger a remote fallback.

The runtime cache identity includes the payload hash, so an earlier online cache cannot count
as offline initialization evidence. Existing caches and user volumes remain untouched.

Implementation and validation order:

- [x] Track and validate the payload, OCI content graph, package metadata and source provenance.
  `build/verify-offline-runtime.py <repository-root>` validates the manifest against all locks.
- [x] Add a deterministic Go offline adapter and patch integration in scratch sources only.
  Test missing/tampered files, unsafe paths, local OCI import and network denial.
- [x] Stage the same payload in the build runner, installed CLI and signed app/helper tree.
  Keep the existing XPC caller/signature validation and macOS 14 floor.
- [x] Build and initialize a new cache with external networking denied; verify all 70 packages.
  Run the source gates, both Swift variants, and package/sign/check the exact candidate.
- [x] Test the installed candidate's GUI and CLI on the connected multi-partition SSD,
  including independent mount/unmount, Finder, refresh and diagnostics. Native writes require
  authorization for temporary test files on the named partitions. These local gates passed;
  publication still requires the notarized draft artifact checks in the release guide.
