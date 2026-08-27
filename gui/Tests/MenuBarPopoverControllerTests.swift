import AppKit
import Foundation
import Testing
@testable import NtfsmacGUI

@Test func openGUIRequestAcceptsOnlyTheExactForkURL() {
    #expect(OpenGUIRequest.notificationName == "com.binarybears.ntfsmac.open-gui")
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

@Test func popoverVisibilityRejectsAnOrderedOutTransientWindow() {
    #expect(PopoverVisibility.isVisible(isShown: true, windowIsVisible: true))
    #expect(!PopoverVisibility.isVisible(isShown: true, windowIsVisible: false))
    #expect(!PopoverVisibility.isVisible(isShown: false, windowIsVisible: true))
    #expect(!PopoverVisibility.isVisible(isShown: false, windowIsVisible: false))
}

@Test func pollingCadenceIsResponsiveOnlyWhileThePopoverIsVisible() {
    let background = PopoverPollingCadence.resolve(isPopoverVisible: false)
    let interactive = PopoverPollingCadence.resolve(isPopoverVisible: true)

    #expect(background.driveScanInterval == .seconds(60))
    #expect(background.mountReconcileInterval == .seconds(30))
    #expect(interactive.driveScanInterval == .seconds(15))
    #expect(interactive.mountReconcileInterval == .seconds(5))
}

@MainActor
@Test func popoverWindowInteractivityRestoresPhysicalMouseDelivery() {
    let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 200, height: 120),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.ignoresMouseEvents = true
    window.acceptsMouseMovedEvents = false

    PopoverWindowInteractivity.restore(window)

    #expect(!window.ignoresMouseEvents)
    #expect(window.acceptsMouseMovedEvents)
}
