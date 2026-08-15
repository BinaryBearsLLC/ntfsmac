import Foundation
import SwiftUI
import Testing
import HelperShared
@testable import NtfsmacGUI

private final class VerifiedCopyFixture {
    let root: URL
    let mountPoint: URL
    let source: URL

    init(sourceName: String = "source file.bin") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntfsmac-verified-copy-tests-\(UUID().uuidString)", isDirectory: true)
        mountPoint = root.appendingPathComponent("mounted volume", isDirectory: true)
        source = root.appendingPathComponent(sourceName)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try Data("stable bytes\n".utf8).write(to: source)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private actor ImmediateVerifiedCopyExecutor: VerifiedCopyExecuting {
    let result: CommandResult
    private(set) var runCount = 0

    init(_ result: CommandResult) {
        self.result = result
    }

    func run(_ selection: VerifiedCopySelection) async -> CommandResult {
        runCount += 1
        return result
    }

    func cancel() {}
}

private actor BlockingVerifiedCopyExecutor: VerifiedCopyExecuting {
    private var continuation: CheckedContinuation<CommandResult, Never>?
    private(set) var runCount = 0
    private(set) var cancelCount = 0

    func run(_ selection: VerifiedCopySelection) async -> CommandResult {
        runCount += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func cancel() {
        cancelCount += 1
        continuation?.resume(returning: CommandResult(
            output: "copy: interrupted — recoverable partial copy retained beside destination",
            exitCode: 130
        ))
        continuation = nil
    }

    func counts() -> (runs: Int, cancellations: Int) {
        (runCount, cancelCount)
    }
}

private func makeUncheckedSelection(suffix: String = "one") -> VerifiedCopySelection {
    VerifiedCopySelection(
        source: URL(fileURLWithPath: "/tmp/source-\(suffix)"),
        destination: URL(fileURLWithPath: "/tmp/destination-\(suffix)"),
        mountPoint: URL(fileURLWithPath: "/tmp"),
        volumeDeviceID: 1
    )
}

@Test(arguments: [
    (true, false, false, Optional("/Volumes/MEDIA"), true),
    (false, false, false, Optional("/Volumes/MEDIA"), false),
    (true, true, false, Optional("/Volumes/MEDIA"), false),
    (true, false, true, Optional("/Volumes/MEDIA"), false),
    (true, false, false, Optional<String>.none, false),
    (true, false, false, Optional(""), false),
])
func availabilityRequiresOneVerifiedWritableMountedRow(
    argument: (Bool, Bool, Bool, String?, Bool)
) {
    #expect(VerifiedCopyAvailability.isAvailable(
        isVerified: argument.0,
        isReadOnly: argument.1,
        isDirty: argument.2,
        mountPoint: argument.3
    ) == argument.4)
}

@MainActor
private func waitForPhase(
    _ phase: VerifiedCopyPhase,
    controller: VerifiedCopyController
) async {
    for _ in 0..<250 {
        if controller.phase == phase { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@Test func validatorAcceptsAFreshDestinationOnTheExactMountedVolume() throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }
    let destination = fixture.mountPoint.appendingPathComponent("copied file.bin")

    let selection = try VerifiedCopySelectionValidator.validate(
        source: fixture.source,
        destination: destination,
        mountPoint: fixture.mountPoint
    )

    #expect(selection.source == fixture.source.standardizedFileURL)
    #expect(selection.destination == destination.standardizedFileURL)
    #expect(selection.mountPoint == fixture.mountPoint.standardizedFileURL)
    #expect(selection.volumeDeviceID > 0)
}

@Test func validatorRejectsOutsideExistingAndSameDestinations() throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }

    #expect(throws: VerifiedCopyValidationError.destinationOutsideMountedDrive) {
        try VerifiedCopySelectionValidator.validate(
            source: fixture.source,
            destination: fixture.root.appendingPathComponent("outside.bin"),
            mountPoint: fixture.mountPoint
        )
    }

    let existing = fixture.mountPoint.appendingPathComponent("existing.bin")
    try Data("keep".utf8).write(to: existing)
    #expect(throws: VerifiedCopyValidationError.destinationExists) {
        try VerifiedCopySelectionValidator.validate(
            source: fixture.source,
            destination: existing,
            mountPoint: fixture.mountPoint
        )
    }

    #expect(throws: VerifiedCopyValidationError.sourceAndDestinationMatch) {
        try VerifiedCopySelectionValidator.validate(
            source: fixture.source,
            destination: fixture.source,
            mountPoint: fixture.mountPoint
        )
    }
}

@MainActor
@Test func savePanelDelegateRejectsExistingNameBeforeNativeReplaceFlow() throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }
    let existing = fixture.mountPoint.appendingPathComponent("existing.bin")
    try Data("keep".utf8).write(to: existing)
    let delegate = VerifiedCopySavePanelDelegate()

    #expect(throws: VerifiedCopyValidationError.destinationExists) {
        try delegate.validateFreshDestination(existing)
    }
    #expect(throws: Never.self) {
        try delegate.validateFreshDestination(fixture.mountPoint.appendingPathComponent("new.bin"))
    }
}

@Test func validatorRejectsBrokenDestinationSymlinksAndParentSymlinkEscapes() throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }

    let broken = fixture.mountPoint.appendingPathComponent("broken destination")
    try FileManager.default.createSymbolicLink(
        atPath: broken.path,
        withDestinationPath: fixture.root.appendingPathComponent("missing").path
    )
    #expect(throws: VerifiedCopyValidationError.destinationExists) {
        try VerifiedCopySelectionValidator.validate(
            source: fixture.source,
            destination: broken,
            mountPoint: fixture.mountPoint
        )
    }

    let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    let escape = fixture.mountPoint.appendingPathComponent("escape", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)
    #expect(throws: VerifiedCopyValidationError.destinationOutsideMountedDrive) {
        try VerifiedCopySelectionValidator.validate(
            source: fixture.source,
            destination: escape.appendingPathComponent("escaped.bin"),
            mountPoint: fixture.mountPoint
        )
    }
}

@Test func validatorRejectsCopyingAFolderInsideItself() throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }
    let sourceFolder = fixture.mountPoint.appendingPathComponent("source folder", isDirectory: true)
    let child = sourceFolder.appendingPathComponent("child", isDirectory: true)
    try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

    #expect(throws: VerifiedCopyValidationError.destinationInsideSource) {
        try VerifiedCopySelectionValidator.validate(
            source: sourceFolder,
            destination: child.appendingPathComponent("copy"),
            mountPoint: fixture.mountPoint
        )
    }
}

@Test func ntfs3PreflightRejectsRootAndNestedSymbolicLinksBeforeCopy() throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }
    let sourceFolder = fixture.root.appendingPathComponent("source folder", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
    let target = sourceFolder.appendingPathComponent("target.txt")
    try Data("target".utf8).write(to: target)
    let nestedLink = sourceFolder.appendingPathComponent("nested-link")
    try FileManager.default.createSymbolicLink(at: nestedLink, withDestinationURL: target)

    #expect(throws: VerifiedCopyValidationError.symbolicLinksUnsupportedByNTFS3) {
        try VerifiedCopySelectionValidator.validate(
            source: sourceFolder,
            destination: fixture.mountPoint.appendingPathComponent("folder-copy"),
            mountPoint: fixture.mountPoint,
            rejectSymbolicLinks: true
        )
    }
    #expect(throws: VerifiedCopyValidationError.symbolicLinksUnsupportedByNTFS3) {
        try VerifiedCopySelectionValidator.validate(
            source: nestedLink,
            destination: fixture.mountPoint.appendingPathComponent("link-copy"),
            mountPoint: fixture.mountPoint,
            rejectSymbolicLinks: true
        )
    }
}

@Test func processExecutorRechecksTheOriginalVolumeIdentityBeforeLaunch() async throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }
    let valid = try VerifiedCopySelectionValidator.validate(
        source: fixture.source,
        destination: fixture.mountPoint.appendingPathComponent("copy.bin"),
        mountPoint: fixture.mountPoint
    )
    let stale = VerifiedCopySelection(
        source: valid.source,
        destination: valid.destination,
        mountPoint: valid.mountPoint,
        volumeDeviceID: valid.volumeDeviceID &+ 1
    )

    let result = await VerifiedCopyProcessExecutor(executablePath: "/usr/bin/true").run(stale)

    #expect(result.exitCode == 74)
    #expect(result.output.contains("exact mounted volume"))
    #expect(!FileManager.default.fileExists(atPath: valid.destination.path))
}

@Test func processExecutorUsesLiteralArgvForPathsWithShellCharacters() async throws {
    let fixture = try VerifiedCopyFixture(sourceName: "source; never-execute")
    defer { fixture.cleanup() }
    let destination = fixture.mountPoint.appendingPathComponent("destination; never-execute")
    let selection = try VerifiedCopySelectionValidator.validate(
        source: fixture.source,
        destination: destination,
        mountPoint: fixture.mountPoint
    )
    let recorder = fixture.root.appendingPathComponent("record-argv.sh")
    try Data("#!/bin/bash\n/usr/bin/printf '<%s>\\n' \"$@\"\n".utf8).write(to: recorder)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: recorder.path)

    let result = await VerifiedCopyProcessExecutor(executablePath: recorder.path).run(selection)

    #expect(result.exitCode == 0)
    #expect(result.output.contains("<copy>"))
    #expect(result.output.contains("<--verify>"))
    #expect(result.output.contains("<\(fixture.source.path)>"))
    #expect(result.output.contains("<\(destination.path)>"))
    #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("never-execute").path))
}

@Test func processExecutorCancellationStopsTheWholeCopyProcessGroup() async throws {
    let fixture = try VerifiedCopyFixture()
    defer { fixture.cleanup() }
    let selection = try VerifiedCopySelectionValidator.validate(
        source: fixture.source,
        destination: fixture.mountPoint.appendingPathComponent("cancelled-copy.bin"),
        mountPoint: fixture.mountPoint
    )
    let blockingCLI = fixture.root.appendingPathComponent("blocking-cli.sh")
    try Data(
        "#!/bin/bash\ntrap 'printf cancelled\\n; exit 130' INT TERM\n/bin/sleep 30 &\nwait $!\n".utf8
    ).write(to: blockingCLI)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: blockingCLI.path)
    let executor = VerifiedCopyProcessExecutor(executablePath: blockingCLI.path)

    let startedAt = Date()
    let runTask = Task { await executor.run(selection) }
    try await Task.sleep(for: .milliseconds(100))
    await executor.cancel()
    let result = await runTask.value

    #expect(result.exitCode == 130)
    #expect(Date().timeIntervalSince(startedAt) < 2)
    #expect(!FileManager.default.fileExists(atPath: selection.destination.path))
}

@MainActor @Test func controllerPublishesSuccessAndRendersACompactResult() async {
    let executor = ImmediateVerifiedCopyExecutor(CommandResult(output: "copy: published", exitCode: 0))
    let controller = VerifiedCopyController(executor: executor)
    controller.start(makeUncheckedSelection(), volumeName: "MEDIA")
    await waitForPhase(.succeeded, controller: controller)

    #expect(controller.phase == .succeeded)
    #expect(controller.message == "SHA-256 manifest matched. Destination published.")
    #expect(await executor.runCount == 1)
    let image = ImageRenderer(content: VerifiedCopyStatusView(controller: controller)).nsImage
    #expect(image?.size.width ?? 0 > 0)
    #expect(image?.size.height ?? 0 > 0)
}

@MainActor @Test func controllerAllowsOnlyOneCopyAndSurfacesCancellation() async {
    let executor = BlockingVerifiedCopyExecutor()
    let controller = VerifiedCopyController(executor: executor)
    controller.start(makeUncheckedSelection(suffix: "first"), volumeName: "MEDIA")

    for _ in 0..<250 {
        if await executor.counts().runs == 1 { break }
        try? await Task.sleep(for: .milliseconds(1))
    }
    controller.start(makeUncheckedSelection(suffix: "second"), volumeName: "OTHER")
    #expect(controller.sourceName == "source-first")

    controller.cancel()
    await waitForPhase(.cancelled, controller: controller)
    let counts = await executor.counts()

    #expect(controller.phase == .cancelled)
    #expect(controller.message.contains("recoverable partial"))
    #expect(counts.runs == 1)
    #expect(counts.cancellations >= 1)
}

@MainActor @Test func controllerSurfacesConciseFailureAndCanDismissIt() async {
    let executor = ImmediateVerifiedCopyExecutor(CommandResult(
        output: "first detail\ncopy: destination already exists; refusing to overwrite\n",
        exitCode: 1
    ))
    let controller = VerifiedCopyController(executor: executor)
    controller.start(makeUncheckedSelection(), volumeName: "MEDIA")
    await waitForPhase(.failed, controller: controller)

    #expect(controller.message == "copy: destination already exists; refusing to overwrite")
    controller.dismiss()
    #expect(controller.phase == .idle)
    #expect(!controller.isVisible)
}
