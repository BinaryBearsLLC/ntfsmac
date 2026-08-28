import Foundation
import HelperShared
import Testing
@testable import NtfsmacGUI

@MainActor
private final class FakeDiskAccessChecker: FullDiskAccessChecking, Sendable {
    var results: [Result<CommandResult, Error>]
    private(set) var devices: [String] = []

    init(_ results: [Result<CommandResult, Error>]) {
        self.results = results
    }

    func checkDeviceAccess(device: String) async throws -> CommandResult {
        devices.append(device)
        return try results.removeFirst().get()
    }
}

@MainActor
@Test func fullDiskAccessWaitsForARealDriveWithoutCallingTheHelper() async {
    let checker = FakeDiskAccessChecker([.success(CommandResult(output: "", exitCode: 0))])
    let controller = FullDiskAccessController(checker: checker)

    await controller.check(deviceID: nil)

    #expect(controller.state == .waitingForDrive)
    #expect(checker.devices.isEmpty)
}

@Test func noDriveIsNormalIdleInsteadOfIncompleteSetup() {
    let unverifiedStates: [FullDiskAccessState] = [
        .notChecked,
        .checking,
        .waitingForDrive,
        .needsAuthorization,
        .waitingForAuthorization,
        .failed("helper unavailable"),
    ]

    for state in unverifiedStates {
        #expect(!FullDiskAccessPresentationPolicy.shouldPresentSetup(
            state: state,
            deviceID: nil,
            driveDiscoveryFailed: false
        ))
    }
}

@Test func detectedDriveStillRequiresARealAccessProbe() {
    #expect(FullDiskAccessPresentationPolicy.shouldPresentSetup(
        state: .notChecked,
        deviceID: "disk6s1",
        driveDiscoveryFailed: false
    ))
    #expect(FullDiskAccessPresentationPolicy.shouldPresentSetup(
        state: .needsAuthorization,
        deviceID: "disk6s1",
        driveDiscoveryFailed: false
    ))
    #expect(!FullDiskAccessPresentationPolicy.shouldPresentSetup(
        state: .granted,
        deviceID: "disk6s1",
        driveDiscoveryFailed: false
    ))
}

@Test func discoveryFailureStillSurfacesWithoutInventingAMissingDrive() {
    #expect(FullDiskAccessPresentationPolicy.shouldPresentSetup(
        state: .waitingForDrive,
        deviceID: nil,
        driveDiscoveryFailed: true
    ))
    #expect(!FullDiskAccessPresentationPolicy.shouldPresentSetup(
        state: .granted,
        deviceID: nil,
        driveDiscoveryFailed: true
    ))
}

@Test func diagnosticsDistinguishUnprobedAccessFromDenial() {
    #expect(FullDiskAccessPresentationPolicy.diagnosticGrantEvidence(for: .notChecked) == nil)
    #expect(FullDiskAccessPresentationPolicy.diagnosticGrantEvidence(for: .waitingForDrive) == nil)
    #expect(FullDiskAccessPresentationPolicy.diagnosticGrantEvidence(for: .needsAuthorization) == false)
    #expect(FullDiskAccessPresentationPolicy.diagnosticGrantEvidence(for: .granted) == true)
}

@MainActor
@Test func fullDiskAccessProbeUnlocksTheMainInterfaceOnSuccess() async {
    let checker = FakeDiskAccessChecker([.success(CommandResult(output: "", exitCode: 0))])
    let controller = FullDiskAccessController(checker: checker)

    await controller.check(deviceID: "disk6s1")

    #expect(controller.state == .granted)
    #expect(checker.devices == ["disk6s1"])
}

@MainActor
@Test func fullDiskAccessProbeRequiresAuthorizationBeforeMounting() async {
    let checker = FakeDiskAccessChecker([.success(CommandResult(output: "Operation not permitted", exitCode: 1))])
    let controller = FullDiskAccessController(checker: checker)

    await controller.check(deviceID: "disk6s1")

    #expect(controller.state == .needsAuthorization)
    controller.beginAuthorization()
    #expect(controller.state == .waitingForAuthorization)
    #expect(controller.authorizationAttempt == 1)
}

@MainActor
@Test func fullDiskAccessResetClosesTheGateAfterRevocation() async {
    let checker = FakeDiskAccessChecker([.success(CommandResult(output: "", exitCode: 0))])
    let controller = FullDiskAccessController(checker: checker, initialState: .granted)

    controller.reset()

    #expect(controller.state == .notChecked)
    #expect(!controller.isGranted)
    #expect(controller.authorizationAttempt == 0)
}

@Test func fullDiskAccessInstructionsUseThePackagedHelperIdentity() {
    #expect(FDAPromptCopy.helperServiceName == helperMachServiceName)
    #expect(FDAPromptCopy.instructions.contains(helperMachServiceName))
    #expect(FDAPromptCopy.instructions.contains("Full Disk Access"))
}
