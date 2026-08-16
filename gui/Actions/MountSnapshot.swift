import Foundation
import HelperShared

/// One ntfsmac-owned NFS mount observed from the host rather than inferred from a GUI action.
/// `isReadOnly == nil` means the anylinuxfs runtime reported the mount but the host mount table
/// could not be paired with it, so callers must present an explicit unverified state.
public struct ObservedMount: Equatable, Sendable {
    public let deviceIdentifier: String
    public let mountPoint: String
    public let fsDriver: String?
    public let isReadOnly: Bool?

    public init(
        deviceIdentifier: String,
        mountPoint: String,
        fsDriver: String? = nil,
        isReadOnly: Bool? = nil
    ) {
        self.deviceIdentifier = deviceIdentifier
        self.mountPoint = mountPoint
        self.fsDriver = fsDriver
        self.isReadOnly = isReadOnly
    }
}

/// A snapshot is authoritative only when both sources agree: `anylinuxfs status` identifies the
/// owning device/session and `/sbin/mount -t nfs` confirms the live host mount plus its options.
public struct MountSnapshot: Equatable, Sendable {
    public let mounts: [ObservedMount]
    public let isAuthoritative: Bool
    public let warningCode: String?
    public let physicallyPresentDeviceIDs: Set<String>?
    public let unresponsiveDeviceIDs: Set<String>

    public init(
        mounts: [ObservedMount],
        isAuthoritative: Bool = true,
        warningCode: String? = nil,
        physicallyPresentDeviceIDs: Set<String>? = nil,
        unresponsiveDeviceIDs: Set<String> = []
    ) {
        self.mounts = mounts
        self.isAuthoritative = isAuthoritative
        self.warningCode = warningCode
        self.physicallyPresentDeviceIDs = physicallyPresentDeviceIDs
        self.unresponsiveDeviceIDs = unresponsiveDeviceIDs
    }
}

/// Extracts partition identifiers from `diskutil list external physical`. The command's scope,
/// not cached runtime state, makes absence meaningful after a physical disconnect.
public enum ExternalPhysicalDeviceParser {
    private static let partitionPattern = try! NSRegularExpression(
        pattern: #"\b(disk[0-9]+s[0-9]+)\b"#,
        options: [.caseInsensitive]
    )

    public static func parse(_ output: String) -> Set<String> {
        let range = NSRange(output.startIndex..., in: output)
        return Set(partitionPattern.matches(in: output, range: range).compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: output) else { return nil }
            let device = String(output[captureRange]).lowercased()
            return validateDevice(device) ? device : nil
        })
    }
}

@MainActor
public protocol MountSnapshotProviding {
    func snapshot() async -> MountSnapshot
}

/// Parser for the stable `anylinuxfs status` line shape:
/// `/dev/disk6s1 on /Volumes/Name (ntfs-3g, mounted by user) VM[cpus: ...]`.
/// The username is intentionally ignored and never reaches the GUI state.
public enum AnyLinuxFSStatusParser {
    private static let linePattern = try! NSRegularExpression(
        pattern: #"^(?:/dev/)?(disk[0-9]+s[0-9]+) on (.+) \((.*)\) VM\[cpus:"#
    )

    public static func parse(_ output: String) -> [ObservedMount] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { rawLine in
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = linePattern.firstMatch(in: line, range: range),
                  let device = capture(match, 1, in: line),
                  let mountPoint = capture(match, 2, in: line),
                  let info = capture(match, 3, in: line),
                  validateDevice(device)
            else { return nil }

            let fields = info
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let driver = fields.first
            return ObservedMount(
                deviceIdentifier: device,
                mountPoint: MountTableParser.decodeEscapes(mountPoint),
                fsDriver: driver,
                // The host NFS client can remain read/write while the guest filesystem beneath
                // the export is read-only (for example ntfs-3g `ro,norecover`). Preserve that
                // independent guest truth here; RealMountSnapshotProvider still returns nil in
                // its final snapshot unless the host mount table pairs this runtime row.
                isReadOnly: fields.contains("ro") || fields.contains("read-only")
            )
        }
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in line: String
    ) -> String? {
        guard let range = Range(match.range(at: index), in: line) else { return nil }
        return String(line[range])
    }
}

public struct NFSMountTableEntry: Equatable, Sendable {
    public let source: String
    public let mountPoint: String
    public let isReadOnly: Bool
    public let deviceIdentifier: String?
}

/// Parses macOS's `/sbin/mount -t nfs` output. Matching from the right preserves mount points
/// containing spaces; octal escapes are decoded before pairing with `anylinuxfs status`.
public enum MountTableParser {
    private static let linePattern = try! NSRegularExpression(
        pattern: #"^(\S+) on (.+) \(nfs(?:,\s*(.*))?\)$"#
    )
    private static let ntfsmacHost = try! NSRegularExpression(
        pattern: #"^(disk[0-9]+s[0-9]+)(?:-[0-9]+)?\.local:"#,
        options: [.caseInsensitive]
    )

    public static func parse(_ output: String) -> [NFSMountTableEntry] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { rawLine in
            let line = String(rawLine)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = linePattern.firstMatch(in: line, range: range),
                  let source = capture(match, 1, in: line),
                  let mountPoint = capture(match, 2, in: line)
            else { return nil }

            let options = capture(match, 3, in: line)?
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { $0.trimmingCharacters(in: .whitespaces) } ?? []
            return NFSMountTableEntry(
                source: decodeEscapes(source),
                mountPoint: decodeEscapes(mountPoint),
                isReadOnly: options.contains("read-only") || options.contains("ro"),
                deviceIdentifier: deviceIdentifier(from: source)
            )
        }
    }

    static func decodeEscapes(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\040", with: " ")
            .replacingOccurrences(of: "\\011", with: "\t")
            .replacingOccurrences(of: "\\134", with: "\\")
    }

    private static func deviceIdentifier(from source: String) -> String? {
        let range = NSRange(source.startIndex..., in: source)
        guard let match = ntfsmacHost.firstMatch(in: source, range: range),
              let device = capture(match, 1, in: source),
              validateDevice(device)
        else { return nil }
        return device.lowercased()
    }

    private static func capture(
        _ match: NSTextCheckingResult,
        _ index: Int,
        in line: String
    ) -> String? {
        guard match.range(at: index).location != NSNotFound,
              let range = Range(match.range(at: index), in: line)
        else { return nil }
        return String(line[range])
    }
}

/// Reads two independent, unprivileged sources. A status-only entry is retained as unverified;
/// a `.local` mount-table entry can also recover a CLI-created mount if status output is briefly
/// unavailable. Only a complete, mutually paired read is allowed to clear cached GUI rows.
@MainActor
public struct RealMountSnapshotProvider: MountSnapshotProviding {
    private let runner: (any PrivilegedCommandRunning)?
    private let anylinuxfsPath: String
    private let mountPath: String
    private let diskutilPath: String
    private let statPath: String
    private let probeTimeout: TimeInterval
    private let sourceTimeout: TimeInterval

    public init(
        runner: (any PrivilegedCommandRunning)? = nil,
        anylinuxfsPath: String = "\(installPrefix)/bin/anylinuxfs",
        mountPath: String = "/sbin/mount",
        diskutilPath: String = "/usr/sbin/diskutil",
        statPath: String = "/usr/bin/stat",
        probeTimeout: TimeInterval = 2,
        sourceTimeout: TimeInterval = 5
    ) {
        self.runner = runner
        self.anylinuxfsPath = anylinuxfsPath
        self.mountPath = mountPath
        self.diskutilPath = diskutilPath
        self.statPath = statPath
        self.probeTimeout = probeTimeout
        self.sourceTimeout = sourceTimeout
    }

    public func snapshot() async -> MountSnapshot {
        let statusResult: CommandResult
        let mountResult: CommandResult
        let physicalResult: CommandResult?
        if let runner {
            // Explicit runners are a deterministic test seam and execute on the caller's actor.
            statusResult = runner.run(anylinuxfsPath, ["status"])
            mountResult = runner.run(mountPath, ["-t", "nfs"])
            physicalResult = nil
        } else {
            // Production polling must never block the menu-bar UI while Process waits. Each
            // reconciliation waits for its own reads before scheduling the next poll, so a slow
            // source cannot create an unbounded queue of subprocesses.
            async let statusTask = Self.runOffMain(
                anylinuxfsPath,
                ["status"],
                timeout: sourceTimeout
            )
            async let mountTask = Self.runOffMain(
                mountPath,
                ["-t", "nfs"],
                timeout: sourceTimeout
            )
            async let physicalTask = Self.runOffMain(
                diskutilPath,
                ["list", "external", "physical"],
                timeout: probeTimeout
            )
            (statusResult, mountResult, physicalResult) = await (statusTask, mountTask, physicalTask)
        }
        let statusMounts = statusResult.exitCode == 0
            ? AnyLinuxFSStatusParser.parse(statusResult.output)
            : []
        let tableMounts = mountResult.exitCode == 0
            ? MountTableParser.parse(mountResult.output)
            : []

        var observed: [ObservedMount] = statusMounts.map { statusMount in
            let tableMount = tableMounts.first { $0.mountPoint == statusMount.mountPoint }
            return ObservedMount(
                deviceIdentifier: statusMount.deviceIdentifier,
                mountPoint: statusMount.mountPoint,
                fsDriver: statusMount.fsDriver,
                // Read-only at either layer makes the user-visible volume read-only. Looking
                // only at `(nfs, ...)` caused a real false-green state: the NFS client was rw,
                // while anylinuxfs truthfully reported the guest NTFS mount as `ro,norecover`.
                isReadOnly: tableMount.map { $0.isReadOnly || statusMount.isReadOnly == true }
            )
        }

        // If anylinuxfs status is transiently unavailable, its stable `<device>.local` hostname
        // still lets the host mount table identify an ntfsmac-owned session without exporting
        // the hostname, address, volume label, or path to diagnostics.
        for tableMount in tableMounts {
            guard let device = tableMount.deviceIdentifier,
                  !observed.contains(where: { $0.deviceIdentifier == device })
            else { continue }
            observed.append(ObservedMount(
                deviceIdentifier: device,
                mountPoint: tableMount.mountPoint,
                isReadOnly: tableMount.isReadOnly
            ))
        }

        observed.sort { $0.deviceIdentifier < $1.deviceIdentifier }
        let physicallyPresent = physicalResult.flatMap { result in
            result.exitCode == 0 ? ExternalPhysicalDeviceParser.parse(result.output) : nil
        }
        // Physical absence is already authoritative failure evidence. Never `stat` an NFS mount
        // whose backing USB partition has disappeared: that syscall can remain blocked in the
        // kernel even after its child process receives TERM/KILL, preventing this snapshot from
        // returning and therefore preventing the exact helper teardown. Keep probing surviving
        // devices so an unrelated live mount still gets its normal backend-health check.
        let livenessCandidates = Self.livenessProbeCandidates(
            observed,
            physicallyPresentDeviceIDs: physicallyPresent
        )
        let unresponsive = runner == nil
            ? await Self.unresponsiveMounts(livenessCandidates, statPath: statPath, timeout: probeTimeout)
            : []
        let sourcesSucceeded = statusResult.exitCode == 0 && mountResult.exitCode == 0
        let everyStatusMountWasPaired = statusMounts.allSatisfy { statusMount in
            tableMounts.contains {
                $0.mountPoint == statusMount.mountPoint
                    && ($0.deviceIdentifier == nil || $0.deviceIdentifier == statusMount.deviceIdentifier)
            }
        }
        let everyNtfsmacTableMountWasPaired = tableMounts
            .filter { $0.deviceIdentifier != nil }
            .allSatisfy { tableMount in
                statusMounts.contains {
                    $0.mountPoint == tableMount.mountPoint
                        && $0.deviceIdentifier == tableMount.deviceIdentifier
                }
            }
        let sourcesAgree = everyStatusMountWasPaired && everyNtfsmacTableMountWasPaired
        let physicallyMissing = physicallyPresent.map { present in
            observed.contains { !present.contains($0.deviceIdentifier) }
        } ?? false
        let authoritative = sourcesSucceeded && sourcesAgree && !physicallyMissing && unresponsive.isEmpty
        let warningCode: String?
        if !sourcesSucceeded {
            warningCode = "MOUNT_STATE_SOURCE_UNAVAILABLE"
        } else if !sourcesAgree {
            warningCode = "MOUNT_STATE_INCONSISTENT"
        } else if physicallyMissing {
            warningCode = "PHYSICAL_DEVICE_MISSING"
        } else if !unresponsive.isEmpty {
            warningCode = "MOUNT_BACKEND_UNRESPONSIVE"
        } else {
            warningCode = nil
        }
        return MountSnapshot(
            mounts: observed,
            isAuthoritative: authoritative,
            warningCode: warningCode,
            physicallyPresentDeviceIDs: physicallyPresent,
            unresponsiveDeviceIDs: unresponsive
        )
    }

    private nonisolated static func runOffMain(
        _ executablePath: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) async -> CommandResult {
        await Task.detached(priority: .userInitiated) {
            RealCommandRunner().run(executablePath, arguments, timeout: timeout)
        }.value
    }

    nonisolated static func livenessProbeCandidates(
        _ mounts: [ObservedMount],
        physicallyPresentDeviceIDs: Set<String>?
    ) -> [ObservedMount] {
        guard let physicallyPresentDeviceIDs else { return mounts }
        return mounts.filter { physicallyPresentDeviceIDs.contains($0.deviceIdentifier) }
    }

    private nonisolated static func unresponsiveMounts(
        _ mounts: [ObservedMount],
        statPath: String,
        timeout: TimeInterval
    ) async -> Set<String> {
        await withTaskGroup(of: (String, Bool).self, returning: Set<String>.self) { group in
            for mount in mounts {
                group.addTask {
                    let result = RealCommandRunner().run(
                        statPath,
                        ["-f", "%d", mount.mountPoint],
                        timeout: timeout
                    )
                    return (mount.deviceIdentifier, result.exitCode == 0)
                }
            }
            var failed = Set<String>()
            for await (device, succeeded) in group where !succeeded {
                failed.insert(device)
            }
            return failed
        }
    }
}
