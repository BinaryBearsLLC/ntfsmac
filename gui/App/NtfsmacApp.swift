import AppKit
import Combine
import CoreServices
import NtfsmacGUI
import SwiftUI
import os.log

private let lifecycleLog = Logger(subsystem: "com.khr898.ntfsmac", category: "Lifecycle")

/// Owns the menu-bar shell and the same long-lived model objects previously retained by
/// `MenuBarExtra`. AppKit is used only because SwiftUI does not expose a supported way to present
/// a `MenuBarExtra` from the CLI; the popover body remains the existing `PopoverContentView`.
@MainActor
final class NtfsmacApplicationDelegate: NSObject, NSApplicationDelegate {
    private var singleInstanceGuard: SingleInstanceGuard?
    private var popoverController: MenuBarPopoverController?
    private var driveScanner: DriveScanner?
    private var mountController: MountController?
    private var securityStatusReader: SecurityStatusReader?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingOpenRequest = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        do {
            singleInstanceGuard = try SingleInstanceGuard()
        } catch SingleInstanceGuardError.alreadyRunning {
            lifecycleLog.notice("A second GUI instance was blocked")
            NSApplication.shared.terminate(nil)
            return
        } catch {
            // Fail closed: two active GUI workflows are riskier than declining to launch when
            // the per-user lock cannot be acquired.
            lifecycleLog.error(
                "Unable to acquire the GUI instance lock: \(error.localizedDescription, privacy: .public)"
            )
            NSApplication.shared.terminate(nil)
            return
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstanceGuard != nil else { return }

        let appState = AppState()
        let driveScanner: DriveScanner
        let mountController: MountController
        let remountController: RemountController

        // See `DemoScaffold.swift`: inert unless NTFSMAC_UI_DEMO is explicitly set. Real installs
        // never set it, so this branch is limited to deliberate live-screen audits.
        if let demoMode = ProcessInfo.processInfo.environment["NTFSMAC_UI_DEMO"] {
            driveScanner = DemoScaffold.driveScanner()
            mountController = DemoScaffold.mountController(mode: demoMode, appState: appState)
            remountController = DemoScaffold.remountController(appState: appState)
        } else {
            driveScanner = DriveScanner()
            mountController = MountController(appState: appState)
            remountController = RemountController(appState: appState)
        }

        let helperInstaller: HelperInstaller
        if let installOutcome = ProcessInfo.processInfo.environment["NTFSMAC_INSTALL_DEMO"] {
            helperInstaller = DemoScaffold.helperInstaller(outcome: installOutcome)
        } else {
            helperInstaller = HelperInstaller()
        }

        let cliInstallChecker = CLIInstallChecker()
        let cliAutoStager = CLIAutoStager(checker: cliInstallChecker)
        let helperUninstaller = HelperUninstaller(onUninstallComplete: {
            helperInstaller.reset()
            cliInstallChecker.check()
        })
        let navigation = PopoverNavigation()
        let helperClient = HelperClient()
        let securityStatusReader = SecurityStatusReader()

        let content = PopoverContentView(
            appState: appState,
            driveScanner: driveScanner,
            mountController: mountController,
            remountController: remountController,
            diagnoseRunner: DiagnoseRunner(),
            securityStatusReader: securityStatusReader,
            helperInstaller: helperInstaller,
            helperUninstaller: helperUninstaller,
            cliInstallChecker: cliInstallChecker,
            cliAutoStager: cliAutoStager,
            settings: Settings(),
            finderOpener: FinderOpener(),
            helperClient: helperClient,
            navigation: navigation
        )
        .popoverGlassBackground()

        let popoverController = MenuBarPopoverController(content: content, initialState: appState.state)
        self.popoverController = popoverController
        self.driveScanner = driveScanner
        self.mountController = mountController
        self.securityStatusReader = securityStatusReader

        Publishers.CombineLatest(appState.$state, helperInstaller.$state)
            .sink { [weak popoverController] state, helperState in
                Task { @MainActor in
                    popoverController?.updateStatus(
                        state: state,
                        helperNeedsAttention: helperState.isDeniedOrFailed
                    )
                }
            }
            .store(in: &cancellables)

        helperInstaller.$state
            .removeDuplicates()
            .sink { state in
                Task { @MainActor in
                    if state == .installing || state == .notChecked {
                        cliAutoStager.reset()
                    }
                    guard state == .installed else { return }
                    await cliAutoStager.stageIfNeeded()
                }
            }
            .store(in: &cancellables)

        driveScanner.startPolling()
        mountController.startPolling { driveScanner.drives }
        securityStatusReader.startPolling()

        if pendingOpenRequest {
            pendingOpenRequest = false
            DispatchQueue.main.async { [weak popoverController] in
                popoverController?.showPopover()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        popoverController?.showPopover()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        driveScanner?.stopPolling()
        mountController?.stopPolling()
        securityStatusReader?.stopPolling()
        popoverController?.invalidate()
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let rawURL = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: rawURL),
              OpenGUIRequest.matches(url)
        else {
            lifecycleLog.error("Ignored an invalid GUI URL request")
            return
        }

        if let popoverController {
            popoverController.showPopover()
        } else {
            pendingOpenRequest = true
        }
    }
}

/// The application has no Dock icon and no standalone window. `Settings` is an inert scene used
/// only to satisfy SwiftUI's scene contract; real settings remain inside `PopoverContentView`.
@main
struct NtfsmacApp: App {
    @NSApplicationDelegateAdaptor(NtfsmacApplicationDelegate.self) private var applicationDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
