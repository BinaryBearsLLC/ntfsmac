import Foundation
import Testing
@testable import NtfsmacGUI

// GUI-PLAN.md "Settings page". Acceptance: assert defaults + persistence round-trip.
// Uses an isolated UserDefaults suite per test (never the real .standard domain).

private func makeIsolatedDefaults(_ testName: String) -> UserDefaults {
    let suiteName = "com.khr898.ntfsmac.tests.\(testName).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private enum FakeLoginError: LocalizedError {
    case registrationDenied

    var errorDescription: String? { "registration denied" }
}

private final class FakeLoginService: LaunchAtLoginStatusProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var storedStatus: LaunchAtLoginRegistrationStatus
    private let enabledStatus: LaunchAtLoginRegistrationStatus
    private let shouldThrow: Bool
    private var calls: [Bool] = []

    init(
        status: LaunchAtLoginRegistrationStatus = .disabled,
        enabledStatus: LaunchAtLoginRegistrationStatus = .enabled,
        shouldThrow: Bool = false
    ) {
        storedStatus = status
        self.enabledStatus = enabledStatus
        self.shouldThrow = shouldThrow
    }

    var status: LaunchAtLoginRegistrationStatus {
        lock.withLock { storedStatus }
    }

    func setEnabled(_ enabled: Bool) throws {
        try lock.withLock {
            calls.append(enabled)
            if shouldThrow { throw FakeLoginError.registrationDenied }
            storedStatus = enabled ? enabledStatus : .disabled
        }
    }

    func replaceStatus(_ status: LaunchAtLoginRegistrationStatus) {
        lock.withLock { storedStatus = status }
    }

    var requestedValues: [Bool] {
        lock.withLock { calls }
    }
}

/// Deliberately implements only the original protocol requirement. Its use here is a compile-time
/// regression test for downstream conformers as well as a behavioral fallback test.
private final class LegacyLoginService: LaunchAtLoginService, @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [Bool] = []

    func setEnabled(_ enabled: Bool) {
        lock.withLock { calls.append(enabled) }
    }

    var requestedValues: [Bool] {
        lock.withLock { calls }
    }
}

@MainActor
private func waitForLaunchAtLoginUpdate(_ settings: Settings) async {
    for _ in 0..<100 {
        if !settings.isUpdatingLaunchAtLogin { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(!settings.isUpdatingLaunchAtLogin)
}

@MainActor
@Test func defaultsMatchGuiPlanTable() {
    let defaults = makeIsolatedDefaults(#function)
    let settings = Settings(defaults: defaults, loginService: LegacyLoginService())

    #expect(settings.launchAtLogin == false)
}

@MainActor
@Test func legacyServicesKeepTheOriginalDefaultsBackedBehavior() async {
    let defaults = makeIsolatedDefaults(#function)
    defaults.set(true, forKey: "com.khr898.ntfsmac.settings.launchAtLogin")
    let service = LegacyLoginService()
    let settings = Settings(defaults: defaults, loginService: service)

    #expect(settings.launchAtLogin)

    // Keep the original writable property API working, not only the new explicit UI method.
    settings.launchAtLogin = false
    await waitForLaunchAtLoginUpdate(settings)

    #expect(!settings.launchAtLogin)
    #expect(service.requestedValues == [false])
    #expect(!defaults.bool(forKey: "com.khr898.ntfsmac.settings.launchAtLogin"))
}

@MainActor
@Test func serviceManagementStatusOverridesAStalePersistedValue() {
    let defaults = makeIsolatedDefaults(#function)
    defaults.set(true, forKey: "com.khr898.ntfsmac.settings.launchAtLogin")

    let settings = Settings(defaults: defaults, loginService: FakeLoginService(status: .disabled))

    #expect(!settings.launchAtLogin)
    #expect(!defaults.bool(forKey: "com.khr898.ntfsmac.settings.launchAtLogin"))
}

@MainActor
@Test func launchAtLoginReadsBackSuccessfulRegistration() async {
    let defaults = makeIsolatedDefaults(#function)
    let service = FakeLoginService()
    let settings = Settings(defaults: defaults, loginService: service)

    settings.setLaunchAtLogin(true)
    await waitForLaunchAtLoginUpdate(settings)

    #expect(settings.launchAtLogin)
    #expect(service.status == .enabled)
    #expect(service.requestedValues == [true])
    #expect(defaults.bool(forKey: "com.khr898.ntfsmac.settings.launchAtLogin"))
}

@MainActor
@Test func launchAtLoginFailureRevertsTheSwitchAndSurfacesTheError() async {
    let defaults = makeIsolatedDefaults(#function)
    let settings = Settings(defaults: defaults, loginService: FakeLoginService(shouldThrow: true))

    settings.setLaunchAtLogin(true)
    await waitForLaunchAtLoginUpdate(settings)

    #expect(!settings.launchAtLogin)
    #expect(settings.launchAtLoginMessage?.contains("registration denied") == true)
    #expect(!defaults.bool(forKey: "com.khr898.ntfsmac.settings.launchAtLogin"))
}

@MainActor
@Test func pendingSystemApprovalDoesNotPretendRegistrationSucceeded() async {
    let defaults = makeIsolatedDefaults(#function)
    let settings = Settings(
        defaults: defaults,
        loginService: FakeLoginService(enabledStatus: .requiresApproval)
    )

    settings.setLaunchAtLogin(true)
    await waitForLaunchAtLoginUpdate(settings)

    #expect(!settings.launchAtLogin)
    #expect(settings.launchAtLoginMessage?.contains("System Settings") == true)
}

@MainActor
@Test func anExistingApprovalRequirementIsExplainedWithoutRegisteringAgain() {
    let defaults = makeIsolatedDefaults(#function)
    let service = FakeLoginService(status: .requiresApproval)
    let settings = Settings(defaults: defaults, loginService: service)

    settings.setLaunchAtLogin(true)

    #expect(!settings.launchAtLogin)
    #expect(settings.launchAtLoginMessage?.contains("System Settings") == true)
    #expect(service.requestedValues.isEmpty)
}

@MainActor
@Test func refreshReconcilesAChangeMadeInSystemSettings() {
    let defaults = makeIsolatedDefaults(#function)
    let service = FakeLoginService(status: .disabled)
    let settings = Settings(defaults: defaults, loginService: service)

    service.replaceStatus(.enabled)
    settings.refreshLaunchAtLoginStatus()

    #expect(settings.launchAtLogin)
    #expect(defaults.bool(forKey: "com.khr898.ntfsmac.settings.launchAtLogin"))
}
