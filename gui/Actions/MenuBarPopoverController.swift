import AppKit
import SwiftUI
import os.log

private let menuBarPopoverLog = Logger(
    subsystem: "com.binarybears.ntfsmac",
    category: "MenuBarPopover"
)

/// Fork-only URL event used by the CLI to reveal the existing menu-bar surface. The request has
/// no operational authority: it can only show the same popover a local click would show.
public enum OpenGUIRequest {
    public static let scheme = "binarybears-ntfsmac"
    public static let host = "opengui"
    public static let notificationName = "com.binarybears.ntfsmac.open-gui"

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

/// `NSPopover.isShown` can remain true after AppKit has ordered out a transient popover window
/// (for example after Escape or an outside click). Treating that stale flag as visible makes the
/// next physical status-item click close an already invisible popover instead of reopening it.
enum PopoverVisibility {
    static func isVisible(isShown: Bool, windowIsVisible: Bool) -> Bool {
        isShown && windowIsVisible
    }
}

@MainActor
enum PopoverWindowInteractivity {
    static func restore(_ window: NSWindow) {
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.makeKey()
    }
}

/// Thin AppKit shell around the existing SwiftUI popover content. SwiftUI's `MenuBarExtra`
/// exposes insertion but no supported presentation binding, so it cannot satisfy a robust CLI
/// "open" request. This controller changes only the shell: `PopoverContentView` remains the one
/// visual and behavioral source of truth.
@MainActor
public final class MenuBarPopoverController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popoverContentViewController: NSViewController
    private var popover: NSPopover
    private var pulseTimer: Timer?
    private var pendingShowTask: Task<Void, Never>?
    private var displayedState: MountState = .idle
    private var hasPresentedPopover = false

    private static let showRetryCount = 40
    private static let showRetryDelay = Duration.milliseconds(50)

    public init<Content: View>(content: Content, initialState: MountState = .idle) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.preferredContentSize]
        popoverContentViewController = hostingController
        popover = NSPopover()
        super.init()

        configurePopover(popover)

        configureStatusItemButton()
        updateStatus(state: initialState, helperNeedsAttention: false)
    }

    public var isShown: Bool { isPopoverVisible }

    private var isPopoverVisible: Bool {
        PopoverVisibility.isVisible(
            isShown: popover.isShown,
            windowIsVisible: popover.contentViewController?.view.window?.isVisible == true
        )
    }

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
        menuBarPopoverLog.notice(
            "Status-item action received: visible=\(self.isPopoverVisible, privacy: .public)"
        )
        isPopoverVisible ? closePopover() : showPopover()
    }

    public func showPopover() {
        pendingShowTask?.cancel()
        pendingShowTask = nil
        menuBarPopoverLog.notice(
            "Reveal requested: visible=\(self.isPopoverVisible, privacy: .public) appKitShown=\(self.popover.isShown, privacy: .public) windowVisible=\(self.popover.contentViewController?.view.window?.isVisible == true, privacy: .public)"
        )
        guard !isPopoverVisible else { return }
        if hasPresentedPopover {
            // On macOS 26.6.2 AppKit can visibly reorder the same transient NSPopover window while
            // leaving it unable to receive physical mouse-down/up events. AXPress still works,
            // which hid the defect during automation. Keep the long-lived SwiftUI controller and
            // its state, but give each reopen a fresh AppKit popover window.
            rebuildPopover()
            menuBarPopoverLog.notice("Rebuilt the transient popover window before reopening")
        }

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
            menuBarPopoverLog.error("Popover reveal exhausted the bounded anchor retries")
        }
    }

    public func closePopover() {
        pendingShowTask?.cancel()
        pendingShowTask = nil
        popover.performClose(nil)
    }

    public func popoverDidClose(_ notification: Notification) {
        // The Control Center-hosted proxy can drop the target/action when a transient popover
        // consumes the status-item mouse-down to dismiss itself. Reapply the action to the same
        // bounded AppKit button so the very next physical click reopens it.
        configureStatusItemButton()
        menuBarPopoverLog.notice("Restored the status-item action after transient close")
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
        if let popoverWindow = popover.contentViewController?.view.window {
            // AppKit can keep the reused transient window in its ordered-out, mouse-ignoring
            // state after Escape or an outside click. The window is visibly ordered in again by
            // `show`, but physical HID clicks then pass through it while AXPress still works —
            // exactly the misleading "automation works, mouse does nothing" failure mode.
            PopoverWindowInteractivity.restore(popoverWindow)
        }
        menuBarPopoverLog.notice(
            "Popover show attempted: appKitShown=\(self.popover.isShown, privacy: .public) windowVisible=\(self.popover.contentViewController?.view.window?.isVisible == true, privacy: .public) mouseIgnored=\(self.popover.contentViewController?.view.window?.ignoresMouseEvents == true, privacy: .public)"
        )
        if popover.isShown {
            hasPresentedPopover = true
        }
        return popover.isShown
    }

    private func configurePopover(_ popover: NSPopover) {
        popover.contentViewController = popoverContentViewController
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    private func configureStatusItemButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        // macOS 26's Control Center-hosted status-item proxy does not reliably forward the
        // default mouse-up action for this LSUIElement app. Dispatch on the physical mouse-down,
        // matching native menu-bar controls and avoiding an AX-only icon.
        button.sendAction(on: [.leftMouseDown])
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel("ntfsmac")
    }

    private func rebuildPopover() {
        let retiredPopover = popover
        retiredPopover.close()
        retiredPopover.contentViewController = nil

        let replacement = NSPopover()
        configurePopover(replacement)
        popover = replacement
        hasPresentedPopover = false
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
