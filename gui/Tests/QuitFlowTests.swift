import Foundation
import Testing
@testable import NtfsmacGUI

private func quitDefaults() -> UserDefaults {
    let suite = "com.binarybears.ntfsmac.tests.quit.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@Test func quitIsImmediateWithoutMountedDrives() {
    #expect(QuitRequestPolicy.resolve(
        hasMountedDrives: false,
        commandPressed: false,
        remembersSafeAction: false
    ) == .quitNow)
    #expect(QuitRequestPolicy.resolve(
        hasMountedDrives: false,
        commandPressed: true,
        remembersSafeAction: true
    ) == .quitNow)
}

@Test func mountedDrivesRequireConfirmationUnlessOnlyTheSafeChoiceWasSaved() {
    #expect(QuitRequestPolicy.resolve(
        hasMountedDrives: true,
        commandPressed: false,
        remembersSafeAction: false
    ) == .showConfirmation)
    #expect(QuitRequestPolicy.resolve(
        hasMountedDrives: true,
        commandPressed: false,
        remembersSafeAction: true
    ) == .unmountAndQuit)
}

@Test func commandClickAlwaysRestoresMountedDriveConfirmation() {
    #expect(QuitRequestPolicy.resolve(
        hasMountedDrives: true,
        commandPressed: true,
        remembersSafeAction: true
    ) == .showConfirmation)
}

@Test func quitPreferencePersistsAndClearsOnlyTheSafeAction() {
    let store = QuitPreferenceStore(defaults: quitDefaults())

    #expect(!store.remembersSafeAction)
    store.rememberSafeAction()
    #expect(store.remembersSafeAction)
    store.clear()
    #expect(!store.remembersSafeAction)
}

@Test func quitConfirmationConsumesOneSafeActionAndKeepsFailureRecoverable() {
    var presentation = QuitConfirmationPresentation()
    presentation.show()
    presentation.setRememberSafeAction(true)

    let firstAttempt = presentation.beginSafeShutdown()
    let duplicateAttempt = presentation.beginSafeShutdown()
    #expect(firstAttempt)
    #expect(!duplicateAttempt)
    #expect(presentation.isWorking)

    presentation.fail("Unmount failed")
    #expect(presentation.isVisible)
    #expect(!presentation.isWorking)
    #expect(presentation.errorMessage == "Unmount failed")
}
