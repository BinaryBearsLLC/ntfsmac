import SwiftUI
import Testing
@testable import NtfsmacGUI

@Test func inlineUninstallConfirmationRequiresOneVisibleExplicitConfirmation() {
    var presentation = UninstallConfirmationPresentation()
    #expect(!presentation.isVisible)
    let confirmationWhileHidden = presentation.confirm()
    #expect(!confirmationWhileHidden)

    presentation.request()
    #expect(presentation.isVisible)
    presentation.cancel()
    #expect(!presentation.isVisible)

    presentation.request()
    let firstConfirmation = presentation.confirm()
    #expect(firstConfirmation)
    #expect(!presentation.isVisible)
    let duplicateConfirmation = presentation.confirm()
    #expect(!duplicateConfirmation, "one click must never start two destructive flows")
}

@MainActor
@Test func inlineUninstallConfirmationRendersInsideTheSettingsPopover() {
    let defaults = UserDefaults(suiteName: "com.khr898.ntfsmac.tests.uninstall.\(UUID().uuidString)")!
    let view = PreferencesView(
        settings: Settings(defaults: defaults),
        installer: HelperInstaller(),
        uninstaller: HelperUninstaller(),
        onBack: {},
        uninstallConfirmation: .init(isVisible: true)
    )
    let renderer = ImageRenderer(content: view)

    #expect(renderer.nsImage?.size.width == 320)
    #expect((renderer.nsImage?.size.height ?? 0) > 200)
}
