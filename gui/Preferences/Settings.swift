import Foundation
import ServiceManagement

public enum LaunchAtLoginRegistrationStatus: Equatable, Sendable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

/// Seam over `SMAppService.mainApp` (macOS 13+, matches L7's floor — not the deprecated
/// `SMLoginItemSetEnabled`) so a toggled-on "Launch at login" preference actually registers the
/// login item rather than just persisting a bool nothing acts on, which would be a silently
/// broken control, not a deferred-integration gap.
public protocol LaunchAtLoginService: Sendable {
    func setEnabled(_ enabled: Bool) throws
}

/// Optional status capability kept separate from `LaunchAtLoginService` so existing service
/// conformers remain source compatible.
public protocol LaunchAtLoginStatusProviding: LaunchAtLoginService {
    var status: LaunchAtLoginRegistrationStatus { get }
}

public struct RealLaunchAtLoginService: LaunchAtLoginStatusProviding {
    public init() {}

    public var status: LaunchAtLoginRegistrationStatus {
        Self.map(SMAppService.mainApp.status)
    }

    public static func map(_ status: SMAppService.Status) -> LaunchAtLoginRegistrationStatus {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            // A freshly replaced ad-hoc bundle can briefly be absent from Background Task
            // Management even though `mainApp.register()` is the documented way to add it.
            // Keep the toggle actionable; a real registration error is surfaced after the call.
            return .disabled
        @unknown default:
            return .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

private enum LaunchAtLoginUpdateResult: Sendable {
    case success(LaunchAtLoginRegistrationStatus)
    case failure(message: String, status: LaunchAtLoginRegistrationStatus)
}

/// Preference state backed by the real Service Management registration. `UserDefaults` mirrors
/// confirmed state and remains the fallback for injected legacy services that cannot report
/// status.
@MainActor
public final class Settings: ObservableObject {
    @Published public var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLaunchAtLoginStatus else { return }
            beginLaunchAtLoginUpdate(launchAtLogin)
        }
    }
    @Published public private(set) var isUpdatingLaunchAtLogin = false
    @Published public private(set) var launchAtLoginMessage: String?
    @Published public private(set) var notificationsEnabled: Bool
    @Published public private(set) var isUpdatingNotifications = false
    @Published public private(set) var notificationsMessage: String?

    private let defaults: UserDefaults
    private let loginService: any LaunchAtLoginService
    private let notificationAuthorization: any NotificationAuthorizationManaging
    private var confirmedLaunchAtLogin: Bool
    private var isApplyingLaunchAtLoginStatus = false

    public init(
        defaults: UserDefaults = .standard,
        loginService: any LaunchAtLoginService = RealLaunchAtLoginService(),
        notificationAuthorization: any NotificationAuthorizationManaging = RealNotificationAuthorizationManager()
    ) {
        self.defaults = defaults
        self.loginService = loginService
        self.notificationAuthorization = notificationAuthorization

        let persisted = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? Defaults.launchAtLogin
        let registrationStatus = Self.registrationStatus(for: loginService, fallbackEnabled: persisted)
        let initialValue = registrationStatus == .enabled

        launchAtLogin = initialValue
        confirmedLaunchAtLogin = initialValue
        launchAtLoginMessage = Self.message(for: registrationStatus)
        notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool
            ?? Defaults.notificationsEnabled
        notificationsMessage = nil
        defaults.set(initialValue, forKey: Keys.launchAtLogin)
        defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled)
    }

    /// Updates the real Service Management registration and then reads it back. The explicit
    /// method powers the UI while the original writable `launchAtLogin` property remains supported
    /// for existing callers.
    public func setLaunchAtLogin(_ enabled: Bool) {
        guard !isUpdatingLaunchAtLogin else { return }
        setPublishedLaunchAtLogin(enabled)
        beginLaunchAtLoginUpdate(enabled)
    }

    /// Reconciles changes made directly in System Settings while the app remains running.
    public func refreshLaunchAtLoginStatus() {
        guard !isUpdatingLaunchAtLogin,
              let statusProvider = loginService as? any LaunchAtLoginStatusProviding else { return }
        applyLaunchAtLoginStatus(statusProvider.status)
    }

    /// Requests Notification Center authorization only when the user explicitly enables the
    /// toggle. Turning the feature off is immediate and does not alter the system-level grant.
    public func setNotificationsEnabled(_ enabled: Bool) {
        guard !isUpdatingNotifications else { return }
        if !enabled {
            applyNotifications(enabled: false, message: nil)
            return
        }

        isUpdatingNotifications = true
        notificationsMessage = nil
        let notificationAuthorization = self.notificationAuthorization
        Task { [weak self] in
            let state = await notificationAuthorization.authorizationState()
            guard let self else { return }
            switch state {
            case .authorized:
                self.applyNotifications(enabled: true, message: nil)
            case .denied:
                self.applyNotifications(
                    enabled: false,
                    message: "Allow notifications for ntfsmac in System Settings."
                )
            case .unavailable:
                self.applyNotifications(
                    enabled: false,
                    message: "Notifications are unavailable for this app bundle."
                )
            case .notDetermined:
                do {
                    let granted = try await notificationAuthorization.requestAuthorization()
                    self.applyNotifications(
                        enabled: granted,
                        message: granted ? nil : "Notification permission was not granted."
                    )
                } catch {
                    // macOS can commit the user's Allow choice before the async request callback
                    // returns an error (observed on the packaged menu-bar app). Read the system
                    // truth once more before treating that callback as a denial; never persist an
                    // opt-in unless Notification Center itself now reports authorization.
                    let recoveredState = await notificationAuthorization.authorizationState()
                    if recoveredState == .authorized {
                        self.applyNotifications(enabled: true, message: nil)
                    } else {
                        self.applyNotifications(
                            enabled: false,
                            message: "Could not enable notifications: \(error.localizedDescription)"
                        )
                    }
                }
            }
        }
    }

    /// Reconciles a previously enabled preference with a permission changed in System Settings.
    /// An existing authorization never turns an opt-out back on.
    public func refreshNotificationStatus() {
        guard notificationsEnabled, !isUpdatingNotifications else { return }
        isUpdatingNotifications = true
        let notificationAuthorization = self.notificationAuthorization
        Task { [weak self] in
            let state = await notificationAuthorization.authorizationState()
            guard let self else { return }
            switch state {
            case .authorized:
                self.applyNotifications(enabled: true, message: nil)
            case .denied:
                self.applyNotifications(
                    enabled: false,
                    message: "Allow notifications for ntfsmac in System Settings."
                )
            case .notDetermined:
                self.applyNotifications(enabled: false, message: nil)
            case .unavailable:
                self.applyNotifications(
                    enabled: false,
                    message: "Notifications are unavailable for this app bundle."
                )
            }
        }
    }

    private func applyNotifications(enabled: Bool, message: String?) {
        notificationsEnabled = enabled
        notificationsMessage = message
        isUpdatingNotifications = false
        defaults.set(enabled, forKey: Keys.notificationsEnabled)
    }

    private func beginLaunchAtLoginUpdate(_ enabled: Bool) {
        guard !isUpdatingLaunchAtLogin else {
            setPublishedLaunchAtLogin(confirmedLaunchAtLogin)
            return
        }
        guard enabled != confirmedLaunchAtLogin else {
            setPublishedLaunchAtLogin(confirmedLaunchAtLogin)
            return
        }

        if enabled,
           let statusProvider = loginService as? any LaunchAtLoginStatusProviding,
           statusProvider.status == .requiresApproval {
            applyLaunchAtLoginStatus(.requiresApproval)
            return
        }

        setPublishedLaunchAtLogin(enabled)
        launchAtLoginMessage = nil
        isUpdatingLaunchAtLogin = true

        let loginService = self.loginService
        let confirmedBeforeUpdate = confirmedLaunchAtLogin
        Task { [weak self] in
            // `register`/`unregister` are blocking IPC calls. Keep them off the main actor and
            // Swift's cooperative executor, then reconcile the framework's actual status.
            let result = await Task.detached(priority: .userInitiated) {
                do {
                    try loginService.setEnabled(enabled)
                    return LaunchAtLoginUpdateResult.success(
                        Self.registrationStatus(for: loginService, fallbackEnabled: enabled)
                    )
                } catch {
                    return LaunchAtLoginUpdateResult.failure(
                        message: error.localizedDescription,
                        status: Self.registrationStatus(
                            for: loginService,
                            fallbackEnabled: confirmedBeforeUpdate
                        )
                    )
                }
            }.value

            guard let self else { return }
            switch result {
            case .success(let status):
                self.applyLaunchAtLoginStatus(status)
            case .failure(let message, let status):
                self.applyLaunchAtLoginStatus(status, failureMessage: message)
            }
        }
    }

    private func applyLaunchAtLoginStatus(
        _ status: LaunchAtLoginRegistrationStatus,
        failureMessage: String? = nil
    ) {
        let enabled = status == .enabled
        confirmedLaunchAtLogin = enabled
        setPublishedLaunchAtLogin(enabled)
        launchAtLoginMessage = failureMessage.map { "Could not update Launch at login: \($0)" }
            ?? Self.message(for: status)
        isUpdatingLaunchAtLogin = false
        defaults.set(enabled, forKey: Keys.launchAtLogin)
    }

    private func setPublishedLaunchAtLogin(_ enabled: Bool) {
        isApplyingLaunchAtLoginStatus = true
        launchAtLogin = enabled
        isApplyingLaunchAtLoginStatus = false
    }

    private nonisolated static func registrationStatus(
        for service: any LaunchAtLoginService,
        fallbackEnabled: Bool
    ) -> LaunchAtLoginRegistrationStatus {
        if let statusProvider = service as? any LaunchAtLoginStatusProviding {
            return statusProvider.status
        }
        return fallbackEnabled ? .enabled : .disabled
    }

    private nonisolated static func message(
        for status: LaunchAtLoginRegistrationStatus
    ) -> String? {
        switch status {
        case .disabled, .enabled:
            return nil
        case .requiresApproval:
            return "Allow ntfsmac in System Settings > General > Login Items."
        case .unavailable:
            return "Launch at login is unavailable for this app bundle."
        }
    }

    /// GUI-PLAN.md "Settings page" table's literal Default column.
    public enum Defaults {
        public static let launchAtLogin = false
        public static let notificationsEnabled = false
    }

    private enum Keys {
        static let launchAtLogin = "com.khr898.ntfsmac.settings.launchAtLogin"
        static let notificationsEnabled = "com.khr898.ntfsmac.settings.notificationsEnabled"
    }
}
