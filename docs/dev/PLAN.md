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
