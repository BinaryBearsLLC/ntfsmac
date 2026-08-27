import Foundation
import HelperShared
import NtfsmacGUI

/// Live-screen verification harness — lets every popover state (including states normally only
/// reachable with a real NTFS drive mounted) be exercised in the *actual* packaged app via each
/// type's existing test-DI seam, not just headless `ImageRenderer` tests. Inert by default: only
/// activates when `NTFSMAC_UI_DEMO` is set, which a real install never does. Kept in the tree
/// (not stripped before commit) so the next screen audit doesn't have to be re-derived from
/// scratch — see UITest.md.
///
/// `NTFSMAC_UI_DEMO=clean|dirty|error|eject-failure dist/ntfsmac.app/Contents/MacOS/ntfsmac-gui`
@MainActor
enum DemoScaffold {
    static func mountController(
        mode: String,
        appState: AppState,
        notifier: any MountEventNotifying = NullMountEventNotifier()
    ) -> MountController {
        let runtime = DemoHelperMounting(
            mountShouldFail: mode == "error",
            unmountFailureDevice: mode == "eject-failure" ? "disk4s2" : nil,
            stillReadOnly: mode == "dirty"
        )
        return MountController(
            helper: runtime,
            readOnlyChecker: DemoReadOnlyChecker(stillReadOnly: mode == "dirty"),
            snapshotProvider: runtime,
            notifier: notifier,
            appState: appState
        )
    }

    static func remountController(
        appState: AppState,
        notifier: any MountEventNotifying = NullMountEventNotifier()
    ) -> RemountController {
        RemountController(
            helper: DemoHelperMounting(),
            readOnlyChecker: DemoReadOnlyChecker(stillReadOnly: false),
            notifier: notifier,
            appState: appState
        )
    }

    static func driveScanner() -> DriveScanner {
        DriveScanner(runner: DemoCommandRunner())
    }

    /// A screen-audit run must never probe a real raw device using one of the synthetic disk IDs
    /// above. Starting in the granted state keeps the demo entirely inside its fake mount stack;
    /// production launches still create the normal session-scoped controller in `NtfsmacApp`.
    static func fullDiskAccessController() -> FullDiskAccessController {
        FullDiskAccessController(initialState: .granted)
    }

    /// Separate from `NTFSMAC_UI_DEMO`: install-outcome and mount-state are orthogonal axes, and
    /// unlike mounting, `HelperInstaller`'s real path is a one-shot OS auth dialog — faking
    /// denied/failed here avoids clicking "Cancel" on a real `SMJobBless` prompt repeatedly during
    /// a screen audit. `NTFSMAC_INSTALL_DEMO=installed|denied|failed`; the explicit `installed`
    /// mode is only a screen-audit bypass and never touches a real helper registration.
    static func helperInstaller(outcome: String) -> HelperInstaller {
        let result: HelperInstallOutcome
        switch outcome {
        case "installed": result = .installed
        case "failed": result = .failed("demo: SMJobBless failed (fake)")
        default: result = .denied("demo: Authorization was denied (fake)")
        }
        return HelperInstaller(service: DemoHelperInstallService(outcome: result))
    }
}

private struct DemoHelperInstallService: HelperInstallService {
    let outcome: HelperInstallOutcome
    func isInstalled(label: String) -> Bool { false }
    func bless(label: String) -> HelperInstallOutcome { outcome }
}

private struct DemoCommandRunner: PrivilegedCommandRunning {
    func run(_ path: String, _ args: [String]) -> CommandResult {
        CommandResult(
            output: "   1:                  GUID_partition_scheme                        *1.0 TB     disk4\n   2:  Microsoft Basic Data      DEMO-DRIVE               500.0 GB   disk4s2\n   1:                  GUID_partition_scheme                       *64.0 GB     disk5\n   2:  Microsoft Basic Data      DEMO-SECOND               32.0 GB   disk5s1\n",
            exitCode: 0
        )
    }
    func runPipingStdin(_ input: String, to path: String, _ args: [String]) -> CommandResult { CommandResult(output: "", exitCode: 0) }
}

@MainActor
private final class DemoHelperMounting: HelperMounting, MountSnapshotProviding {
    private let mountShouldFail: Bool
    private let unmountFailureDevice: String?
    private let stillReadOnly: Bool
    private var mounts: [String: ObservedMount] = [:]

    init(
        mountShouldFail: Bool = false,
        unmountFailureDevice: String? = nil,
        stillReadOnly: Bool = false
    ) {
        self.mountShouldFail = mountShouldFail
        self.unmountFailureDevice = unmountFailureDevice
        self.stillReadOnly = stillReadOnly
    }

    func mount(device: String, driver: FsDriver, mountPoint: String?, readOnly: Bool) async throws -> CommandResult {
        try? await Task.sleep(for: .seconds(1))
        if mountShouldFail {
            return CommandResult(output: "demo: mount failed (fake ntfs-3g exit)", exitCode: 1)
        }
        let label = device == "disk4s2" ? "DEMO-DRIVE" : "DEMO-SECOND"
        let resolvedMountPoint = mountPoint ?? "/Volumes/\(label)"
        mounts[device] = ObservedMount(
            deviceIdentifier: device,
            mountPoint: resolvedMountPoint,
            fsDriver: driver.rawValue,
            isReadOnly: readOnly || stillReadOnly
        )
        return CommandResult(
            output: "/dev/\(device) was mounted as \(resolvedMountPoint)",
            exitCode: 0
        )
    }

    func unmount(target: String) async throws -> CommandResult {
        if target == unmountFailureDevice {
            return CommandResult(output: "demo: device busy", exitCode: 1)
        }
        mounts.removeValue(forKey: target)
        return CommandResult(output: "unmounted", exitCode: 0)
    }

    func snapshot() async -> MountSnapshot {
        MountSnapshot(mounts: mounts.values.sorted { $0.deviceIdentifier < $1.deviceIdentifier })
    }
}

private struct DemoReadOnlyChecker: MountReadOnlyChecking {
    let stillReadOnly: Bool
    func isAnyNfsMountReadOnly() async -> Bool { stillReadOnly }
}
