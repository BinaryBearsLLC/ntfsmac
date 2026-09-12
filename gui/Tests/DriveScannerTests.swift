import Foundation
import Testing
import HelperShared
@testable import NtfsmacGUI

// GUI-PLAN.md "Auto-detect compatible drives" — real `anylinuxfs list --microsoft` output shape:
// `diskutil list`, augmented in place (TYPE/NAME columns swapped for real fs_type/label at fixed
// widths, `vendor/src/anylinuxfs/anylinuxfs/src/diskutil/{mod,darwin}.rs`). Samples below are
// hand-built to match that real column layout, not fabricated JSON.

private let sampleListOutput = """
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *500.1 GB   disk4
   1:                       ntfs My Drive                500.0 GB   disk4s2
"""

private let sampleMultiDiskOutput = """
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *500.1 GB   disk4
   1:                       ntfs My Drive                500.0 GB   disk4s2

/dev/disk5 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:  FDisk_partition_scheme                            *64.0 GB    disk5
   1:                      exfat                          64.0 GB    disk5s1
"""

@Test func parsesNtfsPartitionSkippingHeaderAndWholeDiskRows() {
    let drives = DriveListParser.parse(sampleListOutput)
    #expect(drives.count == 1)
    #expect(drives[0].identifier == "disk4s2")
    #expect(drives[0].fsType == "ntfs")
    #expect(drives[0].label == "My Drive")
    #expect(drives[0].size == "500.0 GB")
}

@Test func parsesMultipleDisksButExcludesExfatAlreadySupportedByMacOS() {
    // macOS reads/writes exFAT natively, so ntfsmac must NOT surface exfat partitions —
    // only NTFS (needs write help) + ext (unsupported by macOS) + BitLocker are in scope.
    // The exfat partition in the multi-disk fixture must be filtered client-side.
    let drives = DriveListParser.parse(sampleMultiDiskOutput)
    #expect(drives.count == 1)
    #expect(drives.map(\.identifier) == ["disk4s2"])
    #expect(drives.allSatisfy { $0.fsType != "exfat" })
}

@Test func emptyOutputYieldsNoDrives() {
    #expect(DriveListParser.parse("").isEmpty)
}

@Test func malformedLinesAreSkippedNotCrashed() {
    let garbage = "this is not a diskutil line at all\n???\n\t\n"
    #expect(DriveListParser.parse(garbage).isEmpty)
}

@Test func rejectsIdentifierMissingPartitionSuffix() {
    // A whole-disk-only line (no `sN` suffix) must never parse as a mountable drive (L6).
    let wholeDiskOnly = "   0:      GUID_partition_scheme                        *500.1 GB   disk4"
    #expect(DriveListParser.parse(wholeDiskOnly).isEmpty)
}

@MainActor
@Test func driveListViewShowsEmptyPlaceholderWhenNoDrivesDetected() {
    // Acceptance: "render idle cleanly when empty" — DriveListView must not crash/hang on [].
    let view = DriveListView(drives: [])
    #expect(view.drives.isEmpty)
}

// ext2/3/4 list support — combine the family-specific anylinuxfs probes and retain a client-side
// allow-set {ntfs,BitLocker,ext2,ext3,ext4}.
// Surfaces ext partitions, keeps out-of-scope Linux FS (btrfs/xfs/zfs/LUKS/LVM) hidden. Mirrors
// tests/cli/list-drives.bats — bash and Swift can't share source, two impls kept in sync
// deliberately (per cli/lib/list-drives.sh header comment).

private let sampleExtOutput = """
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:      GUID_partition_scheme                        *500.1 GB   disk4
   1:                       ntfs My Drive                500.0 GB   disk4s2
   2:                       ext4 LinuxVol                  50.0 GB   disk4s3
   3:                       btrfs BtrVol                   20.0 GB   disk4s4
"""

// Captured layout from a multi-partition MBR SSD. Unprivileged blkid cannot read
// the superblocks, so both Linux siblings retain their partition-family name.
private let sampleMBRLinuxOutput = """
/dev/disk4 (external, physical):
   #:                       TYPE NAME                    SIZE       IDENTIFIER
   0:     FDisk_partition_scheme                        *1.0 TB     disk4
   1:             Windows_FAT_32 bootfs                  536.9 MB   disk4s1
   2:                      Linux                         124.0 GB   disk4s2
   3:                      Linux                         875.7 GB   disk4s3
"""

@Test func parsesEveryMBRLinuxSiblingWithoutInventingLabels() {
    #expect(DriveListParser.parse(sampleMBRLinuxOutput) == [
        Drive(identifier: "disk4s2", fsType: "ext", label: "", size: "124.0 GB"),
        Drive(identifier: "disk4s3", fsType: "ext", label: "", size: "875.7 GB"),
    ])
}

@Test func mbrLinuxFallbackPreservesLabelsAndRejectsOtherLinuxPartitionFamilies() {
    let output = """
       1:                      Linux My Linux Volume          12.0 GB   disk5s1
       2:                  Linux LVM                          12.0 GB   disk5s2
       3:                  Linux_LVM                          12.0 GB   disk5s3
       4:                 Linux_RAID                          12.0 GB   disk5s4
       5:                 Linux Swap                          12.0 GB   disk5s5
       6:                      btrfs                          12.0 GB   disk5s6
       7:                crypto_LUKS                          12.0 GB   disk5s7
       8:                      Linux                          12.0 GB   disk5
    """
    #expect(DriveListParser.parse(output) == [
        Drive(identifier: "disk5s1", fsType: "ext", label: "My Linux Volume", size: "12.0 GB")
    ])
}

@MainActor
@Test func scanRefreshKeepsEveryMBRSiblingAndRemovesDisconnectedPartitions() async {
    let runner = FakeListRunner(output: sampleMBRLinuxOutput)
    let scanner = DriveScanner(runner: runner, anylinuxfsPath: "/stub/anylinuxfs")
    await scanner.refresh()
    #expect(scanner.drives.map(\.identifier) == ["disk4s2", "disk4s3"])
    #expect(scanner.drives.allSatisfy { MountController.driverFor($0.fsType) == .ext })
    runner.output = sampleMBRLinuxOutput.replacingOccurrences(
        of: "   2:                      Linux                         124.0 GB   disk4s2", with: ""
    )
    await scanner.refresh()
    #expect(scanner.drives.map(\.identifier) == ["disk4s3"])
    runner.output = ""
    await scanner.refresh()
    #expect(scanner.drives.isEmpty)
}

@Test func parsesExt4PartitionWithCorrectFsType() {
    let drives = DriveListParser.parse(sampleExtOutput)
    let ext4 = drives.first { $0.identifier == "disk4s3" }
    #expect(ext4 != nil)
    #expect(ext4?.fsType == "ext4")
    #expect(ext4?.label == "LinuxVol")
    #expect(ext4?.size == "50.0 GB")
}

@Test func excludesOutOfScopeFilesystemsFromUnfilteredList() {
    // btrfs is NOT in the allow-set — must be dropped client-side once the scanner switches to
    // bare `anylinuxfs list` (which returns all Linux FS types). Currently RED: DriveListParser
    // has no fstype filter, so btrfs (disk4s4) would be surfaced.
    let drives = DriveListParser.parse(sampleExtOutput)
    #expect(drives.map(\.identifier) == ["disk4s2", "disk4s3"])   // ntfs + ext4 only
    #expect(drives.allSatisfy { $0.fsType != "btrfs" })
}

@Test func rejectsUnresolvedMicrosoftBasicDataPartitionType() {
    // GPT basic data also hosts exFAT: partition metadata alone cannot establish NTFS.
    let realNtfsOutput = """
    /dev/disk4 (external, physical):
       #:                       TYPE NAME                    SIZE       IDENTIFIER
       0:      GUID_partition_scheme                        *500.1 GB   disk4
       4:       Microsoft Basic Data Media                   224.2 GB   disk4s4
    """
    let drives = DriveListParser.parse(realNtfsOutput)
    #expect(drives.isEmpty)
}

@Test func rejectsUnresolvedUnlabeledWindowsNtfsPartitionType() {
    // MBR 0x07 is shared by NTFS and exFAT even though diskutil calls it Windows_NTFS.
    let realMbrNtfsOutput = """
    /dev/disk4 (external, physical):
       #:                       TYPE NAME                    SIZE       IDENTIFIER
       0:     FDisk_partition_scheme                        *248.0 GB   disk4
       1:               Windows_NTFS                         248.0 GB   disk4s1
    """
    let drives = DriveListParser.parse(realMbrNtfsOutput)
    #expect(drives.isEmpty)
}

@Test func rejectsUnresolvedLabeledWindowsNtfsPartitionType() {
    // A label does not turn an ambiguous partition type into filesystem evidence.
    let realMbrNtfsOutput = """
    /dev/disk5 (external, physical):
       #:                       TYPE NAME                    SIZE       IDENTIFIER
       0:     FDisk_partition_scheme                        *8.1 GB     disk5
       1:               Windows_NTFS USB_8GB                 8.1 GB     disk5s1
    """
    let drives = DriveListParser.parse(realMbrNtfsOutput)
    #expect(drives.isEmpty)
}

@Test func mixedDevicesUseOnlyTheirOwnConfirmedFilesystem() {
    let output = """
       1:                        ntfs MobileData             123.0 GB   disk4s1
       1:                       exfat Retroid_SD              62.5 GB   disk5s1
       1:               Windows_NTFS TEST_USB               123.0 GB   disk6s1
       1:                     Unknown UnknownVolume           32.0 GB   disk7s1
    """
    #expect(DriveListParser.parse(output) == [
        Drive(identifier: "disk4s1", fsType: "ntfs", label: "MobileData", size: "123.0 GB")
    ])
    let reformatted = output.replacingOccurrences(of: "exfat Retroid_SD", with: "ntfs Retroid_SD")
    #expect(DriveListParser.parse(reformatted).map(\.identifier) == ["disk4s1", "disk5s1"])
    #expect(DriveListParser.parse(output).map(\.identifier) == ["disk4s1"])
}

@Test func parsesExtWithRealLinuxFilesystemTypeColumn() {
    // Real anylinuxfs list output for ext when blkid can't resolve the superblock: blkid fs_type
    // is empty, so darwin::augment_line falls back to the raw GPT type name "Linux Filesystem" for
    // the TYPE column (vendor/.../diskutil/darwin.rs: fs_type.unwrap_or(part_type); the GPT name
    // is in LINUX_PART_TYPES, mod.rs:257). The GPT name does NOT distinguish ext2/3/4, so the
    // parser must map the whole "Linux Filesystem" prefix to a generic "ext" fstype — taking the
    // first token "Linux" instead leaves the row rejected by allowedFsTypes. This is the ext
    // equivalent of the NTFS "Microsoft Basic Data" regression above. Fixture is the real
    // output shape from /usr/local/ntfsmac/bin/anylinuxfs list against an ext disk.
    let realExtOutput = """
    /dev/disk4 (external, physical):
       #:                       TYPE NAME                    SIZE       IDENTIFIER
       0:      GUID_partition_scheme                        *31.5 GB    disk4
       1:                       Linux Filesystem              31.5 GB    disk4s1
    """
    let drives = DriveListParser.parse(realExtOutput)
    #expect(drives.count == 1)
    #expect(drives[0].identifier == "disk4s1")
    #expect(drives[0].fsType == "ext")
    #expect(drives[0].label.isEmpty)
    #expect(drives[0].size == "31.5 GB")
}

@Test func parsesExtWithRealLinuxFilesystemTypeColumnAndLabel() {
    // Same GPT-name fallback as above, but the partition carries a volume label in the NAME
    // column. The parser must strip the "Linux Filesystem" prefix and keep the label, not
    // treat "Filesystem" as the label.
    let realExtLabeledOutput = """
    /dev/disk4 (external, physical):
       #:                       TYPE NAME                    SIZE       IDENTIFIER
       0:      GUID_partition_scheme                        *31.5 GB    disk4
       1:                       Linux Filesystem MyVol        31.5 GB    disk4s1
    """
    let drives = DriveListParser.parse(realExtLabeledOutput)
    #expect(drives.count == 1)
    #expect(drives[0].identifier == "disk4s1")
    #expect(drives[0].fsType == "ext")
    #expect(drives[0].label == "MyVol")
}

@MainActor
@Test func driveScannerCombinesMicrosoftAndLinuxProbes() async {
    // Live anylinuxfs 0.18.0 evidence on macOS 26.6.1: bare `list` can return no rows while
    // `--microsoft` finds the connected NTFS disk. Query both mutually-exclusive families so
    // NTFS reliability does not regress while ext partitions remain visible.
    let runner = FakeListRunner()
    let scanner = DriveScanner(runner: runner, anylinuxfsPath: "/stub/anylinuxfs")
    await scanner.refresh()
    // Tuples aren't Equatable; compare element-wise.
    #expect(runner.calls.count == 2)
    #expect(runner.calls[0].path == "/stub/anylinuxfs")
    #expect(runner.calls[0].args == ["list", "--microsoft"])
    #expect(runner.calls[1].path == "/stub/anylinuxfs")
    #expect(runner.calls[1].args == ["list", "--linux"])
    #expect(scanner.drives.map(\.identifier) == ["disk4s2", "disk4s3"])
    #expect(scanner.hasCompletedInitialScan)
    #expect(!scanner.isRefreshing)
}

@MainActor
@Test func coldRuntimeScanIsSequentialAndConcurrentRefreshesJoinIt() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: tempDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let microsoftStarted = tempDirectory.appendingPathComponent("microsoft-started")
    let linuxStarted = tempDirectory.appendingPathComponent("linux-started")
    let releaseMicrosoft = tempDirectory.appendingPathComponent("release-microsoft")
    let calls = tempDirectory.appendingPathComponent("calls")
    let controlledList = tempDirectory.appendingPathComponent("controlled-list")
    try """
    #!/bin/sh
    printf '%s\\n' "$*" >> "\(calls.path)"
    if [ "$2" = "--microsoft" ]; then
      : > "\(microsoftStarted.path)"
      while [ ! -e "\(releaseMicrosoft.path)" ]; do
        sleep 0.01
      done
    else
      : > "\(linuxStarted.path)"
    fi
    exit 0
    """.write(
        to: controlledList,
        atomically: true,
        encoding: .utf8
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: controlledList.path
    )

    let scanner = DriveScanner(
        anylinuxfsPath: controlledList.path,
        scanTimeout: 1,
        initialScanTimeout: 2
    )
    let firstRefresh = Task { await scanner.refresh() }
    let microsoftBegan = await Task.detached {
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: microsoftStarted.path) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }.value
    #expect(microsoftBegan)
    #expect(scanner.isRefreshing)
    #expect(!FileManager.default.fileExists(atPath: linuxStarted.path))

    let joinedRefresh = Task { await scanner.refresh() }
    try await Task.sleep(for: .milliseconds(20))
    try Data().write(to: releaseMicrosoft)
    await firstRefresh.value
    await joinedRefresh.value

    let recordedCalls = try String(contentsOf: calls, encoding: .utf8)
        .split(separator: "\n")
        .map(String.init)
    #expect(recordedCalls == ["list --microsoft", "list --linux"])
    #expect(scanner.hasCompletedInitialScan)
    #expect(!scanner.isRefreshing)
    #expect(scanner.lastError == nil)
}

@MainActor
@Test func productionDriveScanDoesNotBlockMainActor() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: tempDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let probeStarted = tempDirectory.appendingPathComponent("probe-started")
    let releaseProbe = tempDirectory.appendingPathComponent("release-probe")
    let slowList = tempDirectory.appendingPathComponent("slow-list")
    try """
    #!/bin/sh
    : > "\(probeStarted.path)"
    while [ ! -e "\(releaseProbe.path)" ]; do
      sleep 0.01
    done
    exit 0
    """.write(
        to: slowList,
        atomically: true,
        encoding: .utf8
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: slowList.path
    )

    let scanner = DriveScanner(anylinuxfsPath: slowList.path, scanTimeout: 2)
    let scanTask = Task { await scanner.refresh() }

    // Wait outside the main actor until the child is running. The child cannot exit until this
    // test resumes on the main actor and writes the release marker. A synchronous production
    // scan would therefore hit DriveScanner's real timeout and fail the assertion below, without
    // relying on a wall-clock scheduling threshold that becomes flaky on a busy CI runner.
    let startedWhileMainActorWasAvailable = await Task.detached {
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: probeStarted.path) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }.value
    #expect(startedWhileMainActorWasAvailable, "the list probe did not start")
    try Data().write(to: releaseProbe)

    await scanTask.value
    #expect(scanner.lastError == nil, "the list probe blocked the main actor until timeout")
}

@MainActor
@Test func productionDriveScanTerminatesAStalledProbe() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: tempDirectory,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let stalledList = tempDirectory.appendingPathComponent("stalled-list")
    try "#!/bin/sh\nwhile :; do :; done\n".write(
        to: stalledList,
        atomically: true,
        encoding: .utf8
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: stalledList.path
    )

    let scanner = DriveScanner(
        anylinuxfsPath: stalledList.path,
        scanTimeout: 0.05,
        initialScanTimeout: 0.05
    )
    let clock = ContinuousClock()
    let startedAt = clock.now

    await scanner.refresh()

    let elapsed = startedAt.duration(to: clock.now)
    // This is a bounded-completion guard, not a latency benchmark. The runner has bounded
    // TERM/SIGKILL grace waits; a busy hosted CI machine can delay task scheduling beyond one
    // second even though the timeout path completes correctly. Three
    // seconds still fails decisively if the production scan loses its bounded-return contract.
    #expect(elapsed < .seconds(3), "stalled production probes did not return within the safety bound")
    #expect(scanner.drives.isEmpty)
    #expect(scanner.lastError?.contains("timed out") == true)
}

private struct ListCall: Equatable {
    let path: String
    let args: [String]
}

private final class FakeListRunner: PrivilegedCommandRunning {
    var output: String
    init(output: String = sampleExtOutput) { self.output = output }
    private(set) var calls: [ListCall] = []
    func run(_ executablePath: String, _ arguments: [String]) -> CommandResult {
        calls.append(ListCall(path: executablePath, args: arguments))
        return CommandResult(output: output, exitCode: 0)
    }
    func runPipingStdin(_ input: String, to executablePath: String, _ arguments: [String]) -> CommandResult {
        CommandResult(output: "", exitCode: 0)
    }
}

@MainActor
@Test func linuxMetadataProbeResolvesBothSiblingsBeforeMountAndNeverCachesDiskIdentifiers() async {
    let runner = FakeListRunner(output: sampleMBRLinuxOutput)
    var format = "ext4"
    let scanner = DriveScanner(runner: runner, filesystemProber: { device in
        CommandResult(output: "{\"device\":\"\(device)\",\"fs_type\":\"\(format)\",\"label\":\"Volume \(device)\"}", exitCode: 0)
    })
    await scanner.refresh()
    #expect(scanner.drives.count == 2)
    #expect(scanner.drives.allSatisfy { $0.filesystemDisplayName == "EXT4" && !$0.label.isEmpty })
    format = "ext3"
    await scanner.refresh()
    #expect(scanner.drives.allSatisfy { $0.fsType == "ext3" })
    format = "btrfs"
    await scanner.refresh()
    #expect(scanner.drives.isEmpty, "a confirmed unsupported format must not retain a generic mount button")
    runner.output = ""
    format = "ext2"
    await scanner.refresh()
    #expect(scanner.drives.isEmpty, "removed devices must not survive in a metadata cache")
}

@MainActor
@Test func linuxProbeFailureOrMismatchedIdentityPreservesUnverifiedCandidates() async {
    for output in ["invalid json", "{\"device\":\"disk99s1\",\"fs_type\":\"ext4\"}",
                   "{\"device\":\"disk4s2\",\"fs_type\":null}"] {
        let scanner = DriveScanner(runner: FakeListRunner(output: sampleMBRLinuxOutput), filesystemProber: { _ in
            CommandResult(output: output, exitCode: 0)
        })
        await scanner.refresh()
        #expect(scanner.drives.count == 2)
        #expect(scanner.drives.allSatisfy { $0.filesystemDisplayName == "Linux (unverified)" })
        #expect(scanner.lastError == nil, "an optional metadata failure must not hide available drives")
    }
    let scanner = DriveScanner(runner: FakeListRunner(output: sampleMBRLinuxOutput), filesystemProber: { _ in
        CommandResult(output: "permission denied", exitCode: 1)
    })
    await scanner.refresh()
    #expect(scanner.drives.count == 2 && scanner.drives.allSatisfy { $0.fsType == "ext" })
}

@MainActor
@Test func confirmedInventoryDoesNotNeedPrivilegedMetadataProbe() async {
    let scanner = DriveScanner(runner: FakeListRunner(output: sampleExtOutput), filesystemProber: { _ in
        Issue.record("already confirmed filesystems must not trigger an extra raw-device probe")
        return CommandResult(output: "", exitCode: 1)
    })
    await scanner.refresh()
    #expect(scanner.drives.map(\.fsType) == ["ntfs", "ext4"])
}
