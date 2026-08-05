import Testing
@testable import NtfsmacGUI

@Suite struct FDAPromptCopyTests {
    @Test func explainsTheTechnicalServiceNameInFriendlyTerms() {
        #expect(FDAPromptCopy.instructions.contains("ntfsmac Helper"))
        #expect(FDAPromptCopy.instructions.contains(FDAPromptCopy.helperServiceName))
        #expect(FDAPromptCopy.instructions.contains("technical service name"))
        #expect(FDAPromptCopy.instructions.contains("generic executable icon"))
        #expect(FDAPromptCopy.instructions.contains("standalone privileged tool"))
    }
}
