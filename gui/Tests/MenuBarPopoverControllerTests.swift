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

@Test func popoverAnchorWaitsForRealMenuBarGeometry() {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let buttonBounds = CGRect(x: 0, y: 0, width: 24, height: 24)
    let menuBarAnchor = CGRect(x: 1680, y: 1048, width: 24, height: 24)

    #expect(PopoverAnchorReadiness.isReady(
        buttonBounds: buttonBounds,
        anchorFrameOnScreen: menuBarAnchor,
        screenFrame: screen
    ))
    #expect(!PopoverAnchorReadiness.isReady(
        buttonBounds: .zero,
        anchorFrameOnScreen: menuBarAnchor,
        screenFrame: screen
    ))
    #expect(!PopoverAnchorReadiness.isReady(
        buttonBounds: buttonBounds,
        anchorFrameOnScreen: nil,
        screenFrame: screen
    ))
    #expect(!PopoverAnchorReadiness.isReady(
        buttonBounds: buttonBounds,
        anchorFrameOnScreen: menuBarAnchor,
        screenFrame: nil
    ))
}

@Test func popoverAnchorRejectsTheColdLaunchLowerLeftFallback() {
    let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
    let buttonBounds = CGRect(x: 0, y: 0, width: 24, height: 24)
    let lowerLeftFallback = CGRect(x: -1920, y: 0, width: 24, height: 24)
    let menuBarAnchor = CGRect(x: -240, y: 1048, width: 24, height: 24)

    #expect(!PopoverAnchorReadiness.isReady(
        buttonBounds: buttonBounds,
        anchorFrameOnScreen: lowerLeftFallback,
        screenFrame: screen
    ))
    #expect(PopoverAnchorReadiness.isReady(
        buttonBounds: buttonBounds,
        anchorFrameOnScreen: menuBarAnchor,
        screenFrame: screen
    ))
}
