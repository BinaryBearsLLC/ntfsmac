import AppKit
import Testing
@testable import NtfsmacGUI

@Test func onlyTabEnablesKeyboardFocusVisibility() {
    #expect(KeyboardFocusTrigger.shouldShow(isFocused: true, eventType: .keyDown, keyCode: 48))
    #expect(!KeyboardFocusTrigger.shouldShow(isFocused: true, eventType: .keyDown, keyCode: 36))
}

@Test func pointerActivationClearsKeyboardFocusVisibility() {
    #expect(!KeyboardFocusTrigger.shouldShow(isFocused: true, eventType: .leftMouseDown))
    #expect(!KeyboardFocusTrigger.shouldShow(isFocused: true, eventType: .rightMouseDown))
}

@Test func unfocusedControlsNeverDrawAKeyboardOutline() {
    #expect(!KeyboardFocusTrigger.shouldShow(isFocused: false, eventType: .keyDown, keyCode: 48))
    #expect(!KeyboardFocusTrigger.shouldShow(isFocused: false, eventType: .applicationDefined))
}
