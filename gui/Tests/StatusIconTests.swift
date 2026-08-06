import SwiftUI
import Testing
@testable import NtfsmacGUI

// GUI-PLAN.md "Menu-bar icon states": system-adaptive=idle, blue(pulsing)=mounting,
// green=rw, yellow=ro-dirty, red=error. The pure style mapping retains `.ntfsIdleGray` as a
// fallback; the rendered idle glyph is a template so AppKit chooses its real menu-bar tint.

@Test func idleIsGrayAndNotPulsing() {
    let style = StatusIcon.style(for: .idle)
    #expect(style.color == .ntfsIdleGray)
    #expect(!style.isPulsing)
}

@Test func mountingIsBlueAndPulsing() {
    let style = StatusIcon.style(for: .mounting)
    #expect(style.color == .ntfsBlue)
    #expect(style.isPulsing)
}

@Test func mountedReadWriteIsGreenAndNotPulsing() {
    let style = StatusIcon.style(for: .mountedReadWrite)
    #expect(style.color == .ntfsGreen)
    #expect(!style.isPulsing)
}

@Test func mountedReadOnlyByRequestIsGreenAndNotPulsing() {
    let style = StatusIcon.style(for: .mountedReadOnly)
    #expect(style.color == .ntfsGreen)
    #expect(!style.isPulsing)
}

@Test func mountedReadOnlyDirtyIsYellowAndNotPulsing() {
    let style = StatusIcon.style(for: .mountedReadOnlyDirty)
    #expect(style.color == .ntfsYellow)
    #expect(!style.isPulsing)
}

@Test func mountedUnknownIsYellowAndNotPulsing() {
    let style = StatusIcon.style(for: .mountedUnknown)
    #expect(style.color == .ntfsYellow)
    #expect(!style.isPulsing)
}

@Test func errorIsRedAndNotPulsing() {
    let style = StatusIcon.style(for: .error)
    #expect(style.color == .ntfsRed)
    #expect(!style.isPulsing)
}

@MainActor
@Test func idleGlyphUsesTheSystemMenuBarTint() {
    let image = StatusIconView.renderedGlyph(for: StatusIcon.style(for: .idle))

    #expect(image.isTemplate)
    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
}

@MainActor
@Test func colouredStatusGlyphIsNotConvertedToATemplate() {
    let image = StatusIconView.renderedGlyph(for: StatusIcon.style(for: .error))

    #expect(!image.isTemplate)
}
