import Foundation
import Testing
@testable import NtfsmacGUI

@Test func openGUIRequestAcceptsOnlyTheExactForkURL() {
    #expect(OpenGUIRequest.matches(URL(string: "binarybears-ntfsmac://opengui")!))
    #expect(OpenGUIRequest.matches(URL(string: "binarybears-ntfsmac://opengui/")!))
    #expect(!OpenGUIRequest.matches(URL(string: "binarybears-ntfsmac://settings")!))
    #expect(!OpenGUIRequest.matches(URL(string: "https://opengui")!))
    #expect(!OpenGUIRequest.matches(URL(string: "binarybears-ntfsmac://opengui/extra")!))
}
