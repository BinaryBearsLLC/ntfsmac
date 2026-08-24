import Foundation
import Testing
@testable import NtfsmacGUI

@Test func settingsUpdatePresentationCoversEveryStateWithoutTextRow() {
    let release = PublishedRelease(
        version: SemanticVersion(tag: "3.2.0")!,
        pageURL: URL(string: "https://github.com/BinaryBearsLLC/ntfsmac/releases/tag/v3.2.0")!
    )

    #expect(SettingsUpdatePresentation.resolve(.idle).accessibilityLabel == "Check for updates")
    #expect(SettingsUpdatePresentation.resolve(.checking).isChecking)
    #expect(SettingsUpdatePresentation.resolve(.upToDate).symbolName == "checkmark.circle.fill")
    #expect(SettingsUpdatePresentation.resolve(.updateAvailable(release)).usesAccent)
    #expect(SettingsUpdatePresentation.resolve(.failed("Offline")).help == "Offline")
}

@Test func helperRepairPresentationSurfacesApprovalRecoveryInsteadOfHidingIt() {
    let recovery = "Turn ntfsmac off and back on in Login Items."
    let approval = HelperRepairPresentation.resolve(
        .requiresApproval(recovery),
        variant: .modern
    )

    #expect(approval.subtitle == recovery)
    #expect(approval.primaryButtonLabel == "Refresh")
    #expect(approval.showsApprovalButton)

    let failure = HelperRepairPresentation.resolve(
        .failed("Registration failed."),
        variant: .modern
    )
    #expect(failure.subtitle == "Repair failed: Registration failed.")
    #expect(!failure.showsApprovalButton)

    let legacy = HelperRepairPresentation.resolve(.installed, variant: .legacy)
    #expect(legacy.subtitle.contains("Legacy"))
}
