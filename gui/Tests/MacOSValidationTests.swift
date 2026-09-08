import Foundation
import Testing
@testable import NtfsmacGUI

@Test func validationRequiresExactProductBuildArchitectureAndOS() {
    let manifest = "# Evidence-backed combinations\n3.1.3 31301 arm64 26.6.2\n"
    #expect(MacOSValidationPolicy.isValidated(release: "3.1.3", build: "31301", architecture: "arm64", os: "26.6.2", manifest: manifest))
    for os in ["14.6.1", "15.0.0", "26.6.3", "27.0.0", "unknown", "26.6.2\n"] {
        #expect(!MacOSValidationPolicy.isValidated(release: "3.1.3", build: "31301", architecture: "arm64", os: os, manifest: manifest))
    }
    #expect(!MacOSValidationPolicy.isValidated(release: "3.1.3", build: "31302", architecture: "arm64", os: "26.6.2", manifest: manifest))
    #expect(!MacOSValidationPolicy.isValidated(release: "3.1.3", build: "31301", architecture: "x86_64", os: "26.6.2", manifest: manifest))
    #expect(!MacOSValidationPolicy.isValidated(release: "3.1.3", build: "31301", architecture: "arm64", os: "26.6.2", manifest: ""))
}

@Test func noticeAcknowledgementIsIndependentOfAppAndOSUpdatesAndUsesTheForkTracker() {
    #expect(MacOSValidationPolicy.acknowledgementKey == "ntfsmac.unvalidated-macos.noticeAcknowledged")
    #expect(MacOSValidationPolicy.issueURL.absoluteString == "https://github.com/BinaryBearsLLC/ntfsmac/issues/new/choose")
}

@Test func noticeOnlyAppearsBeforeFirstAcknowledgementOnAnUnvalidatedOS() throws {
    let suite = "ntfsmac.validation-tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(!MacOSValidationPolicy.shouldPresent(isValidated: true, defaults: defaults))
    #expect(MacOSValidationPolicy.shouldPresent(isValidated: false, defaults: defaults))
    defaults.set(true, forKey: MacOSValidationPolicy.acknowledgementKey)
    let reopenedDefaults = try #require(UserDefaults(suiteName: suite))
    #expect(!MacOSValidationPolicy.shouldPresent(isValidated: false, defaults: reopenedDefaults))
    #expect(!MacOSValidationPolicy.shouldPresent(isValidated: true, defaults: reopenedDefaults))
}
