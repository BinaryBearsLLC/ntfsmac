import SwiftUI

extension Notification.Name {
    static let ntfsmacOpenSettings = Notification.Name("com.khr898.ntfsmac.open-settings")
}

/// Source-compatible adapter for callers of the former Preferences-window API. It no longer
/// creates or owns an NSWindow: `open()` requests navigation to the in-popover Settings page.
@MainActor
public enum PreferencesOpener {
    @available(*, deprecated, message: "Settings content is owned by PopoverContentView")
    public static func configure(content: @escaping () -> AnyView) {
        // Retained only for source compatibility. The popover already owns the same long-lived
        // Settings/helper instances, so retaining a second content factory would be misleading.
    }

    @available(*, deprecated, message: "Use PopoverNavigation.showSettings()")
    public static func open() {
        NotificationCenter.default.post(name: .ntfsmacOpenSettings, object: nil)
    }
}
