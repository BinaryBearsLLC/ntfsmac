import Foundation
import Darwin
import ServiceManagement
import Testing
import HelperShared
@testable import NtfsmacGUI

// GUI-PLAN.md v1 feature 8. Acceptance: mock the install service; assert install/skip/deny
// branches.

private let testExpectedVersion = "test-build-hash"

private final class InstallEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedEvents: [String] = []

    var events: [String] { lock.withLock { storedEvents } }

    func append(_ event: String) {
        lock.withLock { storedEvents.append(event) }
    }
}

private func setTestQuarantine(_ path: String) throws {
    let bytes = Array("0083;00000000;Safari;".utf8)
    let result = bytes.withUnsafeBytes { buffer in
        setxattr(path, "com.apple.quarantine", buffer.baseAddress, buffer.count, 0, XATTR_NOFOLLOW)
    }
    guard result == 0 else {
        throw CocoaError(.fileWriteUnknown)
    }
}

private func hasTestQuarantine(_ path: String) -> Bool {
    getxattr(path, "com.apple.quarantine", nil, 0, 0, XATTR_NOFOLLOW) >= 0
}

private struct FakeInstallService: HelperInstallService {
    let alreadyInstalled: Bool
    let outcome: HelperInstallOutcome

    func isInstalled(label: String) -> Bool { alreadyInstalled }
    func bless(label: String) -> HelperInstallOutcome { outcome }
}

private final class ApprovalInstallService: HelperInstallService, @unchecked Sendable {
    private let lock = NSLock()
    var approvalRequired: Bool
    private(set) var blessCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(approvalRequired: Bool) {
        self.approvalRequired = approvalRequired
    }

    func isInstalled(label: String) -> Bool { false }
    func requiresApproval(label: String) -> Bool { approvalRequired }

    func bless(label: String) -> HelperInstallOutcome {
        lock.withLock { blessCallCount += 1 }
        return .requiresApproval("Approve ntfsmac in Login Items.")
    }

    func openApprovalSettings() {
        lock.withLock { openSettingsCallCount += 1 }
    }
}

private final class StaleModernInstallService: HelperInstallService, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var unregisterCallCount = 0
    private(set) var blessCallCount = 0
    let requiresPostInstallHealthCheck = true

    func isInstalled(label: String) -> Bool { true }

    func unregister(label: String) async -> HelperInstallOutcome? {
        lock.withLock { unregisterCallCount += 1 }
        return .installed
    }

    func bless(label: String) -> HelperInstallOutcome {
        lock.withLock { blessCallCount += 1 }
        return .installed
    }
}

private final class LegacyMigrationInstallService: HelperInstallService, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var legacyLabel: String?
    private(set) var newLabel: String?
    private(set) var blessCount = 0

    func isInstalled(label: String) -> Bool { false }

    func bless(label: String) -> HelperInstallOutcome {
        lock.withLock { blessCount += 1 }
        return .failed("a separate bless must not run after migration")
    }

    func migrateLegacyHelper(legacyLabel: String, newLabel: String) -> HelperInstallOutcome? {
        lock.withLock {
            self.legacyLabel = legacyLabel
            self.newLabel = newLabel
        }
        return .installed
    }
}

@MainActor
@Test func installMigratesThePreV3HelperBeforeBlessingSeparately() async {
    let service = LegacyMigrationInstallService()
    let installer = HelperInstaller(service: service)

    await installer.install()

    #expect(installer.state == .installed)
    #expect(service.legacyLabel == legacyHelperMachServiceName)
    #expect(service.newLabel == helperMachServiceName)
    #expect(service.blessCount == 0)
}

/// Counts `stripQuarantine()` calls the same way `CountingInstallService` counts `bless()` —
/// proving `install()` actually invokes it (and does so before `bless()`, matching the real
/// fresh-machine failure mode: a still-quarantined embedded helper tool must be cleaned before
/// `SMJobBless` copies it out to `/Library/PrivilegedHelperTools/`).
private final class FakeQuarantineStripper: QuarantineStripping, @unchecked Sendable {
    private let lock = NSLock()
    private var _callCount = 0

    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    func stripQuarantine() {
        lock.lock(); _callCount += 1; lock.unlock()
    }
}

/// Reports whatever version `installIfNeededSkipsWhenAlreadyInstalled`-style tests need a
/// registered helper to look "current" (`versionResult` matching `testExpectedVersion`), or lets
/// staleness tests simulate a mismatched/unresponsive one. Counts `uninstallHelper()` calls the
/// same way `CountingInstallService` counts `bless()` — proving the self-heal path actually ran,
/// not just that the end state happens to converge.
@MainActor
private final class FakeStaleDetector: StaleHelperDetecting, Sendable {
    var versionResult: Result<String, Error> = .success(testExpectedVersion)
    let versionAfterFirstRead: Result<String, Error>?
    let versionAfterUninstall: Result<String, Error>?
    private(set) var uninstallCallCount = 0
    private(set) var cleanupCallCount = 0
    var cleanupResult = CommandResult(output: "removed", exitCode: 0)
    let events: InstallEventRecorder?
    // Simulates a helper old/wedged enough to never resolve `version()` at all — the exact case
    // `withStaleCheckTimeout` exists for. `Task.sleep` here vastly outlasts any test's injected
    // timeout, so it proves the bound actually fires rather than the call happening to finish fast.
    var hangsOnVersion = false

    init(
        versionResult: Result<String, Error> = .success(testExpectedVersion),
        versionAfterFirstRead: Result<String, Error>? = nil,
        versionAfterUninstall: Result<String, Error>? = nil,
        events: InstallEventRecorder? = nil
    ) {
        self.versionResult = versionResult
        self.versionAfterFirstRead = versionAfterFirstRead
        self.versionAfterUninstall = versionAfterUninstall
        self.events = events
    }

    func version() async throws -> String {
        events?.append("version")
        if hangsOnVersion {
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
        let result = versionResult
        if let versionAfterFirstRead {
            versionResult = versionAfterFirstRead
        }
        return try result.get()
    }

    func uninstallHelper() async throws -> CommandResult {
        events?.append("uninstall-current")
        uninstallCallCount += 1
        if let versionAfterUninstall {
            versionResult = versionAfterUninstall
        }
        return CommandResult(output: "uninstalled", exitCode: 0)
    }

    func cleanupRetiredHelpers() async throws -> CommandResult {
        events?.append("cleanup-retired")
        cleanupCallCount += 1
        return cleanupResult
    }
}

private final class TransactionalModernInstallService: HelperInstallService, @unchecked Sendable {
    let requiresPostInstallHealthCheck = true
    let outcome: HelperInstallOutcome
    let events: InstallEventRecorder

    init(outcome: HelperInstallOutcome, events: InstallEventRecorder) {
        self.outcome = outcome
        self.events = events
    }

    func isInstalled(label: String) -> Bool { false }

    func bless(label: String) -> HelperInstallOutcome {
        events.append("register-modern")
        return outcome
    }

    func unregister(label: String) async -> HelperInstallOutcome? {
        events.append("unregister-modern-start")
        try? await Task.sleep(for: .milliseconds(20))
        events.append("unregister-modern-finished")
        return .installed
    }
}

@MainActor
private final class NonCooperativeStaleDetector: StaleHelperDetecting, Sendable {
    func version() async throws -> String {
        await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
        return testExpectedVersion
    }

    func uninstallHelper() async throws -> CommandResult {
        CommandResult(output: "uninstalled", exitCode: 0)
    }
}

/// Counts `bless()` calls so a test can prove `installIfNeeded()` does — or does not — re-prompt.
/// `MenuBarExtra(.window)` rebuilds `FirstRunView` (and refires its `.task`) every time the
/// popover reopens, so this simulates "user taps the menu icon again" after a denial/failure.
private final class CountingInstallService: HelperInstallService, @unchecked Sendable {
    private let lock = NSLock()
    private var _blessCallCount = 0
    let alreadyInstalled: Bool
    let outcome: HelperInstallOutcome

    init(alreadyInstalled: Bool, outcome: HelperInstallOutcome) {
        self.alreadyInstalled = alreadyInstalled
        self.outcome = outcome
    }

    var blessCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _blessCallCount
    }

    func isInstalled(label: String) -> Bool { alreadyInstalled }

    func bless(label: String) -> HelperInstallOutcome {
        lock.lock(); _blessCallCount += 1; lock.unlock()
        return outcome
    }
}

/// `bless()` is real production code's synchronous, blocking API (matches `SMJobBless` itself).
/// This double blocks on a semaphore until the test calls `resume(with:)` — it runs on the
/// `DispatchQueue.global` thread `HelperInstaller.runOffCooperativePool` dispatches to, so
/// blocking here is exactly what the real synchronous call does, not a test artifact.
private final class BlockingInstallService: HelperInstallService, @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var _blessCallCount = 0
    private var outcome: HelperInstallOutcome = .installed

    var blessCallCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _blessCallCount
    }

    func isInstalled(label: String) -> Bool { false }

    func bless(label: String) -> HelperInstallOutcome {
        lock.lock()
        _blessCallCount += 1
        lock.unlock()
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }

    func resume(with outcome: HelperInstallOutcome) {
        lock.lock()
        self.outcome = outcome
        lock.unlock()
        semaphore.signal()
    }
}

@MainActor
@Test func installIfNeededSkipsWhenAlreadyInstalledAndCurrent() async {
    // `outcome` is deliberately `.failed` (not `.installed`): if `installIfNeeded()` ever called
    // `bless()` instead of actually skipping, the final state would be `.failed`, not
    // `.installed` — proves the skip path is taken, not just that both paths happen to converge.
    let service = FakeInstallService(alreadyInstalled: true, outcome: .failed("bless() should not have been called"))
    let staleDetector = FakeStaleDetector(versionResult: .success(testExpectedVersion))
    let installer = HelperInstaller(service: service, staleDetector: staleDetector, label: "com.binarybears.ntfsmac.helper", expectedVersion: testExpectedVersion)

    await installer.installIfNeeded()

    #expect(installer.state == .installed)
    #expect(staleDetector.uninstallCallCount == 0)
}

@MainActor
@Test func passiveFirstRunCheckNeverBlessesAMissingHelper() async {
    let service = CountingInstallService(alreadyInstalled: false, outcome: .installed)
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.checkWithoutInstalling()

    #expect(installer.state == .readyToInstall)
    #expect(service.blessCallCount == 0)
}

@MainActor
@Test func passiveCheckSurfacesModernApprovalWithoutRegisteringAgain() async {
    let service = ApprovalInstallService(approvalRequired: true)
    let installer = HelperInstaller(service: service)

    await installer.checkWithoutInstalling()

    guard case .requiresApproval(let message) = installer.state else {
        Issue.record("Expected requiresApproval, got \(installer.state)")
        return
    }
    #expect(message.contains("Login Items"))
    #expect(service.blessCallCount == 0)
    #expect(installer.state.isDeniedOrFailed)
}

@MainActor
@Test func approvalSettingsActionDelegatesToServiceManagementAdapter() {
    let service = ApprovalInstallService(approvalRequired: true)
    let installer = HelperInstaller(service: service)

    installer.openApprovalSettings()

    #expect(service.openSettingsCallCount == 1)
}

@MainActor
@Test func registrationCanTransitionToModernApprovalState() async {
    let service = ApprovalInstallService(approvalRequired: false)
    let installer = HelperInstaller(service: service)

    await installer.installAfterConsent()

    #expect(installer.state == .requiresApproval("Approve ntfsmac in Login Items."))
    #expect(service.blessCallCount == 1)
}

@Test func modernRegistrationPermissionErrorsRouteToLoginItemsRecoveryOnly() {
    let directPermissionError = NSError(
        domain: "SMAppServiceErrorDomain",
        code: Int(POSIXErrorCode.EPERM.rawValue)
    )
    let wrappedLaunchDenial = NSError(
        domain: NSCocoaErrorDomain,
        code: CocoaError.fileReadUnknown.rawValue,
        userInfo: [
            NSUnderlyingErrorKey: NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(kSMErrorLaunchDeniedByUser)
            )
        ]
    )
    let invalidSignature = NSError(
        domain: NSOSStatusErrorDomain,
        code: Int(kSMErrorInvalidSignature)
    )

    #expect(ModernRegistrationErrorPolicy.requiresLoginItemsRecovery(directPermissionError))
    #expect(ModernRegistrationErrorPolicy.requiresLoginItemsRecovery(wrappedLaunchDenial))
    #expect(!ModernRegistrationErrorPolicy.requiresLoginItemsRecovery(invalidSignature))
}

@MainActor
@Test func explicitConsentInstallsAfterPassiveCheck() async {
    let service = CountingInstallService(alreadyInstalled: false, outcome: .installed)
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.checkWithoutInstalling()
    await installer.installAfterConsent()

    #expect(installer.state == .installed)
    #expect(service.blessCallCount == 1)
}

@MainActor
@Test func installIfNeededSelfHealsWhenRegisteredHelperReportsAMismatchedVersion() async {
    // Simulates a daemon left running from a previous build: `SMJobCopyDictionary` sees it as
    // "installed", but its baked-in hash is stale. Real fix: clear it out via its own still-live
    // `uninstallHelper`, then bless a fresh one — same one-auth-prompt path a first install takes.
    let service = CountingInstallService(alreadyInstalled: true, outcome: .installed)
    let staleDetector = FakeStaleDetector(versionResult: .success("old-build-hash"))
    let installer = HelperInstaller(service: service, staleDetector: staleDetector, label: "com.binarybears.ntfsmac.helper", expectedVersion: testExpectedVersion)

    await installer.installIfNeeded()

    #expect(staleDetector.uninstallCallCount == 1)
    #expect(service.blessCallCount == 1)
    #expect(installer.state == .installed)
}

@MainActor
@Test func staleModernRegistrationIsUnregisteredBeforeReplacement() async {
    let service = StaleModernInstallService()
    let staleDetector = FakeStaleDetector(
        versionResult: .success("old-build-hash"),
        versionAfterFirstRead: .success(testExpectedVersion)
    )
    let installer = HelperInstaller(
        service: service,
        staleDetector: staleDetector,
        expectedVersion: testExpectedVersion
    )

    await installer.installAfterConsent()

    #expect(staleDetector.uninstallCallCount == 0)
    #expect(service.unregisterCallCount == 1)
    #expect(service.blessCallCount == 1)
    #expect(staleDetector.cleanupCallCount == 1)
    #expect(installer.state == .installed)
}

@MainActor
@Test func settingsRepairReplacesEvenACurrentRegisteredHelper() async {
    let service = StaleModernInstallService()
    let currentDetector = FakeStaleDetector(
        versionResult: .success(testExpectedVersion),
        versionAfterUninstall: .success(testExpectedVersion)
    )
    let installer = HelperInstaller(
        service: service,
        staleDetector: currentDetector,
        expectedVersion: testExpectedVersion
    )

    await installer.reinstallAfterConsent()

    #expect(currentDetector.uninstallCallCount == 0)
    #expect(service.unregisterCallCount == 1)
    #expect(service.blessCallCount == 1)
    #expect(currentDetector.cleanupCallCount == 1)
    #expect(installer.state == .installed)
}

@MainActor
@Test func standardInstallRemovesLegacyOnlyAfterModernXPCIsHealthy() async {
    let events = InstallEventRecorder()
    let service = TransactionalModernInstallService(outcome: .installed, events: events)
    let detector = FakeStaleDetector(events: events)
    let installer = HelperInstaller(
        service: service,
        staleDetector: detector,
        expectedVersion: testExpectedVersion,
        staleCheckTimeoutNanoseconds: 50_000_000
    )

    await installer.install()

    #expect(events.events == ["register-modern", "version", "cleanup-retired"])
    #expect(detector.cleanupCallCount == 1)
    #expect(installer.state == .installed)
}

@MainActor
@Test func deniedModernInstallLeavesLegacyUntouched() async {
    let events = InstallEventRecorder()
    let service = TransactionalModernInstallService(
        outcome: .requiresApproval("Approval required."),
        events: events
    )
    let detector = FakeStaleDetector(events: events)
    let installer = HelperInstaller(service: service, staleDetector: detector)

    await installer.install()

    #expect(events.events == ["register-modern"])
    #expect(detector.cleanupCallCount == 0)
    #expect(installer.state == .requiresApproval("Approval required."))
}

@MainActor
@Test func transientModernStartupFailureWaitsWithoutDestroyingApproval() async {
    let events = InstallEventRecorder()
    let service = TransactionalModernInstallService(outcome: .installed, events: events)
    let detector = FakeStaleDetector(
        versionResult: .success("wrong-version"),
        versionAfterFirstRead: .success(testExpectedVersion),
        events: events
    )
    let installer = HelperInstaller(
        service: service,
        staleDetector: detector,
        expectedVersion: testExpectedVersion,
        postRegistrationHealthCheckAttempts: 2,
        postRegistrationHealthCheckDelayNanoseconds: 1_000_000
    )

    await installer.install()

    #expect(events.events == [
        "register-modern", "version", "version", "cleanup-retired",
    ])
    #expect(detector.cleanupCallCount == 1)
    #expect(installer.state == .installed)
}

@MainActor
@Test func persistentModernHealthFailureStopsAfterOneRepairAndLeavesLegacyUntouched() async {
    let events = InstallEventRecorder()
    let service = TransactionalModernInstallService(outcome: .installed, events: events)
    let detector = FakeStaleDetector(
        versionResult: .success("wrong-version"),
        events: events
    )
    let installer = HelperInstaller(
        service: service,
        staleDetector: detector,
        expectedVersion: testExpectedVersion,
        postRegistrationHealthCheckAttempts: 2,
        postRegistrationHealthCheckDelayNanoseconds: 1_000_000
    )

    await installer.install()

    #expect(events.events == [
        "register-modern", "version", "version", "unregister-modern-start",
        "unregister-modern-finished", "register-modern", "version", "version",
    ])
    #expect(detector.cleanupCallCount == 0)
    guard case .failed(let message) = installer.state else {
        Issue.record("A broken modern helper must fail without touching Legacy")
        return
    }
    #expect(message.contains("after an automatic repair"))
}

@MainActor
@Test func installIfNeededSelfHealsWhenRegisteredHelperDoesNotRespond() async {
    // A helper old enough to predate `version()` entirely (or just wedged) can't answer at all —
    // reads as stale exactly like a mismatched hash, not as "installed" by default.
    let service = CountingInstallService(alreadyInstalled: true, outcome: .installed)
    let staleDetector = FakeStaleDetector(versionResult: .failure(HelperClientError.proxyUnavailable))
    let installer = HelperInstaller(service: service, staleDetector: staleDetector, label: "com.binarybears.ntfsmac.helper", expectedVersion: testExpectedVersion)

    await installer.installIfNeeded()

    #expect(staleDetector.uninstallCallCount == 1)
    #expect(service.blessCallCount == 1)
    #expect(installer.state == .installed)
}

@MainActor
@Test func installIfNeededSelfHealsWhenRegisteredHelperHangsInsteadOfAnswering() async {
    // A helper old enough to predate `version()` entirely can leave the reply continuation
    // unresolved rather than erroring cleanly (same hang class `HelperClient.call()`'s own doc
    // comment already covers for known selectors — this is the unknown-future-selector version of
    // it). `withStaleCheckTimeout`'s bound is what turns that into "treat as stale" instead of an
    // indefinite wait; a real 5s default would make this test slow, so a 50ms timeout is injected.
    let service = CountingInstallService(alreadyInstalled: true, outcome: .installed)
    let staleDetector = FakeStaleDetector()
    staleDetector.hangsOnVersion = true
    let installer = HelperInstaller(
        service: service,
        staleDetector: staleDetector,
        label: "com.binarybears.ntfsmac.helper",
        expectedVersion: testExpectedVersion,
        staleCheckTimeoutNanoseconds: 50_000_000
    )

    await installer.installIfNeeded()

    #expect(staleDetector.uninstallCallCount == 1)
    #expect(service.blessCallCount == 1)
    #expect(installer.state == .installed)
}

@MainActor
@Test func timeoutReturnsWhenTheXPCOperationIgnoresCancellation() async {
    let service = CountingInstallService(alreadyInstalled: true, outcome: .installed)
    let installer = HelperInstaller(
        service: service,
        staleDetector: NonCooperativeStaleDetector(),
        expectedVersion: testExpectedVersion,
        staleCheckTimeoutNanoseconds: 50_000_000
    )
    let started = ContinuousClock.now

    await installer.checkWithoutInstalling()

    #expect(ContinuousClock.now - started < .seconds(1))
    #expect(installer.state == .readyToInstall)
}

@MainActor
@Test func installStripsQuarantineBeforeEveryBlessAttempt() async {
    let service = FakeInstallService(alreadyInstalled: false, outcome: .installed)
    let stripper = FakeQuarantineStripper()
    let installer = HelperInstaller(service: service, quarantineStripper: stripper, label: "com.binarybears.ntfsmac.helper")

    await installer.install()
    #expect(stripper.callCount == 1)
    #expect(installer.state == .installed)

    // Retry (Preferences "Reinstall") must also strip again — a quarantine tag can persist across
    // attempts on a fresh machine, not just the first one.
    await installer.install()
    #expect(stripper.callCount == 2)
}

@Test func realQuarantineStripperRemovesPresentTagsWithoutFollowingSymlinks() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("ntfsmac-quarantine-\(UUID().uuidString)")
    let file = root.appendingPathComponent("helper")
    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent("ntfsmac-quarantine-outside-\(UUID().uuidString)")
    let link = root.appendingPathComponent("outside-link")
    defer {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: outside)
    }

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    try Data("helper".utf8).write(to: file)
    try Data("outside".utf8).write(to: outside)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    try setTestQuarantine(file.path)
    try setTestQuarantine(outside.path)

    RealQuarantineStripper.stripQuarantine(at: root)

    #expect(!hasTestQuarantine(file.path))
    #expect(hasTestQuarantine(outside.path))
}

@MainActor
@Test func installIfNeededBlessesWhenNotInstalled() async {
    let service = FakeInstallService(alreadyInstalled: false, outcome: .installed)
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.installIfNeeded()

    #expect(installer.state == .installed)
}

@MainActor
@Test func installSurfacesDenialAsPlainLanguageState() async {
    let service = FakeInstallService(alreadyInstalled: false, outcome: .denied("Authorization was cancelled."))
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.install()

    #expect(installer.state == .denied("Authorization was cancelled."))
}

@MainActor
@Test func installSurfacesFailureAsPlainLanguageState() async {
    let service = FakeInstallService(alreadyInstalled: false, outcome: .failed("SMJobBless failed for an unknown reason."))
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.install()

    #expect(installer.state == .failed("SMJobBless failed for an unknown reason."))
}

@MainActor
@Test func retryReusesTheSameInstallPath() async {
    // Do clause: "reuse this path for the Preferences 'Reinstall privileged helper' button" —
    // there's no separate reinstall method; calling install() again after a denial is that
    // reuse, and it must be able to recover to .installed.
    let service = FakeInstallService(alreadyInstalled: false, outcome: .installed)
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.install()
    #expect(installer.state == .installed)

    await installer.install()
    #expect(installer.state == .installed)
}

@MainActor
@Test func installIfNeededDoesNotReattemptBlessAfterDenial() async {
    // Bug repro: reopening the menu-bar popover recreates `FirstRunView`, refiring its
    // `.task { installIfNeeded() }`. A prior denial/failure must not cause a second `bless()`
    // call (and thus a second OS auth prompt) — only the explicit "Retry" button may do that.
    let service = CountingInstallService(alreadyInstalled: false, outcome: .denied("Authorization was denied — an administrator password is required."))
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.installIfNeeded()
    #expect(installer.state == .denied("Authorization was denied — an administrator password is required."))
    #expect(service.blessCallCount == 1)

    await installer.installIfNeeded()
    #expect(service.blessCallCount == 1)
}

@MainActor
@Test func installIfNeededDoesNotReattemptBlessAfterFailure() async {
    let service = CountingInstallService(alreadyInstalled: false, outcome: .failed("SMJobBless failed for an unknown reason."))
    let installer = HelperInstaller(service: service, label: "com.binarybears.ntfsmac.helper")

    await installer.installIfNeeded()
    #expect(service.blessCallCount == 1)

    await installer.installIfNeeded()
    #expect(service.blessCallCount == 1)
}

@MainActor
@Test func secondInstallWhileFirstInFlightIsRejected() async {
    let blocking = BlockingInstallService()
    let installer = HelperInstaller(service: blocking, label: "com.binarybears.ntfsmac.helper")

    let firstTask = Task { await installer.install() }
    // bless() runs on a real background thread (DispatchQueue.global), not MainActor-serialized
    // — poll until it's actually started rather than assuming a single yield suffices.
    while blocking.blessCallCount == 0 {
        await Task.yield()
    }
    #expect(installer.state == .installing)

    await installer.install()
    #expect(blocking.blessCallCount == 1)

    blocking.resume(with: .installed)
    await firstTask.value

    #expect(blocking.blessCallCount == 1)
    #expect(installer.state == .installed)
}
