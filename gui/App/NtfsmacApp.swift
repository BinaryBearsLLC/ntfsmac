import AppKit
import Combine
import CoreFoundation
import CoreServices
import HelperShared
import NtfsmacGUI
import SwiftUI
import os.log

private let lifecycleLog = Logger(subsystem: "com.binarybears.ntfsmac", category: "Lifecycle")

/// Owns the menu-bar shell and the same long-lived model objects previously retained by
/// `MenuBarExtra`. AppKit is used only because SwiftUI does not expose a supported way to present
/// a `MenuBarExtra` from the CLI; the popover body remains the existing `PopoverContentView`.
@MainActor
final class NtfsmacApplicationDelegate: NSObject, NSApplicationDelegate {
    private let foregroundNotificationPresenter = ForegroundNotificationPresenter()
    private var singleInstanceGuard: SingleInstanceGuard?
    private var popoverController: MenuBarPopoverController?
    private var driveScanner: DriveScanner?
    private var mountController: MountController?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingOpenRequest = false
    private var openGUINotificationInstalled = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        foregroundNotificationPresenter.install()
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

    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard singleInstanceGuard != nil else { return }

        let appState = AppState()
        LegacyPreferenceMigrator.migrate()
        let settings = Settings()
        settings.restoreMigratedLaunchAtLoginIntentIfNeeded()
        let updateChecker = UpdateChecker()
        let eventNotifier = MountEventNotifier(isEnabled: { settings.notificationsEnabled })
        let uiDemoMode = ProcessInfo.processInfo.environment["NTFSMAC_UI_DEMO"]
        let driveScanner: DriveScanner
        let mountController: MountController
        let remountController: RemountController

        // See `DemoScaffold.swift`: inert unless NTFSMAC_UI_DEMO is explicitly set. Real installs
        // never set it, so this branch is limited to deliberate live-screen audits.
        if let demoMode = uiDemoMode {
            driveScanner = DemoScaffold.driveScanner()
            mountController = DemoScaffold.mountController(
                mode: demoMode,
                appState: appState,
                notifier: eventNotifier
            )
            remountController = DemoScaffold.remountController(
                appState: appState,
                notifier: eventNotifier
            )
        } else {
            driveScanner = DriveScanner()
            mountController = MountController(notifier: eventNotifier, appState: appState)
            remountController = RemountController(notifier: eventNotifier, appState: appState)
        }

        let helperInstaller: HelperInstaller
        if let installOutcome = ProcessInfo.processInfo.environment["NTFSMAC_INSTALL_DEMO"] {
            helperInstaller = DemoScaffold.helperInstaller(outcome: installOutcome)
        } else {
            helperInstaller = HelperInstaller()
        }

        let cliInstallChecker = CLIInstallChecker()
        let cliAutoStager = CLIAutoStager(checker: cliInstallChecker)
        let fullDiskAccessController = uiDemoMode == nil
            ? FullDiskAccessController()
            : DemoScaffold.fullDiskAccessController()
        let helperUninstaller = HelperUninstaller(onUninstallComplete: {
            helperInstaller.reset()
            fullDiskAccessController.reset()
            cliInstallChecker.check()
        })
        let navigation = PopoverNavigation()
        let helperClient = HelperClient()

        let content = PopoverContentView(
            appState: appState,
            driveScanner: driveScanner,
            mountController: mountController,
            remountController: remountController,
            diagnoseRunner: DiagnoseRunner(),
            helperInstaller: helperInstaller,
            helperUninstaller: helperUninstaller,
            cliInstallChecker: cliInstallChecker,
            cliAutoStager: cliAutoStager,
            fullDiskAccessController: fullDiskAccessController,
            settings: settings,
            updateChecker: updateChecker,
            finderOpener: FinderOpener(),
            helperClient: helperClient,
            navigation: navigation
        )
        .popoverGlassBackground()

        let applyPollingCadence: @MainActor (Bool) -> Void = { isVisible in
            let cadence = PopoverPollingCadence.resolve(isPopoverVisible: isVisible)
            driveScanner.startPolling(interval: cadence.driveScanInterval)
            mountController.startPolling(
                knownDrives: { driveScanner.drives },
                interval: cadence.mountReconcileInterval
            )
        }
        let popoverController = MenuBarPopoverController(
            content: content,
            initialState: appState.state,
            onVisibilityChange: applyPollingCadence
        )
        self.popoverController = popoverController
        self.driveScanner = driveScanner
        self.mountController = mountController

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
                    if uiDemoMode == nil && (state == .installing || state == .notChecked) {
                        cliAutoStager.reset()
                        fullDiskAccessController.reset()
                    }
                    guard state == .installed else { return }
                    await cliAutoStager.stageIfNeeded()
                }
            }
            .store(in: &cancellables)

        applyPollingCadence(false)
        Task {
            await updateChecker.checkAutomaticallyIfNeeded(
                currentVersion: ProductVersion.current().release
            )
        }

        if pendingOpenRequest {
            pendingOpenRequest = false
            DispatchQueue.main.async { [weak popoverController] in
                popoverController?.showPopover()
            }
        }

        // The CLI posts the same idempotent Darwin notification after each bounded Launch
        // Services request. Unlike a SwiftUI Settings-scene URL handler, this listener exists for
        // the complete lifetime of a no-window LSUIElement app, including warm reopen requests.
        installOpenGUINotificationHandler()
        // SwiftUI may install its own URL-event plumbing during launch. Register the direct
        // Apple-event compatibility path on the next run-loop turn so warm custom URLs keep
        // reaching this LSUIElement app even though it has no visible Settings scene.
        DispatchQueue.main.async { [weak self] in
            self?.installOpenGUIEventHandler()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        popoverController?.showPopover()
        return false
    }

    /// AppKit's documented custom-URL entry point. Using the application delegate keeps the
    /// handler owned by the same lifecycle as this LSUIElement app; a raw Apple-event handler set
    /// during `applicationWillFinishLaunching` can be replaced later by SwiftUI, leaving warm
    /// `ntfsmac opengui` requests silently unhandled.
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(handleOpenURL)
    }

    func handleOpenURL(_ url: URL) {
        guard OpenGUIRequest.matches(url) else {
            lifecycleLog.error("Ignored an invalid GUI URL request")
            return
        }
        requestPopoverPresentation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        driveScanner?.stopPolling()
        mountController?.stopPolling()
        popoverController?.invalidate()
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        if openGUINotificationInstalled {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(OpenGUIRequest.notificationName as CFString),
                nil
            )
            openGUINotificationInstalled = false
        }
    }

    private func installOpenGUINotificationHandler() {
        guard !openGUINotificationInstalled else { return }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let delegate = Unmanaged<NtfsmacApplicationDelegate>
                    .fromOpaque(observer)
                    .takeUnretainedValue()
                delegate.performSelector(
                    onMainThread: #selector(NtfsmacApplicationDelegate.handleOpenGUINotification),
                    with: nil,
                    waitUntilDone: false
                )
            },
            OpenGUIRequest.notificationName as CFString,
            nil,
            .deliverImmediately
        )
        openGUINotificationInstalled = true
    }

    @objc private func handleOpenGUINotification() {
        lifecycleLog.notice("Received local GUI reveal notification")
        requestPopoverPresentation()
    }

    private func installOpenGUIEventHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let rawURL = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: rawURL)
        else {
            lifecycleLog.error("Ignored a malformed GUI URL request")
            return
        }
        lifecycleLog.notice("Received custom URL GUI reveal request")
        handleOpenURL(url)
    }

    private func requestPopoverPresentation() {
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
