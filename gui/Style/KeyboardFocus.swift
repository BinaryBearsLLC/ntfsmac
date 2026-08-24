import AppKit
import SwiftUI

public enum KeyboardFocusTrigger {
    public static func shouldShow(
        isFocused: Bool,
        eventType: NSEvent.EventType,
        keyCode: UInt16 = 0
    ) -> Bool {
        isFocused && eventType == .keyDown && keyCode == 48 // Tab / Shift-Tab
    }
}

private struct NtfsmacKeyboardFocusModifier: ViewModifier {
    @FocusState private var isFocused: Bool
    @State private var isKeyboardFocused = false
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                // Observe the control's existing focus node. Do not add `.focusable(true)`: that
                // creates a second SwiftUI focus/event layer which can consume physical mouse
                // down/up delivery inside an AppKit transient popover.
                .focused($isFocused)
                .focusEffectDisabled()
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1)
                        .opacity(isKeyboardFocused ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .onChange(of: isFocused) { _, focused in
                    let event = NSApp.currentEvent
                    let eventType = event?.type ?? .applicationDefined
                    // AppKit raises NSInternalInconsistencyException when `keyCode` is read from
                    // a non-key event. Focus changes may be delivered while the current event is
                    // a mouse, application-defined, or nil event, so inspect the type first.
                    let keyCode: UInt16 = eventType == .keyDown ? (event?.keyCode ?? 0) : 0
                    isKeyboardFocused = KeyboardFocusTrigger.shouldShow(
                        isFocused: focused,
                        eventType: eventType,
                        keyCode: keyCode
                    )
                }
        } else {
            // macOS 13 has no public focus-effect suppression API. Preserve the native control
            // unchanged rather than wrapping it in a second focus or event-monitor layer.
            content
        }
    }
}

public extension View {
    /// Suppresses SwiftUI's thick external blue halo and replaces it, during deliberate keyboard
    /// traversal only, with a stable one-point in-bounds outline.
    func ntfsmacKeyboardFocus(cornerRadius: CGFloat = 8) -> some View {
        modifier(NtfsmacKeyboardFocusModifier(cornerRadius: cornerRadius))
    }
}
