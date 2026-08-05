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
        productVersion: ProductVersion(release: "test", build: "test"),
        uninstallConfirmation: .init(isVisible: true)
    )
    let renderer = ImageRenderer(content: view)

    #expect(renderer.nsImage?.size.width == 320)
    #expect((renderer.nsImage?.size.height ?? 0) > 200)
}

@MainActor
@Test func settingsPageExposesABackControlSoTheUserIsNotTrappedOnIt() {
    // GUI-PLAN.md "Settings page": a keyboard-reachable Back action returns to the previous
    // application content. Without it, tapping the gear strands the user on Preferences.
    // ImageRenderer rasterizes to an image (no text to grep), so the structural signal is:
    // PreferencesView with `onBack` supplied renders taller than the same view with `onBack`
    // nil — the Back header (button + divider) is only emitted when onBack is present.
    let productVersion = ProductVersion(release: "test", build: "test")

    let withoutBack = PreferencesView(
        settings: Settings(defaults: UserDefaults(suiteName: "com.khr898.ntfsmac.tests.noback.\(UUID().uuidString)")!),
        installer: HelperInstaller(),
        uninstaller: HelperUninstaller(),
        onBack: nil,
        productVersion: productVersion
    )
    let withBack = PreferencesView(
        settings: Settings(defaults: UserDefaults(suiteName: "com.khr898.ntfsmac.tests.back.\(UUID().uuidString)")!),
        installer: HelperInstaller(),
        uninstaller: HelperUninstaller(),
        onBack: {},
        productVersion: productVersion
    )

    let heightWithout = ImageRenderer(content: withoutBack).nsImage?.size.height ?? 0
    let heightWith = ImageRenderer(content: withBack).nsImage?.size.height ?? 0

    #expect(heightWith > heightWithout,
            "Settings page must render a Back header when onBack is supplied — without it the user is trapped")
}
