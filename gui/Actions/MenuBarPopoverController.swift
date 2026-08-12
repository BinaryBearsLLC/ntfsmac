import AppKit
import SwiftUI

/// Fork-only URL event used by the CLI to reveal the existing menu-bar surface. The request has
/// no operational authority: it can only show the same popover a local click would show.
public enum OpenGUIRequest {
    public static let scheme = "binarybears-ntfsmac"
    public static let host = "opengui"

    public static func matches(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme && url.host?.lowercased() == host
            && (url.path.isEmpty || url.path == "/")
    }
}

/// A status-item popover is only safe to present after AppKit has attached the button to its
/// menu-bar window and assigned real screen coordinates. Presenting earlier makes AppKit fall
/// back to the lower-left corner of the screen during a cold `opengui` launch.
enum PopoverAnchorReadiness {
    private static let maximumMenuBarBandHeight: CGFloat = 96

    static func isReady(
        buttonBounds: CGRect,
        anchorFrameOnScreen: CGRect?,
        screenFrame: CGRect?
    ) -> Bool {
        guard buttonBounds.width > 0, buttonBounds.height > 0,
              let anchorFrameOnScreen,
              anchorFrameOnScreen.width > 0, anchorFrameOnScreen.height > 0,
              let screenFrame,
              screenFrame.width > 0, screenFrame.height > 0,
              anchorFrameOnScreen.intersects(screenFrame)
        else {
            return false
        }

        let menuBarBandHeight = min(maximumMenuBarBandHeight, screenFrame.height)
        return anchorFrameOnScreen.midY >= screenFrame.maxY - menuBarBandHeight
    }
}

/// Thin AppKit shell around the existing SwiftUI popover content. SwiftUI's `MenuBarExtra`
/// exposes insertion but no supported presentation binding, so it cannot satisfy a robust CLI
/// "open" request. This controller changes only the shell: `PopoverContentView` remains the one
/// visual and behavioral source of truth.
@MainActor
public final class MenuBarPopoverController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var pulseTimer: Timer?
    private var pendingShowTask: Task<Void, Never>?
    private var displayedState: MountState = .idle

    private static let showRetryCount = 40
    private static let showRetryDelay = Duration.milliseconds(50)

    public init<Content: View>(content: Content, initialState: MountState = .idle) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hostingController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("ntfsmac")
        }
        updateStatus(state: initialState, helperNeedsAttention: false)
    }

    public var isShown: Bool { popover.isShown }

    /// Explicit main-actor cleanup. The controller normally lives for the whole app process;
    /// keeping teardown explicit also avoids Swift 6's deliberately nonisolated `deinit`
    /// touching AppKit's non-Sendable objects.
    public func invalidate() {
        pendingShowTask?.cancel()
        pendingShowTask = nil
        pulseTimer?.invalidate()
        pulseTimer = nil
        popover.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc public func togglePopover() {
        popover.isShown ? closePopover() : showPopover()
    }

    public func showPopover() {
        pendingShowTask?.cancel()
        pendingShowTask = nil
        guard !popover.isShown else { return }

        pendingShowTask = Task { @MainActor [weak self] in
            guard let self else { return }

            for attempt in 0..<Self.showRetryCount {
                guard !Task.isCancelled else { return }
                if self.showPopoverIfAnchorIsReady() {
                    self.pendingShowTask = nil
                    return
                }
                guard attempt + 1 < Self.showRetryCount else { break }
                try? await Task.sleep(for: Self.showRetryDelay)
            }

            self.pendingShowTask = nil
        }
    }

    public func closePopover() {
        pendingShowTask?.cancel()
        pendingShowTask = nil
        popover.performClose(nil)
    }

    private func showPopoverIfAnchorIsReady() -> Bool {
        guard let button = statusItem.button,
              let window = button.window,
              let screen = window.screen
        else {
            return false
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let anchorFrameOnScreen = window.convertToScreen(buttonFrameInWindow)
        guard PopoverAnchorReadiness.isReady(
            buttonBounds: button.bounds,
            anchorFrameOnScreen: anchorFrameOnScreen,
            screenFrame: screen.frame
        ) else {
            return false
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        return popover.isShown
    }

    public func updateStatus(state: MountState, helperNeedsAttention: Bool) {
        displayedState = helperNeedsAttention ? .error : state
        guard let button = statusItem.button else { return }
        let style = StatusIcon.style(for: displayedState)
        button.image = StatusIconView.renderedGlyph(for: style)
        button.image?.accessibilityDescription = "ntfsmac"
        configurePulse(enabled: style.isPulsing)
    }

    private func configurePulse(enabled: Bool) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        statusItem.button?.alphaValue = 1
        guard enabled else { return }

        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let button = self?.statusItem.button else { return }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.35
                    button.animator().alphaValue = button.alphaValue < 0.7 ? 1 : 0.4
                }
            }
        }
    }
}
