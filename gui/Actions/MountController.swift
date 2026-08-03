import Foundation
import HelperShared

/// Narrow seam over `HelperClient`'s two mutating methods so tests can inject a fake without a
/// real `NSXPCConnection` (`HelperClient` itself has no protocol — it's a concrete class wrapping
/// XPC directly, per `3-xpc-helper`). Declared here rather than in `gui/Helper/HelperClient.swift`
/// to keep that unit's file untouched; retroactive conformance below is same-module so no
/// `@retroactive` marker is needed.
@MainActor
public protocol HelperMounting {
    func mount(device: String, driver: FsDriver, mountPoint: String?, readOnly: Bool) async throws -> CommandResult
    func unmount(target: String) async throws -> CommandResult
}

extension HelperClient: HelperMounting {}

/// One mounted drive: the `Drive` plus its real mount point and per-drive read-only/dirty
/// landing state. Multi-mount (PLAN.md / GUI-PLAN.md "v2") means the controller holds a list
/// of these, not a single optional drive. `isDirty` is per-drive so `DriveRow`'s
/// "Mount read/write anyway…" pill can surface on exactly the row that landed read-only on a
/// dirty NTFS journal, not on every mounted row.
public struct MountedDrive: Identifiable, Equatable, Sendable {
    public let drive: Drive
    public var mountPoint: String?
    public var isReadOnly: Bool
    public var isDirty: Bool
    public var id: String { drive.id }
}

/// `[Mount]`/`Unmount` (GUI-PLAN.md "Popover — idle"/"Popover — mounted") always route through
/// this controller, which always routes through the XPC helper (L5) — never a raw shell-out.
/// Drives the shared `AppState.state` icon/popover transition: idle→mounting→mounted/error.
/// Supports multiple concurrent mounts (mixed NTFS + ext) — each mount is an independent
/// anylinuxfs microVM on its own vmnet /30 subnet (anylinuxfs `netutil::pick_available_network`
/// allocates a distinct subnet per mount), so the controller only has to track N entries and
/// keep the aggregate icon state correct.
@MainActor
public final class MountController: ObservableObject {
    @Published public private(set) var mountedDrives: [MountedDrive] = []
    @Published public internal(set) var errorMessage: String?

    private let helper: any HelperMounting
    private let readOnlyChecker: any MountReadOnlyChecking
    private let appState: AppState

    public init(
        helper: any HelperMounting = HelperClient(),
        readOnlyChecker: any MountReadOnlyChecking = RealMountOptionsChecker(),
        appState: AppState
    ) {
        self.helper = helper
        self.readOnlyChecker = readOnlyChecker
        self.appState = appState
    }

    /// Derive the helper driver from the parsed fstype when the caller didn't pin one. ext-family
    /// (GPT-name fallback "ext" or blkid "ext2/3/4") → `.ext` so the helper skips --fs-driver and
    /// passes --ignore-permissions; everything else (ntfs, BitLocker) → `.ntfs3g`. `hasPrefix`
    /// is safe here — `DriveListParser.allowedFsTypes` is the only producer of fsType and the
    /// only value starting with "ext" is the ext family. NTFS never routes to `.ext`.
    static func driverFor(_ fsType: String) -> FsDriver {
        fsType.hasPrefix("ext") ? .ext : .ntfs3g
    }

    // MARK: - Back-compat single-drive accessors
    // `PopoverContentView`/`FinderOpener` and existing tests read the "primary" mounted drive
    // and its mount point. With N drives these return the first — the per-row UI in
    // `PopoverContentView` renders from `mountedDrives`/`mountedDriveIDs` directly, so these
    // accessors only feed the icon/banner and the Finder-reveal of the first mount.

    /// First mounted drive, or nil if nothing is mounted (primary-drive compat).
    public var mountedDrive: Drive? { mountedDrives.first?.drive }
    /// First mounted drive's real mount point, or nil (primary-drive compat).
    public var mountedMountPoint: String? { mountedDrives.first?.mountPoint }
    /// Identifiers of every currently mounted drive — used by `DriveListView` to mark rows.
    public var mountedDriveIDs: Set<String> { Set(mountedDrives.map(\.id)) }

    /// `mountPoint`: real, caller-resolved path (e.g. `Settings.defaultMountPoint` with
    /// `<label>` substituted) — `nil` lets anylinuxfs pick its own default under `/Volumes/`.
    /// `readOnly`: threads through to the helper's `--read-only` flag (`HelperMounting`'s real
    /// lever for `Settings.defaultMountMode == .readOnly` — see `HelperProtocol.swift`'s doc
    /// comment for why this is the only real mechanism available).
    /// `driver`: `nil` (the default — what `PopoverContentView`'s `mountDrive` passes) derives
    /// from `drive.fsType`: ext-family → `.ext` (helper skips --fs-driver, adds
    /// --ignore-permissions for all_squash), anything else → `.ntfs3g`. An explicit driver
    /// overrides — preserved for a future ntfs3 preference and for tests that pin the value.
    public func mount(_ drive: Drive, driver: FsDriver? = nil, mountPoint: String? = nil, readOnly: Bool = false) async {
        // Do clause: validate the device regex before the call. `HelperClient.mount` already
        // re-validates internally (defense in depth per L6), but that check is invisible to a
        // mocked `HelperMounting` in tests — this guard is what the acceptance criteria
        // ("rejection of invalid device names") actually exercises.
        guard validateDevice(drive.identifier) else {
            fail("Invalid device name: \(drive.identifier)")
            return
        }

        errorMessage = nil
        appState.state = .mounting
        do {
            let resolvedDriver = driver ?? Self.driverFor(drive.fsType)
            let result = try await helper.mount(device: drive.identifier, driver: resolvedDriver, mountPoint: mountPoint, readOnly: readOnly)
            if result.exitCode == 0 {
                let resolvedMountPoint: String?
                if let mountPoint = mountPoint {
                    resolvedMountPoint = mountPoint
                } else {
                    // Parse the actual mount point from the command output, e.g.:
                    // "/dev/disk4s2 was mounted as /Volumes/My Drive"
                    let lines = result.output.components(separatedBy: .newlines)
                    if let mountLine = lines.first(where: { $0.contains(" was mounted as ") }),
                       let range = mountLine.range(of: " was mounted as ") {
                        let path = String(mountLine[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        resolvedMountPoint = path
                    } else {
                        // Fallback to the heuristic
                        resolvedMountPoint = "/Volumes/\(drive.label.isEmpty ? drive.identifier : drive.label)"
                    }
                }
                // A `readOnly: false` request can still land read-only: ntfs-3g silently falls
                // back to read-only on a dirty/unclean NTFS journal (same real-mount-options
                // check `RemountController.confirmRemount` already relies on — `exitCode == 0`
                // alone doesn't mean "mounted the way you asked"). Without this, a dirty landing
                // was reported as a healthy `.mountedReadWrite`, and `.mountedReadOnlyDirty` was
                // never reachable from a real mount at all — only from `RemountController`, which
                // itself is only reachable from the banner this state is supposed to trigger.
                // ponytail: known ceiling — `isAnyNfsMountReadOnly()` is global, so with a sibling
                // dirty drive already mounted, a clean 2nd mount could be mis-flagged dirty.
                // Per-mount-point disambiguation is the upgrade path; acceptable while N is small.
                let isReadOnly: Bool
                let isDirty: Bool
                if readOnly {
                    isReadOnly = true
                    isDirty = false
                } else if await readOnlyChecker.isAnyNfsMountReadOnly() {
                    isReadOnly = true
                    isDirty = true
                } else {
                    isReadOnly = false
                    isDirty = false
                }
                mountedDrives.append(MountedDrive(drive: drive, mountPoint: resolvedMountPoint, isReadOnly: isReadOnly, isDirty: isDirty))
                recomputeAggregateState()
            } else {
                fail(result.output)
            }
        } catch {
            fail(Self.describe(error))
        }
    }

    /// Unmount one drive by id, or every mounted drive when `driveID` is nil. Each unmount is an
    /// independent `helper.unmount(target:)` call (one anylinuxfs session per drive).
    public func unmount(driveID: String? = nil) async {
        errorMessage = nil
        let targets: [String]
        if let driveID {
            guard mountedDrives.contains(where: { $0.id == driveID }) else { return }
            targets = [driveID]
        } else {
            targets = mountedDrives.map(\.id)
        }
        guard !targets.isEmpty else { return }
        for target in targets {
            do {
                let result = try await helper.unmount(target: target)
                if result.exitCode == 0 {
                    mountedDrives.removeAll { $0.id == target }
                } else {
                    fail(result.output)
                    recomputeAggregateState()
                    return
                }
            } catch {
                fail(Self.describe(error))
                recomputeAggregateState()
                return
            }
        }
        recomputeAggregateState()
    }

    public func clearError() {
        errorMessage = nil
    }

    /// Derive the shared icon/banner state from the full mounted set. The icon reflects the
    /// worst landing across all drives: any dirty → dirty banner; else any ro → read-only;
    /// else read/write; empty → idle. `.mounting` is set imperatively at mount start and
    /// overwritten here once the mount resolves.
    private func recomputeAggregateState() {
        if mountedDrives.isEmpty {
            appState.state = .idle
        } else if mountedDrives.contains(where: { $0.isDirty }) {
            appState.state = .mountedReadOnlyDirty
        } else if mountedDrives.contains(where: { $0.isReadOnly }) {
            appState.state = .mountedReadOnly
        } else {
            appState.state = .mountedReadWrite
        }
    }

    private func fail(_ message: String) {
        // A failed mount/unmount while other drives are still mounted must not flip the icon to
        // `.error` and hide the "mounted" indicator — only go `.error` when nothing is mounted.
        if message.contains("Insufficient permissions?") || message.contains("Cannot probe") {
            errorMessage = "FDA_REQUIRED"
        } else {
            errorMessage = message
        }
        if mountedDrives.isEmpty {
            appState.state = .error
        }
    }

    /// GUI-PLAN.md "Error state": plain-language cause, not a raw Swift error dump. Not
    /// `private` — `RemountController` (`3-dirty-ro-warning`) reuses it rather than
    /// re-duplicating the same `HelperClientError` mapping.
    static func describe(_ error: Error) -> String {
        switch error {
        case HelperClientError.invalidDevice(let device):
            return "Invalid device name: \(device)"
        case HelperClientError.invalidUnmountTarget(let target):
            return "Invalid unmount target: \(target)"
        case HelperClientError.helper(let message):
            return message
        case HelperClientError.decode:
            return "Helper returned an unreadable response"
        case HelperClientError.proxyUnavailable:
            return "Privileged helper is not installed or not responding"
        default:
            return error.localizedDescription
        }
    }
}
