import Foundation
import Testing
@testable import NtfsmacGUI

private func migrationDefaults(_ prefix: String) -> UserDefaults {
    let suite = "com.binarybears.ntfsmac.tests.\(prefix).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func legacyMigrationCopiesOnlyTheTwoAllowListedPreferences() {
    let destination = migrationDefaults("destination")
    let legacy = migrationDefaults("legacy")
    legacy.set(true, forKey: LegacyPreferenceMigrator.legacyNotificationsKey)
    legacy.set(true, forKey: LegacyPreferenceMigrator.legacyLaunchAtLoginKey)
    legacy.set("private", forKey: "unrelated.path.or.runtime.state")

    let result = LegacyPreferenceMigrator.migrate(into: destination, legacyDefaults: legacy)

    #expect(result.migratedNotifications)
    #expect(result.shouldRestoreLaunchAtLogin)
    #expect(destination.bool(forKey: NtfsmacPreferenceKeys.notificationsEnabled))
    #expect(destination.bool(forKey: NtfsmacPreferenceKeys.pendingLaunchAtLoginRestore))
    #expect(destination.object(forKey: "unrelated.path.or.runtime.state") == nil)
}

@Test func legacyMigrationNeverOverwritesANewPreference() {
    let destination = migrationDefaults("destination-existing")
    let legacy = migrationDefaults("legacy-existing")
    destination.set(false, forKey: NtfsmacPreferenceKeys.notificationsEnabled)
    legacy.set(true, forKey: LegacyPreferenceMigrator.legacyNotificationsKey)

    LegacyPreferenceMigrator.migrate(into: destination, legacyDefaults: legacy)

    #expect(!destination.bool(forKey: NtfsmacPreferenceKeys.notificationsEnabled))
}

@Test func legacyMigrationIsIdempotent() {
    let destination = migrationDefaults("destination-repeat")
    let legacy = migrationDefaults("legacy-repeat")
    legacy.set(true, forKey: LegacyPreferenceMigrator.legacyNotificationsKey)

    let first = LegacyPreferenceMigrator.migrate(into: destination, legacyDefaults: legacy)
    legacy.set(false, forKey: LegacyPreferenceMigrator.legacyNotificationsKey)
    let second = LegacyPreferenceMigrator.migrate(into: destination, legacyDefaults: legacy)

    #expect(first.migratedNotifications)
    #expect(!second.migratedNotifications)
    #expect(destination.bool(forKey: NtfsmacPreferenceKeys.notificationsEnabled))
}
