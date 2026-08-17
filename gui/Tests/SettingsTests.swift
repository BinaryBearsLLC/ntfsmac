import Foundation
import ServiceManagement
import Testing
@testable import NtfsmacGUI

// GUI-PLAN.md "Settings page". Acceptance: assert defaults + persistence round-trip.
// Uses an isolated UserDefaults suite per test (never the real .standard domain).

private func makeIsolatedDefaults(_ testName: String) -> UserDefaults {
    let suiteName = "com.binarybears.ntfsmac.tests.\(testName).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private enum FakeLoginError: LocalizedError {
    case registrationDenied

    var errorDescription: String? { "registration denied" }
}

private enum FakeNotificationError: LocalizedError {
    case requestFailed

    var errorDescription: String? { "notification request failed" }
}

private final class FakeNotificationAuthorization: NotificationAuthorizationManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var storedState: NotificationAuthorizationState
    private let requestResult: Result<Bool, Error>
    private let stateAfterRequestFailure: NotificationAuthorizationState?
    private var requests = 0

    init(
        state: NotificationAuthorizationState,
        requestResult: Result<Bool, Error> = .success(true),
        stateAfterRequestFailure: NotificationAuthorizationState? = nil
    ) {
        storedState = state
        self.requestResult = requestResult
        self.stateAfterRequestFailure = stateAfterRequestFailure
    }

    func authorizationState() async -> NotificationAuthorizationState {
        lock.withLock { storedState }
    }

    func requestAuthorization() async throws -> Bool {
        try lock.withLock {
            requests += 1
            do {
                let granted = try requestResult.get()
                storedState = granted ? .authorized : .denied
                return granted
            } catch {
                if let stateAfterRequestFailure {
                    storedState = stateAfterRequestFailure
                }
                throw error
            }
        }
    }

    var requestCount: Int { lock.withLock { requests } }
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

@Test func aFreshMainAppNotFoundStatusStillAllowsRegistrationAttempt() {
    #expect(RealLaunchAtLoginService.map(.notFound) == .disabled)
}

@MainActor
private func waitForNotificationUpdate(_ settings: Settings) async {
    for _ in 0..<100 {
        if !settings.isUpdatingNotifications { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(!settings.isUpdatingNotifications)
}

@MainActor
@Test func defaultsMatchGuiPlanTable() {
    let defaults = makeIsolatedDefaults(#function)
    let settings = Settings(defaults: defaults, loginService: LegacyLoginService())

    #expect(settings.launchAtLogin == false)
    #expect(settings.notificationsEnabled == false)
}

@MainActor
@Test func notificationOptInRequestsPermissionAndPersistsOnlyAConfirmedGrant() async {
    let defaults = makeIsolatedDefaults(#function)
    let authorization = FakeNotificationAuthorization(state: .notDetermined)
    let settings = Settings(
        defaults: defaults,
        loginService: LegacyLoginService(),
        notificationAuthorization: authorization
    )

    settings.setNotificationsEnabled(true)
    await waitForNotificationUpdate(settings)

    #expect(settings.notificationsEnabled)
    #expect(authorization.requestCount == 1)
    #expect(defaults.bool(forKey: "com.binarybears.ntfsmac.settings.notificationsEnabled"))
}

@MainActor
@Test func deniedNotificationPermissionKeepsThePreferenceOff() async {
    let defaults = makeIsolatedDefaults(#function)
    let authorization = FakeNotificationAuthorization(state: .denied)
    let settings = Settings(
        defaults: defaults,
        loginService: LegacyLoginService(),
        notificationAuthorization: authorization
    )

    settings.setNotificationsEnabled(true)
    await waitForNotificationUpdate(settings)

    #expect(!settings.notificationsEnabled)
    #expect(authorization.requestCount == 0)
    #expect(settings.notificationsMessage?.contains("System Settings") == true)
}

@MainActor
@Test func notificationRequestFailureIsVisibleAndNeverPersistsOptIn() async {
    let defaults = makeIsolatedDefaults(#function)
    let authorization = FakeNotificationAuthorization(
        state: .notDetermined,
        requestResult: .failure(FakeNotificationError.requestFailed)
    )
    let settings = Settings(
        defaults: defaults,
        loginService: LegacyLoginService(),
        notificationAuthorization: authorization
    )

    settings.setNotificationsEnabled(true)
    await waitForNotificationUpdate(settings)

    #expect(!settings.notificationsEnabled)
    #expect(settings.notificationsMessage?.contains("notification request failed") == true)
    #expect(!defaults.bool(forKey: "com.binarybears.ntfsmac.settings.notificationsEnabled"))
}

@MainActor
@Test func notificationRequestErrorRecoversWhenSystemAuthorizationWasCommitted() async {
    let defaults = makeIsolatedDefaults(#function)
    let authorization = FakeNotificationAuthorization(
        state: .notDetermined,
        requestResult: .failure(FakeNotificationError.requestFailed),
        stateAfterRequestFailure: .authorized
    )
    let settings = Settings(
        defaults: defaults,
        loginService: LegacyLoginService(),
        notificationAuthorization: authorization
    )

    settings.setNotificationsEnabled(true)
    await waitForNotificationUpdate(settings)

    #expect(settings.notificationsEnabled)
    #expect(settings.notificationsMessage == nil)
    #expect(defaults.bool(forKey: "com.binarybears.ntfsmac.settings.notificationsEnabled"))
}

@MainActor
@Test func legacyServicesKeepTheOriginalDefaultsBackedBehavior() async {
    let defaults = makeIsolatedDefaults(#function)
    defaults.set(true, forKey: "com.binarybears.ntfsmac.settings.launchAtLogin")
    let service = LegacyLoginService()
    let settings = Settings(defaults: defaults, loginService: service)

    #expect(settings.launchAtLogin)

    // Keep the original writable property API working, not only the new explicit UI method.
    settings.launchAtLogin = false
    await waitForLaunchAtLoginUpdate(settings)

    #expect(!settings.launchAtLogin)
    #expect(service.requestedValues == [false])
    #expect(!defaults.bool(forKey: "com.binarybears.ntfsmac.settings.launchAtLogin"))
}

@MainActor
@Test func serviceManagementStatusOverridesAStalePersistedValue() {
    let defaults = makeIsolatedDefaults(#function)
    defaults.set(true, forKey: "com.binarybears.ntfsmac.settings.launchAtLogin")

    let settings = Settings(defaults: defaults, loginService: FakeLoginService(status: .disabled))

    #expect(!settings.launchAtLogin)
    #expect(!defaults.bool(forKey: "com.binarybears.ntfsmac.settings.launchAtLogin"))
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
    #expect(defaults.bool(forKey: "com.binarybears.ntfsmac.settings.launchAtLogin"))
}

@MainActor
@Test func launchAtLoginFailureRevertsTheSwitchAndSurfacesTheError() async {
    let defaults = makeIsolatedDefaults(#function)
    let settings = Settings(defaults: defaults, loginService: FakeLoginService(shouldThrow: true))

    settings.setLaunchAtLogin(true)
    await waitForLaunchAtLoginUpdate(settings)

    #expect(!settings.launchAtLogin)
    #expect(settings.launchAtLoginMessage?.contains("registration denied") == true)
    #expect(!defaults.bool(forKey: "com.binarybears.ntfsmac.settings.launchAtLogin"))
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
    #expect(defaults.bool(forKey: "com.binarybears.ntfsmac.settings.launchAtLogin"))
}
