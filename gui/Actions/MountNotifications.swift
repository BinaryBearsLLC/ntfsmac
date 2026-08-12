import Foundation
import UserNotifications

public enum NotificationAuthorizationState: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case unavailable
}

public protocol NotificationAuthorizationManaging: Sendable {
    func authorizationState() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
}

public struct RealNotificationAuthorizationManager: NotificationAuthorizationManaging {
    public init() {}

    public func authorizationState() async -> NotificationAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .unavailable
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
}

public enum MountNotificationAction: String, Equatable, Sendable {
    case mount = "Mount"
    case unmount = "Unmount"
}

public enum MountNotificationEvent: Equatable, Sendable {
    case mounted(volumeName: String, readOnly: Bool)
    case unmounted(volumeName: String)
    case failed(action: MountNotificationAction, volumeName: String?)
    case ejectAll(succeeded: Int, total: Int)
}

public struct MountNotificationPayload: Equatable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public enum MountNotificationCopy {
    public static func payload(for event: MountNotificationEvent) -> MountNotificationPayload {
        switch event {
        case .mounted(let volumeName, let readOnly):
            return MountNotificationPayload(
                title: "Drive mounted",
                body: "\(volumeName) is available \(readOnly ? "read-only" : "read/write")."
            )
        case .unmounted(let volumeName):
            return MountNotificationPayload(
                title: "Drive unmounted",
                body: "\(volumeName) can be disconnected safely."
            )
        case .failed(let action, let volumeName):
            let subject = volumeName.map { "\($0) needs attention." } ?? "A drive needs attention."
            return MountNotificationPayload(
                title: "\(action.rawValue) failed",
                body: "\(subject) Open ntfsmac for details."
            )
        case .ejectAll(let succeeded, let total):
            let failed = max(0, total - succeeded)
            return MountNotificationPayload(
                title: failed == 0 ? "All drives unmounted" : "Eject All needs attention",
                body: failed == 0
                    ? "\(succeeded) drive(s) can be disconnected safely."
                    : "\(succeeded) of \(total) drive(s) unmounted. Open ntfsmac for per-drive results."
            )
        }
    }
}

@MainActor
public protocol LocalNotificationScheduling {
    func schedule(_ payload: MountNotificationPayload)
}

@MainActor
public struct RealLocalNotificationScheduler: LocalNotificationScheduling {
    public init() {}

    public func schedule(_ payload: MountNotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        content.threadIdentifier = "com.khr898.ntfsmac.mount-events"
        let request = UNNotificationRequest(
            identifier: "ntfsmac-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
public protocol MountEventNotifying {
    func post(_ event: MountNotificationEvent)
}

@MainActor
public struct NullMountEventNotifier: MountEventNotifying {
    public init() {}
    public func post(_ event: MountNotificationEvent) {}
}

/// Local notifications are opt-in. The controller supplies only concise user-facing copy; raw
/// helper output and privacy-sensitive paths never enter Notification Center.
@MainActor
public final class MountEventNotifier: MountEventNotifying {
    private let isEnabled: () -> Bool
    private let scheduler: any LocalNotificationScheduling

    public init(
        isEnabled: @escaping () -> Bool,
        scheduler: any LocalNotificationScheduling = RealLocalNotificationScheduler()
    ) {
        self.isEnabled = isEnabled
        self.scheduler = scheduler
    }

    public func post(_ event: MountNotificationEvent) {
        guard isEnabled() else { return }
        scheduler.schedule(MountNotificationCopy.payload(for: event))
    }
}
