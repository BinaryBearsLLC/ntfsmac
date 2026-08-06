import AppKit
import SwiftUI

public struct StatusIconStyle: Equatable {
    public let color: Color
    public let isIdle: Bool
    public let isPulsing: Bool
}

/// GUI-PLAN.md "Menu-bar icon states" mapping. Idle retains `.ntfsIdleGray` as its semantic
/// fallback, while `StatusIconView` presents that state as a native template image so macOS can
/// choose the contrasting menu-bar tint. Every active/error state keeps its exact saturated
/// project colour in both appearances.
public enum StatusIcon {
    public static func style(for state: MountState) -> StatusIconStyle {
        switch state {
        case .idle:
            return StatusIconStyle(color: .ntfsIdleGray, isIdle: true, isPulsing: false)
        case .mounting:
            return StatusIconStyle(color: .ntfsBlue, isIdle: false, isPulsing: true)
        case .mountedReadWrite:
            return StatusIconStyle(color: .ntfsGreen, isIdle: false, isPulsing: false)
        case .mountedReadOnly:
            // Deliberate, healthy read-only — same green as a successful read-write mount
            // (this is a config choice, not a warning); GUI-PLAN.md's icon table predates
            // this case and only documents the dirty-journal yellow, not this one.
            return StatusIconStyle(color: .ntfsGreen, isIdle: false, isPulsing: false)
        case .mountedReadOnlyDirty:
            return StatusIconStyle(color: .ntfsYellow, isIdle: false, isPulsing: false)
        case .mountedUnknown:
            return StatusIconStyle(color: .ntfsYellow, isIdle: false, isPulsing: false)
        case .error:
            return StatusIconStyle(color: .ntfsRed, isIdle: false, isPulsing: false)
        }
    }
}

/// Menu-bar label view. Uses the same SF Symbol (`externaldrive.fill`) as the rest of the app's
/// drive icons (`DriveHeaderGlyph`/`DriveRowGlyph`, `gui/Style/Icons.swift`) — explicit product
/// decision to match the app's standard icon rather than keep a one-off custom glyph here.
/// The idle glyph is an AppKit template image, matching native menu-bar apps: macOS supplies the
/// correct contrasting tint for the current menu-bar background. Non-idle states keep the
/// GUI-PLAN status colours and are pre-rendered because `MenuBarExtra` does not reliably apply a
/// SwiftUI foreground style to its real `NSStatusItem`. Pulsing uses opacity rather than the
/// macOS 14-only `.symbolEffect`, preserving the macOS 13 deployment floor.
public struct StatusIconView: View {
    let state: MountState
    @State private var isDim = false

    public init(state: MountState) {
        self.state = state
    }

    public var body: some View {
        let style = StatusIcon.style(for: state)
        Image(nsImage: Self.renderedGlyph(for: style))
            .opacity(style.isPulsing && isDim ? 0.4 : 1.0)
            .onAppear {
                guard style.isPulsing else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
    }

    static func renderedGlyph(for style: StatusIconStyle) -> NSImage {
        if style.isIdle {
            return templateGlyph()
        }

        let renderer = ImageRenderer(content:
            Image(systemName: "externaldrive.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(style.color)
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: 15, height: 12))
    }

    private static func templateGlyph() -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let symbol = NSImage(
            systemSymbolName: "externaldrive.fill",
            accessibilityDescription: "ntfsmac"
        )?.withSymbolConfiguration(configuration)
        let image = (symbol?.copy() as? NSImage) ?? NSImage(size: NSSize(width: 15, height: 12))
        image.isTemplate = true
        return image
    }
}
