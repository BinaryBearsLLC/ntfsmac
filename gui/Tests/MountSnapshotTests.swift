import HelperShared
import Testing
@testable import NtfsmacGUI

@MainActor
private final class MutableSnapshotProvider: MountSnapshotProviding {
    var value: MountSnapshot

    init(_ value: MountSnapshot) {
        self.value = value
    }

    func snapshot() async -> MountSnapshot { value }
}

@MainActor
private final class SequenceSnapshotProvider: MountSnapshotProviding {
    private var values: [MountSnapshot]

    init(_ values: [MountSnapshot]) {
        self.values = values
    }

    func snapshot() async -> MountSnapshot {
        guard values.count > 1 else { return values[0] }
        return values.removeFirst()
    }
}

@MainActor
private final class SuccessfulHelper: HelperMounting {
    private(set) var unmountCalls: [String] = []
    var unmountResult = CommandResult(output: "unmounted", exitCode: 0)

    func mount(
        device: String,
        driver: FsDriver,
        mountPoint: String?,
        readOnly: Bool
    ) async throws -> CommandResult {
        CommandResult(
            output: "/dev/\(device) was mounted as \(mountPoint ?? "/Volumes/\(device)")",
            exitCode: 0
        )
    }

    func unmount(target: String) async throws -> CommandResult {
        unmountCalls.append(target)
        return unmountResult
    }
}

@MainActor
private final class DelayedMountHelper: HelperMounting {
    func mount(
        device: String,
        driver: FsDriver,
        mountPoint: String?,
        readOnly: Bool
    ) async throws -> CommandResult {
        try await Task.sleep(for: .milliseconds(150))
        return CommandResult(output: "mount failed after delay", exitCode: 1)
    }

    func unmount(target: String) async throws -> CommandResult {
        CommandResult(output: "unused", exitCode: 0)
    }
}

private struct AlwaysReadWrite: MountReadOnlyChecking {
    func isAnyNfsMountReadOnly() async -> Bool { false }
}

private struct SnapshotCommandRunner: PrivilegedCommandRunning {
    let status: CommandResult
    let mount: CommandResult

    func run(_ executablePath: String, _ arguments: [String]) -> CommandResult {
        executablePath == "/test/anylinuxfs" ? status : mount
    }

    func runPipingStdin(
        _ input: String,
        to executablePath: String,
        _ arguments: [String]
    ) -> CommandResult {
        CommandResult(output: "unused", exitCode: 1)
    }
}

@Test func parsesAnyLinuxFSStatusWithoutRetainingMountedByIdentity() {
    let output = """
    /dev/disk6s1 on /Volumes/My Drive (ntfs-3g, mounted by local-user) VM[cpus: 2, ram: 1024 MiB]
    malformed diagnostic line
    disk7s2 on /Volumes/Linux (ext4, ro, mounted by another-user) VM[cpus: 2, ram: 1024 MiB]
    """

    let mounts = AnyLinuxFSStatusParser.parse(output)

    #expect(mounts.count == 2)
    #expect(mounts[0].deviceIdentifier == "disk6s1")
    #expect(mounts[0].mountPoint == "/Volumes/My Drive")
    #expect(mounts[0].fsDriver == "ntfs-3g")
    #expect(mounts[0].isReadOnly == false)
    #expect(mounts[1].isReadOnly == true)
    #expect(mounts.allSatisfy { !$0.mountPoint.contains("user") })
}

@Test func parsesHostNfsMountOptionsAndDeviceHostnameSuffix() {
    let output = """
    disk6s1.local:/mnt/My\\040Drive on /Volumes/My\\040Drive (nfs, nodev, nosuid, soft, mounted by local-user)
    disk7s2-1.local:/mnt/Linux on /Volumes/Linux (nfs, nodev, read-only, soft)
    server.example:/share on /Volumes/Other (nfs, soft)
    """

    let mounts = MountTableParser.parse(output)

    #expect(mounts.count == 3)
    #expect(mounts[0].deviceIdentifier == "disk6s1")
    #expect(mounts[0].mountPoint == "/Volumes/My Drive")
    #expect(mounts[0].isReadOnly == false)
    #expect(mounts[1].deviceIdentifier == "disk7s2")
    #expect(mounts[1].isReadOnly == true)
    #expect(mounts[2].deviceIdentifier == nil)
}

@Test func parsesExternalPhysicalPartitionsWithoutWholeDisks() {
    let output = """
    /dev/disk4 (external, physical):
       0: GUID_partition_scheme *16.0 GB disk4
       1: Microsoft Basic Data USB_8GB 16.0 GB disk4s1
    /dev/disk7 (external, physical):
       0: FDisk_partition_scheme *32.0 GB disk7
       1: Windows_NTFS DATA 32.0 GB disk7s2
    """

    #expect(ExternalPhysicalDeviceParser.parse(output) == Set(["disk4s1", "disk7s2"]))
}

@Test func livenessProbeSkipsPhysicallyRemovedMountButKeepsSurvivor() {
    let removed = ObservedMount(
        deviceIdentifier: "disk6s1",
        mountPoint: "/Volumes/Removed"
    )
    let survivor = ObservedMount(
        deviceIdentifier: "disk7s2",
        mountPoint: "/Volumes/Survivor"
    )

    let candidates = RealMountSnapshotProvider.livenessProbeCandidates(
        [removed, survivor],
        physicallyPresentDeviceIDs: Set([survivor.deviceIdentifier])
    )

    #expect(candidates == [survivor])
    #expect(RealMountSnapshotProvider.livenessProbeCandidates(
        [removed, survivor],
        physicallyPresentDeviceIDs: nil
    ) == [removed, survivor])
}

@Test func physicalRemovalSnapshotUsesHostIdentityWithoutRuntimeStatus() {
    let removed = NFSMountTableEntry(
        source: "disk6s1.local:/mnt/Removed",
        mountPoint: "/Volumes/Removed",
        isReadOnly: false,
        deviceIdentifier: "disk6s1"
    )
    let survivor = NFSMountTableEntry(
        source: "disk7s2.local:/mnt/Survivor",
        mountPoint: "/Volumes/Survivor",
        isReadOnly: false,
        deviceIdentifier: "disk7s2"
    )

    let snapshot = RealMountSnapshotProvider.physicalRemovalSnapshot(
        tableMounts: [removed, survivor],
        physicallyPresentDeviceIDs: Set(["disk7s2"])
    )

    #expect(snapshot?.warningCode == "PHYSICAL_DEVICE_MISSING")
    #expect(snapshot?.isAuthoritative == false)
    #expect(snapshot?.mounts.map(\.deviceIdentifier) == ["disk6s1", "disk7s2"])
    #expect(snapshot?.physicallyPresentDeviceIDs == Set(["disk7s2"]))
}

@MainActor
@Test func tableOnlyNtfsmacMountIsInconsistentRatherThanAuthoritativeGreen() async {
    let runner = SnapshotCommandRunner(
        status: CommandResult(output: "", exitCode: 0),
        mount: CommandResult(
            output: "disk6s1.local:/mnt/Media on /Volumes/Media (nfs, soft)",
            exitCode: 0
        )
    )
    let provider = RealMountSnapshotProvider(
        runner: runner,
        anylinuxfsPath: "/test/anylinuxfs",
        mountPath: "/test/mount"
    )

    let snapshot = await provider.snapshot()

    #expect(snapshot.mounts.count == 1)
    #expect(snapshot.isAuthoritative == false)
    #expect(snapshot.warningCode == "MOUNT_STATE_INCONSISTENT")
}

@MainActor
@Test func guestReadOnlyOverridesAReadWriteNfsClientMount() async {
    let runner = SnapshotCommandRunner(
        status: CommandResult(
            output: "/dev/disk6s1 on /Volumes/Media (ntfs, ro, norecover, uid=502, gid=20, mounted by local-user) VM[cpus: 1, ram: 512 MiB]",
            exitCode: 0
        ),
        mount: CommandResult(
            output: "disk6s1.local:/mnt/Media on /Volumes/Media (nfs, nodev, nosuid, soft, mounted by local-user)",
            exitCode: 0
        )
    )
    let provider = RealMountSnapshotProvider(
        runner: runner,
        anylinuxfsPath: "/test/anylinuxfs",
        mountPath: "/test/mount"
    )

    let snapshot = await provider.snapshot()

    #expect(snapshot.isAuthoritative)
    #expect(snapshot.mounts.count == 1)
    #expect(snapshot.mounts[0].isReadOnly == true)
}

@MainActor
@Test func authoritativeExternalUnmountClearsAStaleGuiRow() async {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [
        ObservedMount(
            deviceIdentifier: drive.identifier,
            mountPoint: "/Volumes/Media",
            fsDriver: "ntfs-3g",
            isReadOnly: false
        ),
    ]))
    let appState = AppState()
    let helper = SuccessfulHelper()
    let controller = MountController(
        helper: helper,
        readOnlyChecker: AlwaysReadWrite(),
        snapshotProvider: provider,
        appState: appState
    )
    await controller.mount(drive, mountPoint: "/Volumes/Media")
    #expect(appState.state == .mountedReadWrite)

    provider.value = MountSnapshot(mounts: [])
    await controller.reconcile(knownDrives: [drive])

    #expect(helper.unmountCalls == [drive.identifier])
    #expect(controller.mountedDrives.isEmpty)
    #expect(appState.state == .idle)
}

@MainActor
@Test func physicalRemovalOverridesStaleRuntimeAndMountTableTruth() async {
    let removed = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let survivor = Drive(identifier: "disk7s2", fsType: "ntfs", label: "Backup", size: "32 GB")
    let both = [
        ObservedMount(deviceIdentifier: removed.id, mountPoint: "/Volumes/Media", fsDriver: "ntfs-3g", isReadOnly: false),
        ObservedMount(deviceIdentifier: survivor.id, mountPoint: "/Volumes/Backup", fsDriver: "ntfs-3g", isReadOnly: false),
    ]
    let provider = MutableSnapshotProvider(MountSnapshot(
        mounts: both,
        physicallyPresentDeviceIDs: Set([removed.id, survivor.id])
    ))
    let helper = SuccessfulHelper()
    let appState = AppState()
    let controller = MountController(helper: helper, snapshotProvider: provider, appState: appState)
    await controller.reconcile(knownDrives: [removed, survivor])

    provider.value = MountSnapshot(
        mounts: both,
        isAuthoritative: false,
        warningCode: "PHYSICAL_DEVICE_MISSING",
        physicallyPresentDeviceIDs: Set([survivor.id])
    )
    // The scanner may already have dropped the unplugged partition. Physical evidence still
    // has to invalidate the controller's cached/observed mounted row.
    await controller.reconcile(knownDrives: [survivor])

    #expect(helper.unmountCalls == [removed.id])
    #expect(controller.physicallyMissingDriveIDs == Set([removed.id]))
    #expect(controller.mountedDrives.first { $0.id == removed.id }?.isVerified == false)
    #expect(controller.mountedDrives.first { $0.id == survivor.id }?.isVerified == true)
    #expect(appState.state == .mountedUnknown)
}

@MainActor
@Test func physicalRemovalCleansUncachedCLIMountAndPreservesSurvivor() async {
    let removed = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let survivor = Drive(identifier: "disk7s2", fsType: "ntfs", label: "Backup", size: "32 GB")
    let removedMount = ObservedMount(
        deviceIdentifier: removed.id,
        mountPoint: "/Volumes/Media",
        fsDriver: "ntfs3",
        isReadOnly: false
    )
    let survivorMount = ObservedMount(
        deviceIdentifier: survivor.id,
        mountPoint: "/Volumes/Backup",
        fsDriver: "ntfs-3g",
        isReadOnly: false
    )
    let provider = SequenceSnapshotProvider([
        MountSnapshot(
            mounts: [removedMount, survivorMount],
            isAuthoritative: false,
            warningCode: "PHYSICAL_DEVICE_MISSING",
            physicallyPresentDeviceIDs: Set([survivor.id])
        ),
        MountSnapshot(
            mounts: [survivorMount],
            physicallyPresentDeviceIDs: Set([survivor.id])
        ),
    ])
    let helper = SuccessfulHelper()
    let appState = AppState()
    let controller = MountController(helper: helper, snapshotProvider: provider, appState: appState)

    // No prior GUI mount/reconcile: this is the CLI-mount race observed on hardware.
    await controller.reconcile(knownDrives: [survivor])

    #expect(helper.unmountCalls == [removed.id])
    #expect(controller.mountedDriveIDs == Set([survivor.id]))
    #expect(controller.mountedDrives.first?.isVerified == true)
    #expect(appState.state == .mountedReadWrite)
}

@MainActor
@Test func backendFailureRemovesGreenThenDebouncesExactCleanup() async {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let observed = ObservedMount(
        deviceIdentifier: drive.id,
        mountPoint: "/Volumes/Media",
        fsDriver: "ntfs-3g",
        isReadOnly: false
    )
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [observed]))
    let helper = SuccessfulHelper()
    let appState = AppState()
    let controller = MountController(helper: helper, snapshotProvider: provider, appState: appState)
    await controller.reconcile(knownDrives: [drive])

    provider.value = MountSnapshot(
        mounts: [observed],
        isAuthoritative: false,
        warningCode: "MOUNT_BACKEND_UNRESPONSIVE",
        unresponsiveDeviceIDs: Set([drive.id])
    )
    await controller.reconcile(knownDrives: [drive])
    #expect(helper.unmountCalls.isEmpty)
    #expect(appState.state == .mountedUnknown)

    await controller.reconcile(knownDrives: [drive])
    #expect(helper.unmountCalls == [drive.id])
    #expect(appState.state == .mountedUnknown)
}

@MainActor
@Test func pollingCannotPublishIdleWhileAHelperMountIsStillRunning() async throws {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: []))
    let appState = AppState()
    let controller = MountController(
        helper: DelayedMountHelper(),
        readOnlyChecker: AlwaysReadWrite(),
        snapshotProvider: provider,
        appState: appState
    )

    let mountTask = Task { await controller.mount(drive) }
    try await Task.sleep(for: .milliseconds(25))
    #expect(appState.state == .mounting)

    await controller.reconcile(knownDrives: [drive])
    #expect(appState.state == .mounting)

    await mountTask.value
    #expect(appState.state == .error)
    #expect(controller.errorMessage == "mount failed after delay")
}

@MainActor
@Test func finderUnmountRequiresRepeatedInconsistentProofBeforeSessionCleanup() async {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [
        ObservedMount(
            deviceIdentifier: drive.identifier,
            mountPoint: "/Volumes/Media",
            fsDriver: "ntfs-3g",
            isReadOnly: false
        ),
    ]))
    let helper = SuccessfulHelper()
    let appState = AppState()
    let controller = MountController(
        helper: helper,
        readOnlyChecker: AlwaysReadWrite(),
        snapshotProvider: provider,
        appState: appState
    )
    await controller.mount(drive, mountPoint: "/Volumes/Media")

    provider.value = MountSnapshot(
        mounts: [ObservedMount(
            deviceIdentifier: drive.identifier,
            mountPoint: "/Volumes/Media",
            fsDriver: "ntfs-3g",
            isReadOnly: nil
        )],
        isAuthoritative: false,
        warningCode: "MOUNT_STATE_INCONSISTENT"
    )

    await controller.reconcile(knownDrives: [drive])
    #expect(helper.unmountCalls.isEmpty)
    #expect(appState.state == .mountedUnknown)

    await controller.reconcile(knownDrives: [drive])
    #expect(helper.unmountCalls == [drive.identifier])
    #expect(appState.state == .mountedUnknown)

    provider.value = MountSnapshot(mounts: [])
    await controller.reconcile(knownDrives: [drive])
    #expect(controller.mountedDrives.isEmpty)
    #expect(appState.state == .idle)
}

@MainActor
@Test func failedExternalUnmountCleanupCannotFallBackToIdle() async {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [
        ObservedMount(
            deviceIdentifier: drive.identifier,
            mountPoint: "/Volumes/Media",
            fsDriver: "ntfs-3g",
            isReadOnly: false
        ),
    ]))
    let helper = SuccessfulHelper()
    helper.unmountResult = CommandResult(output: "failed", exitCode: 1)
    let appState = AppState()
    let controller = MountController(
        helper: helper,
        readOnlyChecker: AlwaysReadWrite(),
        snapshotProvider: provider,
        appState: appState
    )
    await controller.mount(drive, mountPoint: "/Volumes/Media")

    provider.value = MountSnapshot(mounts: [])
    await controller.reconcile(knownDrives: [drive])

    #expect(helper.unmountCalls == [drive.identifier])
    #expect(controller.mountedDrives.isEmpty)
    #expect(appState.state == .error)
    #expect(controller.errorMessage?.hasPrefix("EXTERNAL_UNMOUNT_CLEANUP_UNPROVEN") == true)
    #expect(controller.reconciliationWarning == controller.errorMessage)
}

@MainActor
@Test func cliCreatedMountAppearsWithoutAGuiMountAction() async {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [
        ObservedMount(
            deviceIdentifier: drive.identifier,
            mountPoint: "/Volumes/Media",
            fsDriver: "ntfs-3g",
            isReadOnly: false
        ),
    ]))
    let appState = AppState()
    let controller = MountController(
        helper: SuccessfulHelper(),
        snapshotProvider: provider,
        appState: appState
    )

    await controller.reconcile(knownDrives: [drive])

    #expect(controller.mountedDrive == drive)
    #expect(controller.mountedMountPoint == "/Volumes/Media")
    #expect(appState.state == .mountedReadWrite)
}

@MainActor
@Test func unavailableSnapshotPreservesRowsButRemovesTheFalseGreenState() async {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [
        ObservedMount(
            deviceIdentifier: drive.identifier,
            mountPoint: "/Volumes/Media",
            fsDriver: "ntfs-3g",
            isReadOnly: false
        ),
    ]))
    let appState = AppState()
    let controller = MountController(
        helper: SuccessfulHelper(),
        readOnlyChecker: AlwaysReadWrite(),
        snapshotProvider: provider,
        appState: appState
    )
    await controller.mount(drive, mountPoint: "/Volumes/Media")

    provider.value = MountSnapshot(
        mounts: [],
        isAuthoritative: false,
        warningCode: "MOUNT_STATE_SOURCE_UNAVAILABLE"
    )
    await controller.reconcile(knownDrives: [drive])

    #expect(controller.mountedDrive == drive)
    #expect(controller.mountedDrives.first?.isVerified == false)
    #expect(appState.state == .mountedUnknown)
    #expect(controller.reconciliationWarning?.hasPrefix("MOUNT_STATE_SOURCE_UNAVAILABLE") == true)
}

@MainActor
@Test func unavailableSnapshotDoesNotWarnWhenThereIsNoMountClaimToVerify() async {
    let provider = MutableSnapshotProvider(MountSnapshot(
        mounts: [],
        isAuthoritative: false,
        warningCode: "MOUNT_STATE_SOURCE_UNAVAILABLE"
    ))
    let appState = AppState()
    let controller = MountController(
        helper: SuccessfulHelper(),
        snapshotProvider: provider,
        appState: appState
    )

    await controller.reconcile(knownDrives: [])

    #expect(controller.mountedDrives.isEmpty)
    #expect(controller.reconciliationWarning == nil)
    #expect(appState.state == .idle)
}

@MainActor
@Test func oneDisappearingMountDoesNotEraseTheSurvivingMount() async {
    let first = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let second = Drive(identifier: "disk7s2", fsType: "ext4", label: "Linux", size: "32 GB")
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [
        ObservedMount(deviceIdentifier: first.identifier, mountPoint: "/Volumes/Media", fsDriver: "ntfs-3g", isReadOnly: false),
        ObservedMount(deviceIdentifier: second.identifier, mountPoint: "/Volumes/Linux", fsDriver: "ext4", isReadOnly: false),
    ]))
    let appState = AppState()
    let controller = MountController(
        helper: SuccessfulHelper(),
        snapshotProvider: provider,
        appState: appState
    )
    await controller.reconcile(knownDrives: [first, second])

    provider.value = MountSnapshot(mounts: [
        ObservedMount(deviceIdentifier: second.identifier, mountPoint: "/Volumes/Linux", fsDriver: "ext4", isReadOnly: false),
    ])
    await controller.reconcile(knownDrives: [first, second])

    #expect(controller.mountedDriveIDs == Set([second.identifier]))
    #expect(appState.state == .mountedReadWrite)
}

@MainActor
@Test func successfulUnmountResponseCannotHideAStillObservedMount() async {
    let drive = Drive(identifier: "disk6s1", fsType: "ntfs", label: "Media", size: "120 GB")
    let observed = ObservedMount(
        deviceIdentifier: drive.identifier,
        mountPoint: "/Volumes/Media",
        fsDriver: "ntfs-3g",
        isReadOnly: false
    )
    let provider = MutableSnapshotProvider(MountSnapshot(mounts: [observed]))
    let helper = SuccessfulHelper()
    let appState = AppState()
    let controller = MountController(
        helper: helper,
        readOnlyChecker: AlwaysReadWrite(),
        snapshotProvider: provider,
        appState: appState
    )
    await controller.mount(drive, mountPoint: "/Volumes/Media")

    await controller.unmount(driveID: drive.identifier)

    #expect(helper.unmountCalls == [drive.identifier])
    #expect(controller.mountedDrive == drive)
    #expect(appState.state == .mountedUnknown)
    #expect(controller.reconciliationWarning?.hasPrefix("UNMOUNT_NOT_OBSERVED") == true)
}
