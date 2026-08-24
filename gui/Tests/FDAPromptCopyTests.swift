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
}
