import AppKit
import Combine
import Darwin
import Foundation
import HelperShared

public enum VerifiedCopyValidationError: LocalizedError, Equatable, Sendable {
    case sourceUnavailable
    case unsupportedSource
    case mountUnavailable
    case destinationParentUnavailable
    case destinationOutsideMountedDrive
    case destinationOnDifferentFilesystem
    case destinationExists
    case sourceAndDestinationMatch
    case destinationInsideSource
    case destinationNotWritable

    public var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "The selected source is no longer available."
        case .unsupportedSource:
            "Choose a regular file, folder, or symbolic link."
        case .mountUnavailable:
            "The selected drive is no longer mounted at its verified location."
        case .destinationParentUnavailable:
            "The destination folder is no longer available."
        case .destinationOutsideMountedDrive:
            "Choose a destination inside this mounted drive."
        case .destinationOnDifferentFilesystem:
            "The destination must stay on this exact mounted volume."
        case .destinationExists:
            "The destination already exists. Verified Copy never overwrites it."
        case .sourceAndDestinationMatch:
            "Source and destination must be different."
        case .destinationInsideSource:
            "A folder cannot be copied inside itself."
        case .destinationNotWritable:
            "The destination folder is not writable."
        }
    }
}

public struct VerifiedCopySelection: Equatable, Sendable {
    public let source: URL
    public let destination: URL
    public let mountPoint: URL
    public let volumeDeviceID: UInt64

    public init(source: URL, destination: URL, mountPoint: URL, volumeDeviceID: UInt64) {
        self.source = source
        self.destination = destination
        self.mountPoint = mountPoint
        self.volumeDeviceID = volumeDeviceID
    }
}

public enum VerifiedCopyAvailability {
    public static func isAvailable(
        isVerified: Bool,
        isReadOnly: Bool,
        isDirty: Bool,
        mountPoint: String?
    ) -> Bool {
        isVerified
            && !isReadOnly
            && !isDirty
            && !(mountPoint?.isEmpty ?? true)
    }
}

/// GUI preflight for the CLI's stricter copy contract. The final path component is deliberately
/// not symlink-resolved: a source symlink is copied as a symlink, while an existing or broken
/// destination symlink must still be treated as an existing destination. Existing parent paths
/// are resolved before containment and `st_dev` checks so a symlink or nested mount cannot escape
/// the exact mounted volume selected in the drive row.
public enum VerifiedCopySelectionValidator {
    public static func validate(
        source sourceURL: URL,
        destination destinationURL: URL,
        mountPoint mountPointURL: URL,
        fileManager: FileManager = .default
    ) throws -> VerifiedCopySelection {
        let mountPoint = try canonicalDirectory(
            mountPointURL,
            unavailable: .mountUnavailable,
            fileManager: fileManager
        )
        let source = try canonicalPathPreservingLeaf(
            sourceURL,
            parentUnavailable: .sourceUnavailable,
            fileManager: fileManager
        )
        let destination = try canonicalPathPreservingLeaf(
            destinationURL,
            parentUnavailable: .destinationParentUnavailable,
            fileManager: fileManager
        )

        guard let sourceMode = lstatMode(atPath: source.path) else {
            throw VerifiedCopyValidationError.sourceUnavailable
        }
        let sourceType = sourceMode & mode_t(S_IFMT)
        guard sourceType == mode_t(S_IFREG)
                || sourceType == mode_t(S_IFDIR)
                || sourceType == mode_t(S_IFLNK)
        else {
            throw VerifiedCopyValidationError.unsupportedSource
        }

        guard source.path != destination.path else {
            throw VerifiedCopyValidationError.sourceAndDestinationMatch
        }
        guard lstatMode(atPath: destination.path) == nil else {
            throw VerifiedCopyValidationError.destinationExists
        }

        let destinationParent = destination.deletingLastPathComponent()
        guard path(destinationParent.path, isInside: mountPoint.path) else {
            throw VerifiedCopyValidationError.destinationOutsideMountedDrive
        }
        guard let destinationDevice = lstatDevice(atPath: destinationParent.path),
              let mountDevice = lstatDevice(atPath: mountPoint.path),
              destinationDevice == mountDevice
        else {
            throw VerifiedCopyValidationError.destinationOnDifferentFilesystem
        }
        guard fileManager.isWritableFile(atPath: destinationParent.path) else {
            throw VerifiedCopyValidationError.destinationNotWritable
        }

        if sourceType == mode_t(S_IFDIR) {
            let resolvedSource = source.resolvingSymlinksInPath().standardizedFileURL
            if path(destinationParent.path, isInside: resolvedSource.path) {
                throw VerifiedCopyValidationError.destinationInsideSource
            }
        }

        return VerifiedCopySelection(
            source: source,
            destination: destination,
            mountPoint: mountPoint,
            volumeDeviceID: UInt64(mountDevice)
        )
    }

    private static func canonicalDirectory(
        _ url: URL,
        unavailable error: VerifiedCopyValidationError,
        fileManager: FileManager
    ) throws -> URL {
        guard url.isFileURL else { throw error }
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let mode = lstatMode(atPath: resolved.path),
              mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        else {
            throw error
        }
        return resolved
    }

    private static func canonicalPathPreservingLeaf(
        _ url: URL,
        parentUnavailable error: VerifiedCopyValidationError,
        fileManager: FileManager
    ) throws -> URL {
        guard url.isFileURL else { throw error }
        let standardized = url.standardizedFileURL
        let leaf = standardized.lastPathComponent
        guard !leaf.isEmpty, leaf != ".", leaf != ".." else { throw error }
        let parent = try canonicalDirectory(
            standardized.deletingLastPathComponent(),
            unavailable: error,
            fileManager: fileManager
        )
        return parent.appendingPathComponent(leaf, isDirectory: false).standardizedFileURL
    }

    private static func path(_ candidate: String, isInside root: String) -> Bool {
        if root == "/" { return candidate.hasPrefix("/") }
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private static func lstatMode(atPath path: String) -> mode_t? {
        var information = stat()
        guard Darwin.lstat(path, &information) == 0 else { return nil }
        return information.st_mode
    }

    private static func lstatDevice(atPath path: String) -> dev_t? {
        var information = stat()
        guard Darwin.lstat(path, &information) == 0 else { return nil }
        return information.st_dev
    }
}

/// Native panels are used only after the user selects Verified Copy from a mounted drive's small
/// overflow menu. There is no permanent page or global copy control in the popover.
@MainActor
public enum VerifiedCopyPicker {
    public static func choose(onMountPoint mountPoint: String) throws -> VerifiedCopySelection? {
        let sourcePanel = NSOpenPanel()
        sourcePanel.title = "Verified Copy"
        sourcePanel.message = "Choose one file or folder to copy and verify with SHA-256."
        sourcePanel.prompt = "Choose"
        sourcePanel.canChooseFiles = true
        sourcePanel.canChooseDirectories = true
        sourcePanel.allowsMultipleSelection = false
        sourcePanel.treatsFilePackagesAsDirectories = true
        sourcePanel.resolvesAliases = false

        NSApp.activate(ignoringOtherApps: true)
        guard sourcePanel.runModal() == .OK, let source = sourcePanel.url else { return nil }

        let mountPointURL = URL(fileURLWithPath: mountPoint, isDirectory: true)
        let destinationPanel = NSSavePanel()
        destinationPanel.title = "Verified Copy Destination"
        destinationPanel.message = "Choose a new destination on this mounted drive. Existing items are never overwritten."
        destinationPanel.prompt = "Copy & Verify"
        destinationPanel.directoryURL = mountPointURL
        destinationPanel.nameFieldStringValue = source.lastPathComponent
        destinationPanel.canCreateDirectories = true

        guard destinationPanel.runModal() == .OK, let destination = destinationPanel.url else {
            return nil
        }
        return try VerifiedCopySelectionValidator.validate(
            source: source,
            destination: destination,
            mountPoint: mountPointURL
        )
    }
}

public protocol VerifiedCopyExecuting: Sendable {
    func run(_ selection: VerifiedCopySelection) async -> CommandResult
    func cancel() async
}

private final class VerifiedCopyProcessBox: @unchecked Sendable {
    let id = UUID()
    let processID: pid_t
    let outputURL: URL

    init(processID: pid_t, outputURL: URL) {
        self.processID = processID
        self.outputURL = outputURL
    }
}

/// Runs the installed CLI directly with an argv array — never through a shell and never through
/// the privileged helper. Verified Copy is a user-owned file operation; the helper remains
/// exclusively responsible for mount/unmount. `posix_spawn` creates a dedicated process group so
/// cancellation reaches the CLI and every active copy/hash child instead of orphaning a writer.
/// Output is drained to a private temporary file so even unexpected verbose failures cannot fill
/// a pipe and deadlock the popover.
public actor VerifiedCopyProcessExecutor: VerifiedCopyExecuting {
    private let executablePath: String
    private var active: VerifiedCopyProcessBox?
    private var cancellationEscalation: Task<Void, Never>?

    public init(executablePath: String = "\(resolveNtfsmacPrefix())/bin/ntfsmac") {
        self.executablePath = executablePath
    }

    public func run(_ selection: VerifiedCopySelection) async -> CommandResult {
        guard active == nil else {
            return CommandResult(output: "copy: another Verified Copy is already running", exitCode: 75)
        }
        guard !Task.isCancelled else {
            return CommandResult(output: "copy: cancelled before launch", exitCode: 130)
        }

        do {
            let current = try VerifiedCopySelectionValidator.validate(
                source: selection.source,
                destination: selection.destination,
                mountPoint: selection.mountPoint
            )
            guard current.volumeDeviceID == selection.volumeDeviceID else {
                throw VerifiedCopyValidationError.destinationOnDifferentFilesystem
            }
        } catch {
            return CommandResult(output: "copy: \(error.localizedDescription)", exitCode: 74)
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntfsmac-verified-copy-\(UUID().uuidString).log")
        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ), let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return CommandResult(output: "copy: could not create private command output", exitCode: -1)
        }

        let spawn = spawnProcess(
            arguments: ["copy", "--verify", selection.source.path, selection.destination.path],
            outputFileDescriptor: outputHandle.fileDescriptor
        )
        try? outputHandle.close()
        guard spawn.errorCode == 0 else {
            try? FileManager.default.removeItem(at: outputURL)
            return CommandResult(output: "copy: failed to launch the installed ntfsmac CLI", exitCode: -1)
        }
        let box = VerifiedCopyProcessBox(processID: spawn.processID, outputURL: outputURL)
        active = box

        return await withTaskCancellationHandler {
            if Task.isCancelled { requestCancellation(for: box) }
            let exitCode = await Task.detached(priority: .utility) {
                Self.waitForExit(processID: box.processID)
            }.value
            let output = (try? String(contentsOf: box.outputURL, encoding: .utf8)) ?? ""
            finish(box)
            return CommandResult(output: output, exitCode: exitCode)
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    public func cancel() {
        guard let active else { return }
        requestCancellation(for: active)
    }

    private func requestCancellation(for box: VerifiedCopyProcessBox) {
        guard active?.id == box.id else { return }
        Darwin.kill(-box.processID, SIGINT)
        guard cancellationEscalation == nil else { return }

        cancellationEscalation = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.terminateIfStillRunning(id: box.id)
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            await self?.killIfStillRunning(id: box.id)
        }
    }

    private func terminateIfStillRunning(id: UUID) {
        guard let active, active.id == id else { return }
        Darwin.kill(-active.processID, SIGTERM)
    }

    private func killIfStillRunning(id: UUID) {
        guard let active, active.id == id else { return }
        Darwin.kill(-active.processID, SIGKILL)
    }

    private func finish(_ box: VerifiedCopyProcessBox) {
        try? FileManager.default.removeItem(at: box.outputURL)
        guard active?.id == box.id else { return }
        active = nil
        cancellationEscalation?.cancel()
        cancellationEscalation = nil
    }

    private func spawnProcess(
        arguments: [String],
        outputFileDescriptor: Int32
    ) -> (processID: pid_t, errorCode: Int32) {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&fileActions) == 0 else { return (0, EINVAL) }
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return (0, EINVAL) }
        defer { posix_spawnattr_destroy(&attributes) }

        guard posix_spawn_file_actions_adddup2(
            &fileActions,
            outputFileDescriptor,
            STDOUT_FILENO
        ) == 0,
        posix_spawn_file_actions_adddup2(
            &fileActions,
            outputFileDescriptor,
            STDERR_FILENO
        ) == 0,
        posix_spawn_file_actions_addclose(&fileActions, outputFileDescriptor) == 0,
        posix_spawnattr_setpgroup(&attributes, 0) == 0
        else {
            return (0, EINVAL)
        }

        var defaultSignals = sigset_t()
        var emptySignalMask = sigset_t()
        sigemptyset(&defaultSignals)
        sigemptyset(&emptySignalMask)
        sigaddset(&defaultSignals, SIGINT)
        sigaddset(&defaultSignals, SIGTERM)
        sigaddset(&defaultSignals, SIGHUP)
        let spawnFlags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        guard posix_spawnattr_setsigdefault(&attributes, &defaultSignals) == 0,
              posix_spawnattr_setsigmask(&attributes, &emptySignalMask) == 0,
              posix_spawnattr_setflags(&attributes, Int16(spawnFlags)) == 0
        else {
            return (0, EINVAL)
        }

        let strings = [executablePath] + arguments
        var argv: [UnsafeMutablePointer<CChar>?] = strings.map { strdup($0) }
        guard !argv.contains(where: { $0 == nil }) else {
            argv.forEach { free($0) }
            return (0, ENOMEM)
        }
        defer { argv.forEach { free($0) } }
        argv.append(nil)

        var processID: pid_t = 0
        let errorCode = executablePath.withCString { executable in
            argv.withUnsafeMutableBufferPointer { buffer in
                posix_spawn(
                    &processID,
                    executable,
                    &fileActions,
                    &attributes,
                    buffer.baseAddress!,
                    environ
                )
            }
        }
        return (processID, errorCode)
    }

    private nonisolated static func waitForExit(processID: pid_t) -> Int32 {
        var status: Int32 = 0
        while true {
            let waited = Darwin.waitpid(processID, &status, 0)
            if waited == processID { break }
            if waited == -1, errno == EINTR { continue }
            return -1
        }

        let terminationSignal = status & 0x7F
        if terminationSignal == 0 {
            return (status >> 8) & 0xFF
        }
        return 128 + terminationSignal
    }
}

public enum VerifiedCopyPhase: Equatable, Sendable {
    case idle
    case running
    case cancelling
    case succeeded
    case failed
    case cancelled
}

@MainActor
public final class VerifiedCopyController: ObservableObject {
    @Published public private(set) var phase: VerifiedCopyPhase = .idle
    @Published public private(set) var volumeName = ""
    @Published public private(set) var sourceName = ""
    @Published public private(set) var destinationName = ""
    @Published public private(set) var message = ""

    private let executor: any VerifiedCopyExecuting
    private var copyTask: Task<Void, Never>?
    private var cancellationRequested = false

    public init(executor: any VerifiedCopyExecuting = VerifiedCopyProcessExecutor()) {
        self.executor = executor
    }

    public var isActive: Bool {
        phase == .running || phase == .cancelling
    }

    public var isVisible: Bool { phase != .idle }

    public func start(_ selection: VerifiedCopySelection, volumeName: String) {
        guard !isActive else { return }
        self.volumeName = volumeName
        sourceName = selection.source.lastPathComponent
        destinationName = selection.destination.lastPathComponent
        message = "Copying, flushing, then rereading SHA-256…"
        cancellationRequested = false
        phase = .running

        copyTask = Task { [weak self] in
            guard let self else { return }
            let result = await executor.run(selection)
            complete(with: result)
        }
    }

    public func showSelectionError(_ error: Error, volumeName: String) {
        guard !isActive else { return }
        self.volumeName = volumeName
        sourceName = ""
        destinationName = ""
        message = error.localizedDescription
        phase = .failed
    }

    public func cancel() {
        guard phase == .running else { return }
        cancellationRequested = true
        phase = .cancelling
        message = "Cancelling safely…"
        copyTask?.cancel()
        Task { await executor.cancel() }
    }

    public func dismiss() {
        guard !isActive else { return }
        phase = .idle
        volumeName = ""
        sourceName = ""
        destinationName = ""
        message = ""
    }

    private func complete(with result: CommandResult) {
        copyTask = nil
        if cancellationRequested || result.exitCode == 130 {
            phase = .cancelled
            message = Self.conciseOutput(result.output)
                ?? "Copy cancelled. The source is unchanged; any partial remains beside the destination."
        } else if result.exitCode == 0 {
            phase = .succeeded
            message = "SHA-256 manifest matched. Destination published."
        } else {
            phase = .failed
            message = Self.conciseOutput(result.output)
                ?? "Copy failed. The source is unchanged; any partial remains beside the destination."
        }
        cancellationRequested = false
    }

    private static func conciseOutput(_ output: String) -> String? {
        let lastLine = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })
        guard let lastLine else { return nil }
        let printable = lastLine.unicodeScalars.map { scalar -> Character in
            scalar.value >= 0x20 && scalar.value != 0x7F ? Character(String(scalar)) : " "
        }
        let text = String(printable)
        return text.count <= 240 ? text : String(text.prefix(237)) + "…"
    }
}
