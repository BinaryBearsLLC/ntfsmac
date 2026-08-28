import Testing
import HelperShared
@testable import NtfsmacGUI

@Suite struct FDAPromptCopyTests {
    @Test func explainsThePackagedServiceNameInFriendlyTerms() {
        #expect(FDAPromptCopy.instructions.contains("ntfsmac Helper"))
        #expect(FDAPromptCopy.instructions.contains(FDAPromptCopy.helperServiceName))
        #expect(FDAPromptCopy.helperServiceName == helperMachServiceName)
        #expect(FDAPromptCopy.instructions.contains("Full Disk Access"))
    }

    @Test func driveDiscoveryFailureUsesSafeActionableCopy() {
        let rawError = "open /Users/private/.config/containers/registries.d: permission denied"

        #expect(DriveDiscoveryFailureCopy.isVisible(for: rawError))
        #expect(!DriveDiscoveryFailureCopy.isVisible(for: nil))
        #expect(DriveDiscoveryFailureCopy.title == "Unable to check connected drives")
        #expect(DriveDiscoveryFailureCopy.message.contains("Try again"))
        #expect(DriveDiscoveryFailureCopy.message.contains("Settings"))
        #expect(!DriveDiscoveryFailureCopy.message.contains(rawError))
        #expect(!DriveDiscoveryFailureCopy.message.contains("/Users/"))
    }

    @Test func noDriveFallbackDoesNotClaimSetupIsIncomplete() {
        #expect(NoDriveAccessCopy.title == "No drives found")
        #expect(NoDriveAccessCopy.message.contains("verify access before mounting"))
        #expect(!NoDriveAccessCopy.message.lowercased().contains("finish setup"))
    }
}
