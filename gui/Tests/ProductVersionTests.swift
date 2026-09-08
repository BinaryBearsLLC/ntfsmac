import Testing
@testable import NtfsmacGUI

@Test func productVersionIdentifiesBetaWithoutChangingNumericAppleVersion() {
    let version = ProductVersion.resolve(infoDictionary: [
        "CFBundleShortVersionString": "3.1.3",
        "CFBundleVersion": "31303",
        "NTFSMACReleaseLabel": "Beta 1",
    ])
    #expect(version.release == "3.1.3")
    #expect(version.settingsText == "Version 3.1.3 Beta 1 (31303)")
    #expect(ProductVersion.resolve(infoDictionary: [
        "CFBundleShortVersionString": "3.1.3", "NTFSMACReleaseLabel": "  "
    ]).settingsText == "Version 3.1.3")
}

@Test func productVersionFormatsReleaseAndBuildForSettings() {
    let version = ProductVersion.resolve(infoDictionary: [
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
    ])

    #expect(version == ProductVersion(release: "1.0", build: "1"))
    #expect(version.settingsText == "Version 1.0 (1)")
}

@Test func productVersionHandlesMissingOrRedundantBuildMetadata() {
    #expect(ProductVersion.resolve(infoDictionary: [:]).settingsText == "Version Unknown")
    #expect(
        ProductVersion(release: "1.0", build: "1.0").settingsText == "Version 1.0"
    )
}
