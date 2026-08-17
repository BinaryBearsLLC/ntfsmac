import Foundation

enum NtfsmacPreferenceKeys {
    static let launchAtLogin = "com.binarybears.ntfsmac.settings.launchAtLogin"
    static let notificationsEnabled = "com.binarybears.ntfsmac.settings.notificationsEnabled"
    static let legacyMigrationCompleted = "com.binarybears.ntfsmac.migration.khr898.completed"
    static let pendingLaunchAtLoginRestore = "com.binarybears.ntfsmac.migration.launchAtLogin.pending"
}

public struct LegacyPreferenceMigrationResult: Equatable, Sendable {
    public let migratedNotifications: Bool
    public let shouldRestoreLaunchAtLogin: Bool
}

/// One-way, allow-listed migration from the pre-v3 bundle domain. Runtime state, helper state,
/// permissions, paths, diagnostics, and any unknown keys are deliberately ignored.
public enum LegacyPreferenceMigrator {
    public static let legacyDomain = "com.khr898.ntfsmac"
    static let legacyLaunchAtLoginKey = "com.khr898.ntfsmac.settings.launchAtLogin"
    static let legacyNotificationsKey = "com.khr898.ntfsmac.settings.notificationsEnabled"

    @discardableResult
    public static func migrate(
        into defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacyDomain)
    ) -> LegacyPreferenceMigrationResult {
        if defaults.bool(forKey: NtfsmacPreferenceKeys.legacyMigrationCompleted) {
            return .init(
                migratedNotifications: false,
                shouldRestoreLaunchAtLogin: defaults.bool(
                    forKey: NtfsmacPreferenceKeys.pendingLaunchAtLoginRestore
                )
            )
        }

        var migratedNotifications = false
        if defaults.object(forKey: NtfsmacPreferenceKeys.notificationsEnabled) == nil,
           let legacyNotifications = legacyDefaults?.object(forKey: legacyNotificationsKey) as? Bool {
            defaults.set(legacyNotifications, forKey: NtfsmacPreferenceKeys.notificationsEnabled)
            migratedNotifications = true
        }

        let restoreLaunchAtLogin = legacyDefaults?.object(forKey: legacyLaunchAtLoginKey) as? Bool == true
        if restoreLaunchAtLogin {
            defaults.set(true, forKey: NtfsmacPreferenceKeys.pendingLaunchAtLoginRestore)
        }
        defaults.set(true, forKey: NtfsmacPreferenceKeys.legacyMigrationCompleted)

        return .init(
            migratedNotifications: migratedNotifications,
            shouldRestoreLaunchAtLogin: restoreLaunchAtLogin
        )
    }
}
