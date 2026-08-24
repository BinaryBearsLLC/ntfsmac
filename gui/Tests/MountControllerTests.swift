import Testing
import HelperShared
@testable import NtfsmacGUI

// GUI-PLAN.md "Popover — idle"/"Popover — mounted": [Mount]/Unmount always route through the XPC
// helper (L5), never a shell-out. `FakeHelper` stands in for `HelperClient` (a concrete class
// wrapping a real `NSXPCConnection` — can't be unit tested directly) via the `HelperMounting` seam.

private let sampleDrive = Drive(identifier: "disk4s2", fsType: "ntfs", label: "My Drive", size: "500.0 GB")

private final class FakeHelper: HelperMounting, MountSnapshotProviding {
    private(set) var mountCalls: [(device: String, driver: FsDriver, mountPoint: String?, readOnly: Bool)] = []
    private(set) var unmountCalls: [String] = []
    var mountResult: Result<CommandResult, Error> = .success(CommandResult(output: "mounted", exitCode: 0))
    var unmountResult: Result<CommandResult, Error> = .success(CommandResult(output: "unmounted", exitCode: 0))
    var unmountResultsByTarget: [String: Result<CommandResult, Error>] = [:]
    var snapshotReadOnlyOverride: Bool?
    private var successfulUnmounts: Set<String> = []

    func mount(device: String, driver: FsDriver, mountPoint: String?, readOnly: Bool) async throws -> CommandResult {
        mountCalls.append((device, driver, mountPoint, readOnly))
        return try mountResult.get()
    }

    func unmount(target: String) async throws -> CommandResult {
        unmountCalls.append(target)
        let result = try (unmountResultsByTarget[target] ?? unmountResult).get()
        if result.exitCode == 0 {
            successfulUnmounts.insert(target)
        }
        return result
    }

    func snapshot() async -> MountSnapshot {
        var latest: [String: (device: String, driver: FsDriver, mountPoint: String?, readOnly: Bool)] = [:]
        for call in mountCalls where !successfulUnmounts.contains(call.device) {
            latest[call.device] = call
        }
        let mounts = latest.values.map { call in
            ObservedMount(
                deviceIdentifier: call.device,
                mountPoint: call.mountPoint ?? "/Volumes/\(call.device)",
                fsDriver: call.driver.rawValue,
                isReadOnly: snapshotReadOnlyOverride ?? call.readOnly
            )
        }.sorted { $0.deviceIdentifier < $1.deviceIdentifier }
        return MountSnapshot(mounts: mounts)
    }
}

@MainActor
private final class BlockingStorageHelper: HelperMounting, MountSnapshotProviding {
    private var mountContinuation: CheckedContinuation<CommandResult, Never>?

    func mount(device: String, driver: FsDriver, mountPoint: String?, readOnly: Bool) async throws -> CommandResult {
        await withCheckedContinuation { continuation in
            mountContinuation = continuation
        }
    }

    func unmount(target: String) async throws -> CommandResult {
        CommandResult(output: "unmounted", exitCode: 0)
    }

    func snapshot() async -> MountSnapshot {
        MountSnapshot(mounts: [])
    }

    func finishMount() {
        mountContinuation?.resume(returning: CommandResult(output: "mount failed", exitCode: 1))
        mountContinuation = nil
    }
}

private struct FakeReadOnlyChecker: MountReadOnlyChecking {
    let isReadOnly: Bool
    func isAnyNfsMountReadOnly() async -> Bool { isReadOnly }
}

@MainActor
private final class RecordingMountNotifier: MountEventNotifying {
    private(set) var events: [MountNotificationEvent] = []
    func post(_ event: MountNotificationEvent) { events.append(event) }
}

@MainActor
@Test func mountRoutesThroughHelperAndTransitionsToMountedReadWrite() async {
    let fake = FakeHelper()
    let appState = AppState()
    let notifier = RecordingMountNotifier()
    let controller = MountController(
        helper: fake,
        readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false),
        notifier: notifier,
        appState: appState
    )

    await controller.mount(sampleDrive)

    #expect(fake.mountCalls.count == 1)
    #expect(fake.mountCalls[0].device == "disk4s2")
    #expect(fake.mountCalls[0].driver == .ntfs3g)
    #expect(appState.state == .mountedReadWrite)
    #expect(controller.mountedDrive == sampleDrive)
    #expect(controller.errorMessage == nil)
    #expect(!controller.hasStorageOperationInFlight)
    #expect(notifier.events == [.mounted(volumeName: "My Drive", readOnly: false)])
}

@MainActor
@Test func storageOperationFlagCoversTheWholeAsynchronousMount() async {
    let helper = BlockingStorageHelper()
    let controller = MountController(helper: helper, appState: AppState())

    let operation = Task { await controller.mount(sampleDrive) }
    await Task.yield()

    #expect(controller.hasStorageOperationInFlight)
    #expect(controller.activeStorageOperations == 1)

    helper.finishMount()
    await operation.value

    #expect(!controller.hasStorageOperationInFlight)
    #expect(controller.activeStorageOperations == 0)
}

@MainActor
@Test func mountThreadsRequestedMountPointAndReadOnlyThroughToHelper() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive, mountPoint: "/Volumes/My Drive", readOnly: true)

    #expect(fake.mountCalls.count == 1)
    #expect(fake.mountCalls[0].mountPoint == "/Volumes/My Drive")
    #expect(fake.mountCalls[0].readOnly == true)
    #expect(controller.mountedMountPoint == "/Volumes/My Drive")
    // Real bug caught by review: this used to report .mountedReadWrite unconditionally,
    // even for a successful read-only-by-request mount.
    #expect(appState.state == .mountedReadOnly)
}

@MainActor
@Test func mountWithoutReadOnlyTransitionsToMountedReadWrite() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive, readOnly: false)

    #expect(appState.state == .mountedReadWrite)
}

@MainActor
@Test func explicitExperimentalNTFS3SelectionIsOneMountOnlyAndNeverFallsBack() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive, driver: .ntfs3)

    #expect(fake.mountCalls.count == 1)
    #expect(fake.mountCalls[0].driver == .ntfs3)
}

@MainActor
@Test func unmountClearsMountedMountPoint() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive, mountPoint: "/Volumes/My Drive")
    await controller.unmount()

    #expect(controller.mountedMountPoint == nil)
}

@MainActor
@Test func mountDerivesExtDriverForExtDriveAndNtfs3gForNtfs() async {
    // The GUI defaults to .ntfs3g; for an ext drive it must instead send .ext so the helper
    // skips --fs-driver and passes --ignore-permissions (all_squash). PopoverContentView calls
    // mount(drive) with no driver, so the controller must derive it from drive.fsType.
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    let extDrive = Drive(identifier: "disk4s1", fsType: "ext", label: "LinuxVol", size: "31.5 GB")
    await controller.mount(extDrive)
    #expect(fake.mountCalls[0].driver == .ext)

    await controller.mount(sampleDrive)
    #expect(fake.mountCalls.last!.driver == .ntfs3g)
}

@MainActor
@Test func unmountRoutesThroughHelperAndTransitionsToIdle() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive)
    await controller.unmount()

    #expect(fake.unmountCalls == ["disk4s2"])
    #expect(appState.state == .idle)
    #expect(controller.mountedDrive == nil)
    #expect(!controller.hasStorageOperationInFlight)
}

@MainActor
@Test func mountRejectsInvalidDeviceNameWithoutCallingHelper() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)
    let badDrive = Drive(identifier: "not-a-device", fsType: "ntfs", label: "", size: "1.0 GB")

    await controller.mount(badDrive)

    #expect(fake.mountCalls.isEmpty)
    #expect(appState.state == .error)
    #expect(controller.errorMessage != nil)
}

@MainActor
@Test func mountFailureFromHelperTransitionsToError() async {
    let fake = FakeHelper()
    fake.mountResult = .failure(HelperClientError.helper("mount.sh: device busy"))
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive)

    #expect(appState.state == .error)
    #expect(controller.errorMessage == "mount.sh: device busy")
    #expect(controller.mountedDrive == nil)
}

@MainActor
@Test func mountFailureFromNonZeroExitCodeTransitionsToError() async {
    let fake = FakeHelper()
    fake.mountResult = .success(CommandResult(output: "mount.sh: unsupported filesystem", exitCode: 1))
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive)

    #expect(appState.state == .error)
    #expect(controller.errorMessage == "mount.sh: unsupported filesystem")
}

@MainActor
@Test func mountTimeoutUsesAConciseRecoveryMessage() async {
    let fake = FakeHelper()
    fake.mountResult = .success(CommandResult(
        output: "mount: still working (240s elapsed)...\nmount: no response after 240s — backend may be wedged (try 'ntfsmac diagnose')\nmount: failed to mount disk4s2",
        exitCode: 1
    ))
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.mount(sampleDrive)

    #expect(appState.state == .error)
    #expect(controller.errorMessage == "Mount timed out before the private VM became ready. Retry; if it repeats, run Diagnose.")
}

@MainActor
@Test func unsafeWindowsVolumeFailureNeverSurfacesRawBackendTranscript() async {
    let fake = FakeHelper()
    fake.mountResult = .success(CommandResult(
        output: "NTFS is inconsistent. The volume is dirty and the dirty bit is set. Failed to mount /dev/disk4s2.",
        exitCode: 1
    ))
    let appState = AppState()
    let controller = MountController(helper: fake, appState: appState)

    await controller.mount(sampleDrive)

    #expect(appState.state == .error)
    #expect(controller.errorMessage == MountFailureCopy.unsafeWindowsVolume)
    #expect(controller.errorMessage?.contains("disk4s2") == false)
}

@MainActor
@Test func classifiedNTFS3RefusalUsesTheSameConciseRecoveryCopy() async {
    let fake = FakeHelper()
    fake.mountResult = .success(CommandResult(
        output: "mount: NTFS3 read/write refused — Windows left this volume in an unsafe state. Run chkdsk, disable Fast Startup, then fully shut down Windows.",
        exitCode: 1
    ))
    let appState = AppState()
    let controller = MountController(helper: fake, appState: appState)

    await controller.mount(sampleDrive)

    #expect(appState.state == .error)
    #expect(controller.errorMessage == MountFailureCopy.unsafeWindowsVolume)
}

@MainActor
@Test func unmountWithNothingMountedNeverCallsHelper() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)

    await controller.unmount()

    #expect(fake.unmountCalls.isEmpty)
}

@MainActor
@Test func mountRequestingReadWriteButLandingReadOnlyTransitionsToMountedReadOnlyDirty() async {
    // Root-cause fix: `exitCode == 0` on a `readOnly: false` request doesn't guarantee the
    // mount actually landed read-write — ntfs-3g silently falls back to read-only on a dirty
    // journal. Without checking the real mount options, this was reported as a healthy
    // `.mountedReadWrite` and `.mountedReadOnlyDirty` was unreachable from any real mount.
    let fake = FakeHelper()
    fake.snapshotReadOnlyOverride = true
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: true), appState: appState)

    await controller.mount(sampleDrive, readOnly: false)

    #expect(appState.state == .mountedReadOnlyDirty)
    #expect(controller.mountedDrive == sampleDrive)
}

@MainActor
@Test func mountingASecondDriveWhileOneIsMountedMountsBothDrives() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)
    let otherDrive = Drive(identifier: "disk5s1", fsType: "exfat", label: "Other", size: "64.0 GB")

    await controller.mount(sampleDrive)
    await controller.mount(otherDrive)

    #expect(fake.mountCalls.count == 2)
    #expect(controller.mountedDriveIDs == Set(["disk4s2", "disk5s1"]))
    #expect(appState.state == .mountedReadWrite)
}

@MainActor
@Test func unmountTargetsSpecificDriveAndLeavesOthersMounted() async {
    let fake = FakeHelper()
    let appState = AppState()
    let notifier = RecordingMountNotifier()
    let controller = MountController(
        helper: fake,
        readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false),
        notifier: notifier,
        appState: appState
    )
    let otherDrive = Drive(identifier: "disk5s1", fsType: "ext4", label: "ExtVol", size: "32.0 GB")

    await controller.mount(sampleDrive)
    await controller.mount(otherDrive)
    await controller.unmount(driveID: sampleDrive.identifier)

    #expect(fake.unmountCalls == ["disk4s2"])
    #expect(controller.mountedDriveIDs == Set(["disk5s1"]))
    #expect(appState.state == .mountedReadWrite)
    #expect(notifier.events.contains(.unmounted(volumeName: "My Drive")))
}

@MainActor
@Test func unmountingLastDriveReturnsToIdle() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(helper: fake, readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false), appState: appState)
    let otherDrive = Drive(identifier: "disk5s1", fsType: "ext4", label: "ExtVol", size: "32.0 GB")

    await controller.mount(sampleDrive)
    await controller.mount(otherDrive)
    await controller.unmount(driveID: sampleDrive.identifier)
    await controller.unmount(driveID: otherDrive.identifier)

    #expect(controller.mountedDriveIDs.isEmpty)
    #expect(appState.state == .idle)
    #expect(!controller.hasStorageOperationInFlight)
}

@MainActor
@Test func ejectAllContinuesAfterFailureAndPreservesRecoveryControls() async {
    let fake = FakeHelper()
    fake.unmountResultsByTarget["disk4s2"] = .success(
        CommandResult(output: "device busy", exitCode: 1)
    )
    let appState = AppState()
    let notifier = RecordingMountNotifier()
    let controller = MountController(
        helper: fake,
        readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false),
        notifier: notifier,
        appState: appState
    )
    let otherDrive = Drive(
        identifier: "disk5s1",
        fsType: "ext4",
        label: "ExtVol",
        size: "32.0 GB"
    )

    await controller.mount(sampleDrive)
    await controller.mount(otherDrive)
    await controller.ejectAll()

    #expect(fake.unmountCalls == ["disk4s2", "disk5s1"])
    #expect(controller.mountedDriveIDs == Set(["disk4s2"]))
    #expect(controller.mountedDrives.first?.isVerified == true)
    #expect(appState.state == .mountedReadWrite)
    #expect(controller.lastEjectAllReport == EjectAllReport(results: [
        EjectDriveResult(id: "disk4s2", volumeName: "My Drive", status: .helperFailed),
        EjectDriveResult(id: "disk5s1", volumeName: "ExtVol", status: .unmounted),
    ]))
    #expect(notifier.events.last == .ejectAll(succeeded: 1, total: 2))

    // The failed row remains actionable: retrying its normal per-drive Unmount can recover.
    fake.unmountResultsByTarget["disk4s2"] = .success(CommandResult(output: "unmounted", exitCode: 0))
    await controller.unmount(driveID: "disk4s2")
    #expect(controller.mountedDriveIDs.isEmpty)
    #expect(controller.lastEjectAllReport == nil)
}

@MainActor
@Test func ejectAllPublishesOneSuccessfulResultPerDrive() async {
    let fake = FakeHelper()
    let appState = AppState()
    let controller = MountController(
        helper: fake,
        readOnlyChecker: FakeReadOnlyChecker(isReadOnly: false),
        appState: appState
    )
    let otherDrive = Drive(
        identifier: "disk5s1",
        fsType: "ext4",
        label: "ExtVol",
        size: "32.0 GB"
    )

    await controller.mount(sampleDrive)
    await controller.mount(otherDrive)
    await controller.ejectAll()

    #expect(controller.lastEjectAllReport?.succeededCount == 2)
    #expect(controller.lastEjectAllReport?.allSucceeded == true)
    #expect(controller.mountedDriveIDs.isEmpty)
    #expect(appState.state == .idle)
}
