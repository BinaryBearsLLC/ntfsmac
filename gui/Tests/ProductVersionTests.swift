import Testing
@testable import NtfsmacGUI

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
