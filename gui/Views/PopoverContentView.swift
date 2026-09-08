import SwiftUI
import AppKit
import HelperShared

/// Assembles GUI-PLAN.md's "Popover — idle" / "Popover — mounted" / "Read-only (dirty) state" /
/// "Error state" tables into the single popover `NtfsmacApp.swift` presents; every subview used
/// here is unmodified, already-reviewed production code — this file only composes them per the
/// state machine `AppState.state` already defines.
/// Header status dot — pulses only during the transient mounting state and remains static for
/// idle, mounted, warning, and error states. It uses an opacity fade rather than the macOS 14-only
/// `.symbolEffect`, preserving the macOS 13.0 deployment floor.
/// No-drives empty-state copy, extracted as testable constants (same pattern as
/// `DirtyBanner.bannerCopy`) — `PopoverStateRenderTests` renders to an `ImageRenderer` image
/// which can't be grepped for text, so the strings live here for `EmptyStateCopyTests`.
enum EmptyStateCopy {
    static let title = "No NTFS / ext drives connected"
    static let subtitle = "Connect an NTFS or ext drive to\nget started"
}

enum PreparingStateCopy {
    static let title = "Preparing ntfsmac…"
    static let subtitle = "Setting up the disk runtime for its first check."
}

enum HeaderDriveSummary {
    static func idleSubtitle(
        hasCompletedInitialScan: Bool,
        driveDiscoveryFailed: Bool,
        visibleDriveCount: Int
    ) -> String {
        if !hasCompletedInitialScan { return "Preparing ntfsmac…" }
        if driveDiscoveryFailed { return "Drive check failed" }
        return visibleDriveCount == 0
            ? "No drives found"
            : "\(visibleDriveCount) drive(s) detected"
    }
}

/// "Other available devices" section copy — the unmounted-drives list shown below the mounted
/// list when one or more drives are already mounted. Says "devices" (not "drives") and only
/// renders once something is primary: before mounting, the detected drives are just "the drives",
/// not "other", so the labeled section is suppressed in the idle state. Mirrors
/// `EmptyStateCopy`'s testable-constant pattern.
enum OtherAvailableCopy {
    static let label = "Other available devices"
}

/// Pure gating decision for the "Other available devices" section, extracted from the view so the
/// idle-vs-mounted behavior is testable without rendering an image. The section (header + small
/// Refresh button) renders whenever a drive is mounted — it must stay visible even when no
/// unmounted drive is currently listed, so the Refresh button stays available to re-scan for
/// newly connected drives without unmounting first. The per-drive rows render only when
/// `rowsRender(availableCount:)` is true (at least one unmounted drive detected).
enum OtherAvailableSection {
    /// Header + Refresh button render iff a drive is mounted (never in the idle state — there the
    /// detected drives are the primary list, not "other").
    static func shouldRender(isMounted: Bool) -> Bool { isMounted }

    /// Per-drive rows render only when at least one unmounted drive is actually available.
    static func rowsRender(availableCount: Int) -> Bool { availableCount > 0 }
}

public enum QuitRequestDecision: Equatable, Sendable {
    case quitNow
    case showConfirmation
    case unmountAndQuit
}

public enum QuitRequestPolicy {
    public static func resolve(
        hasMountedDrives: Bool,
        commandPressed: Bool,
        remembersSafeAction: Bool
    ) -> QuitRequestDecision {
        guard hasMountedDrives else { return .quitNow }
        if commandPressed { return .showConfirmation }
        return remembersSafeAction ? .unmountAndQuit : .showConfirmation
    }
}

/// The only persisted Quit choice is the safe one. Command-click clears this key; there is no
/// Settings row or alternate persisted "Quit Anyway" state.
public struct QuitPreferenceStore {
    private static let safeActionKey = "com.binarybears.ntfsmac.quit.unmountWithoutAsking"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var remembersSafeAction: Bool { defaults.bool(forKey: Self.safeActionKey) }
    public func rememberSafeAction() { defaults.set(true, forKey: Self.safeActionKey) }
    public func clear() { defaults.removeObject(forKey: Self.safeActionKey) }
}

public struct QuitConfirmationPresentation: Equatable, Sendable {
    public private(set) var isVisible = false
    public private(set) var remembersSafeAction = false
    public private(set) var isWorking = false
    public private(set) var errorMessage: String?

    public init() {}

    public mutating func show(errorMessage: String? = nil) {
        isVisible = true
        isWorking = false
        remembersSafeAction = false
        self.errorMessage = errorMessage
    }

    public mutating func setRememberSafeAction(_ value: Bool) {
        guard !isWorking else { return }
        remembersSafeAction = value
    }

    public mutating func beginSafeShutdown() -> Bool {
        guard isVisible, !isWorking else { return false }
        isWorking = true
        errorMessage = nil
        return true
    }

    public mutating func fail(_ message: String) {
        isVisible = true
        isWorking = false
        errorMessage = message
    }

    public mutating func cancel() {
        guard !isWorking else { return }
        isVisible = false
        remembersSafeAction = false
        errorMessage = nil
    }
}

private struct HeaderStatusDot: View {
    let color: Color
    let isPulsing: Bool

    var body: some View {
        Group {
            if isPulsing {
                PulsingHeaderStatusDot(color: color)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Keep the repeating transaction inside a conditional child. When mounting finishes SwiftUI
/// removes this child entirely, which tears down its display-link animation instead of leaving a
/// dormant `repeatForever` transaction attached to the long-lived popover view graph.
private struct PulsingHeaderStatusDot: View {
    let color: Color
    @State private var isDim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .opacity(isDim ? 0.45 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    isDim = true
                }
            }
    }
}

/// Diagnostics describe the set of active storage sessions, not just the aggregate icon state.
/// Including mounted IDs invalidates a report when one of several same-mode drives is added or
/// removed while the aggregate `MountState` remains unchanged.
private struct DiagnoseStorageContext: Equatable {
    let mountState: MountState
    let mountedDriveIDs: Set<String>
}

public struct PopoverContentView: View {
    @ObservedObject public var appState: AppState
    @ObservedObject public var driveScanner: DriveScanner
    @ObservedObject public var mountController: MountController
    @ObservedObject public var diagnoseRunner: DiagnoseRunner
    @ObservedObject public var securityStatusReader: SecurityStatusReader
    @ObservedObject public var helperInstaller: HelperInstaller
    @ObservedObject public var helperUninstaller: HelperUninstaller
    @ObservedObject public var cliInstallChecker: CLIInstallChecker
    @ObservedObject public var cliAutoStager: CLIAutoStager
    @ObservedObject public var fullDiskAccessController: FullDiskAccessController
    @ObservedObject public var settings: Settings
    @ObservedObject public var updateChecker: UpdateChecker
    @StateObject private var navigation: PopoverNavigation
    @StateObject private var verifiedCopyController: VerifiedCopyController
    public let finderOpener: FinderOpener
    public let helperClient: HelperClient

    @Environment(\.colorScheme) private var colorScheme
    @State private var diagnosePresentation = DiagnosePanelPresentation()
    @State private var diagnoseReportContext: DiagnoseStorageContext?
    @State private var quitPresentation = QuitConfirmationPresentation()
    @State private var finderErrorMessage: String?
    private let quitPreferenceStore = QuitPreferenceStore()

    public init(
        appState: AppState,
        driveScanner: DriveScanner,
        mountController: MountController,
        diagnoseRunner: DiagnoseRunner,
        securityStatusReader: SecurityStatusReader = SecurityStatusReader(),
        helperInstaller: HelperInstaller,
        helperUninstaller: HelperUninstaller,
        cliInstallChecker: CLIInstallChecker,
        cliAutoStager: CLIAutoStager,
        fullDiskAccessController: FullDiskAccessController = FullDiskAccessController(),
        settings: Settings,
        updateChecker: UpdateChecker = UpdateChecker(),
        finderOpener: FinderOpener,
        helperClient: HelperClient,
        navigation: PopoverNavigation
    ) {
        self.appState = appState
        self.driveScanner = driveScanner
        self.mountController = mountController
        self.diagnoseRunner = diagnoseRunner
        self.securityStatusReader = securityStatusReader
        self.helperInstaller = helperInstaller
        self.helperUninstaller = helperUninstaller
        self.cliInstallChecker = cliInstallChecker
        self.cliAutoStager = cliAutoStager
        self.fullDiskAccessController = fullDiskAccessController
        self.settings = settings
        self.updateChecker = updateChecker
        self.finderOpener = finderOpener
        self.helperClient = helperClient
        _navigation = StateObject(wrappedValue: navigation)
        _verifiedCopyController = StateObject(wrappedValue: VerifiedCopyController())
    }

    /// Source-compatible initializer matching the original public surface. The production app
    /// supplies its long-lived uninstaller/navigation objects through the designated initializer.
    public init(
        appState: AppState,
        driveScanner: DriveScanner,
        mountController: MountController,
        diagnoseRunner: DiagnoseRunner,
        securityStatusReader: SecurityStatusReader = SecurityStatusReader(),
        helperInstaller: HelperInstaller,
        cliInstallChecker: CLIInstallChecker,
        cliAutoStager: CLIAutoStager,
        settings: Settings,
        updateChecker: UpdateChecker = UpdateChecker(),
        finderOpener: FinderOpener,
        helperClient: HelperClient
    ) {
        self.init(
            appState: appState,
            driveScanner: driveScanner,
            mountController: mountController,
            diagnoseRunner: diagnoseRunner,
            securityStatusReader: securityStatusReader,
            helperInstaller: helperInstaller,
            helperUninstaller: HelperUninstaller(),
            cliInstallChecker: cliInstallChecker,
            cliAutoStager: cliAutoStager,
            fullDiskAccessController: FullDiskAccessController(),
            settings: settings,
            updateChecker: updateChecker,
            finderOpener: finderOpener,
            helperClient: helperClient,
            navigation: PopoverNavigation()
        )
    }

    public var body: some View {
        Group {
            if navigation.page == .settings {
                PreferencesView(
                    settings: settings,
                    installer: helperInstaller,
                    uninstaller: helperUninstaller,
                    onBack: navigation.showMain,
                    updateChecker: updateChecker
                )
            // Helper install is a self-contained ServiceManagement/XPC flow that doesn't touch the CLI
            // tree at all — gating it behind `cliInstallChecker.isInstalled` would block the
            // "Install Helper…" button while the CLI is still being staged. `CLIAutoStager`
            // stages the CLI (bundled into the .app by `build/package-app.sh`, no tap/Homebrew
            // needed) the moment the helper finishes installing, so helper state is checked
            // first; CLI-missing is the brief, self-clearing window between "helper just
            // installed" and "CLIAutoStager finished running install.sh through it."
            } else if helperInstaller.state != .installed {
                FirstRunView(
                    installer: helperInstaller,
                    diagnoseRunner: diagnoseRunner,
                    onOpenSettings: navigation.showSettings,
                    onQuit: { requestQuit(commandPressed: false) }
                )
            } else if !cliInstallChecker.isInstalled || cliAutoStager.lastFailureReason != nil {
                CLIMissingView(
                    checker: cliInstallChecker,
                    stager: cliAutoStager,
                    onOpenSettings: navigation.showSettings,
                    onQuit: { requestQuit(commandPressed: false) }
                )
            } else if driveDiscoveryFailed {
                VStack(spacing: 0) {
                    DriveDiscoveryFailureView(
                        isRetrying: driveScanner.isRefreshing,
                        onRetry: {
                            Task { await refreshAll() }
                        },
                        onOpenSettings: navigation.showSettings,
                        onQuit: { requestQuit(commandPressed: false) },
                        footer: AnyView(footer)
                    )
                    if diagnosePresentation.isVisible {
                        diagnosticPanel.padding(12)
                    }
                }
                .frame(width: 320)
                .fixedSize(horizontal: false, vertical: true)
            } else if FullDiskAccessPresentationPolicy.shouldPresentSetup(
                state: fullDiskAccessController.state,
                deviceID: driveScanner.drives.first?.identifier
            ) {
                FullDiskAccessSetupView(
                    controller: fullDiskAccessController,
                    deviceID: driveScanner.drives.first?.identifier,
                    onOpenSettings: navigation.showSettings,
                    onQuit: { requestQuit(commandPressed: false) }
                )
            } else {
                mainContent
            }
        }
        .onChange(of: mountController.errorMessage) { newValue in
            if newValue == "FDA_REQUIRED" {
                fullDiskAccessController.reset()
                mountController.clearError()
            }
        }
        .onChange(of: diagnoseStorageContext) { newContext in
            diagnoseReportContext = nil
            diagnoseRunner.invalidateForStorageStateChange()
            guard DiagnoseRefreshPolicy.shouldRunAutomatically(
                panelIsVisible: diagnosePresentation.isVisible,
                mountState: newContext.mountState
            ) else { return }
            Task { @MainActor in
                guard diagnoseStorageContext == newContext, diagnosePresentation.isVisible else { return }
                await diagnoseRunner.run()
                diagnoseReportContext = diagnoseStorageContext == newContext ? newContext : nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ntfsmacOpenSettings)) { _ in
            if !verifiedCopyController.isActive {
                navigation.showSettings()
            }
        }
        .task(id: cliAutoStager.hasVerifiedCurrentCLI) {
            await refreshAll()
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            // A requested read-only mount is healthy and needs no warning. Any unexpected cause is
            // shown explicitly without offering a forced read/write retry.
            if let reason = DirtyBanner.preferredReason(
                among: mountController.mountedDrives.compactMap(\.readOnlyReason)
            ) {
                DirtyBannerView(reason: reason)
            }

            Divider()

            // Mounted drives — one DriveRow per drive, each with its own Unmount pill. Scales to
            // the number of drives anylinuxfs is exporting (one microVM per mount, mixed NTFS+ext).
            if !mountController.mountedDrives.isEmpty {
                if mountController.mountedDrives.count > 1 {
                    HStack(spacing: 6) {
                        Text("MOUNTED")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.1)
                            .foregroundStyle(.secondary.opacity(0.7))
                        Spacer()
                        Button {
                            Task { await mountController.ejectAll() }
                        } label: {
                            HStack(spacing: 5) {
                                if mountController.isEjectingAll {
                                    ProgressView().controlSize(.small)
                                } else {
                                    EjectGlyph()
                                }
                                Text("Eject All")
                            }
                        }
                        .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                        .ntfsmacKeyboardFocus()
                        .disabled(driveActionsDisabled)
                        .help(TooltipCopy.text(for: .ejectAll))
                    }
                }
                ForEach(mountController.mountedDrives) { entry in
                    DriveRow(
                        drive: entry.drive,
                        isMounted: true,
                        hasReadOnlyWarning: entry.hasReadOnlyWarning,
                        actionsDisabled: driveActionsDisabled,
                        onOpenInFinder: entry.isVerified ? {
                            let opened = finderOpener.open(
                                entry.drive,
                                state: finderState(for: entry),
                                mountPoint: entry.mountPoint
                            )
                            finderErrorMessage = opened
                                ? nil
                                : "Could not open this mounted drive in Finder"
                        } : nil,
                        onVerifiedCopy: verifiedCopyAction(for: entry),
                        onUnmount: { Task { await mountController.unmount(driveID: entry.id) } }
                    )
                }
            }

            if verifiedCopyController.isVisible {
                VerifiedCopyStatusView(controller: verifiedCopyController)
            }

            if let report = mountController.lastEjectAllReport {
                EjectAllReportView(report: report) {
                    mountController.dismissEjectAllReport()
                }
            }

            // Before anything is mounted: the detected drives are the primary list, not "other" —
            // nothing is primary yet, so no "Other available" section header. Each row is a
            // mountable DriveRow, with a Refresh pill (icon + "Refresh" text, same shape as the
            // no-drives empty-state Refresh) above the list so the user can re-scan before mounting.
            if mountController.mountedDrives.isEmpty && !visibleDrives.isEmpty {
                HStack(spacing: 6) {
                    Spacer()
                    Button {
                        Task { await refreshAll() }
                    } label: {
                        HStack(spacing: 6) {
                            RefreshGlyph()
                            Text("Refresh")
                        }
                    }
                    .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                    .ntfsmacKeyboardFocus()
                    .accessibilityLabel("Refresh drives")
                }
                ForEach(visibleDrives) { drive in
                    DriveRow(
                        drive: drive,
                        isMounted: false,
                        actionsDisabled: driveActionsDisabled,
                        onMount: { mountDrive(drive) },
                        onMountExperimental: ntfs3Action(for: drive)
                    )
                }
            }

            // Mounted: the "Other available devices" header + small Refresh button render below the
            // mounted list — and STAY rendered even when no unmounted
            // drive is currently listed, so the Refresh button stays available to re-scan for newly
            // connected drives. The per-drive rows render only when an unmounted drive is detected.
            if OtherAvailableSection.shouldRender(isMounted: !mountController.mountedDrives.isEmpty) {
                Divider()
                HStack(spacing: 6) {
                    Text(OtherAvailableCopy.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await refreshAll() }
                    } label: {
                        RefreshGlyph()
                    }
                    .buttonStyle(.glassIcon(colorScheme: colorScheme))
                    .ntfsmacKeyboardFocus()
                    .disabled(driveActionsDisabled)
                    .accessibilityLabel("Refresh drives")
                }
                if OtherAvailableSection.rowsRender(availableCount: otherAvailableDrives.count) {
                    ForEach(otherAvailableDrives) { drive in
                        DriveRow(
                            drive: drive,
                            isMounted: false,
                            actionsDisabled: driveActionsDisabled,
                            onMount: { mountDrive(drive) },
                            onMountExperimental: ntfs3Action(for: drive)
                        )
                    }
                }
            }

            if mountController.mountedDrives.isEmpty && visibleDrives.isEmpty {
                emptyState
            }

            if quitPresentation.isVisible {
                quitConfirmation
            }

            if let errorMessage = mountController.errorMessage, errorMessage != "FDA_REQUIRED" {
                Text(errorMessage).font(.caption).foregroundStyle(Color.ntfsRed)
            }

            if let finderErrorMessage {
                Text(finderErrorMessage).font(.caption).foregroundStyle(Color.ntfsRed)
            }

            if let warning = mountController.reconciliationWarning {
                Text(warning).font(.caption).foregroundStyle(Color.ntfsYellow)
            }

            if diagnosePresentation.isVisible {
                diagnosticPanel
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        // ponytail: MenuBarExtra(.window) resizes its NSPanel over 2+ layout passes whenever
        // any @Published state here changes — without an explicit vertical fixedSize, the
        // panel briefly converges through a larger intermediate size before settling, which
        // reads as "grow then shrink" on every button tap, not just ones that change content.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `ui/prototype.html`'s popover header (icon-box + title/subtitle + status dot) appears in
    /// every state shown in the comp (mounted lines 113-129, idle 462-477, dirty 555-570) — was
    /// previously just a bare "ntfsmac" headline with no icon, subtitle, or dot at all.
    private var header: some View {
        let style = StatusIcon.style(for: appState.state)
        return HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(style.color.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style.color.opacity(0.28)))
                DriveHeaderGlyph(color: style.color)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("ntfsmac").font(.system(size: 13, weight: .semibold))
                Text(headerSubtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HeaderStatusDot(color: style.color, isPulsing: style.isPulsing)
                .help(TooltipCopy.status(for: appState.state))
        }
    }

    /// Drives the scanner sees that aren't currently mounted — the "Other available" section.
    private var otherAvailableDrives: [Drive] {
        visibleDrives.filter { !mountController.mountedDriveIDs.contains($0.id) }
    }

    private var visibleDrives: [Drive] {
        driveScanner.drives.filter { !mountController.physicallyMissingDriveIDs.contains($0.id) }
    }

    private var driveDiscoveryFailed: Bool {
        DriveDiscoveryFailureCopy.isVisible(
            for: driveScanner.lastError,
            detectedDriveCount: visibleDrives.count
        )
    }

    private var driveActionsDisabled: Bool {
        mountController.hasStorageOperationInFlight || verifiedCopyController.isActive || quitPresentation.isWorking
    }

    /// Mount an unmounted drive r/w at its default mount point. Shared by the idle primary list
    /// and the mounted "Other available devices" section — both offer the same per-row Mount action.
    private func mountDrive(_ drive: Drive, driver: FsDriver? = nil) {
        guard !verifiedCopyController.isActive else { return }
        Task { await mountController.mount(drive, driver: driver, mountPoint: nil, readOnly: false) }
    }

    private func ntfs3Action(for drive: Drive) -> (() -> Void)? {
        guard NTFS3PreflightCopy.isAvailable(for: drive.fsType) else { return nil }
        return { mountDrive(drive, driver: .ntfs3) }
    }

    private func finderState(for entry: MountedDrive) -> MountState {
        if !entry.isVerified { return .mountedUnknown }
        if entry.requiresWindowsRepair { return .mountedReadOnlyDirty }
        if entry.hasReadOnlyWarning { return .mountedReadOnlyUnexpected }
        return entry.isReadOnly ? .mountedReadOnly : .mountedReadWrite
    }

    private var diagnoseStorageContext: DiagnoseStorageContext {
        DiagnoseStorageContext(
            mountState: appState.state,
            mountedDriveIDs: mountController.mountedDriveIDs
        )
    }

    private func verifiedCopyAction(for entry: MountedDrive) -> (() -> Void)? {
        guard VerifiedCopyAvailability.isAvailable(
            isVerified: entry.isVerified,
            isReadOnly: entry.isReadOnly,
            mountPoint: entry.mountPoint
        ), let mountPoint = entry.mountPoint
        else {
            return nil
        }
        return {
            do {
                guard let selection = try VerifiedCopyPicker.choose(
                    onMountPoint: mountPoint,
                    rejectSymbolicLinks: entry.fsDriver == FsDriver.ntfs3.rawValue
                ) else {
                    return
                }
                let volumeName = entry.drive.label.isEmpty ? entry.drive.identifier : entry.drive.label
                verifiedCopyController.start(selection, volumeName: volumeName)
            } catch {
                let volumeName = entry.drive.label.isEmpty ? entry.drive.identifier : entry.drive.label
                verifiedCopyController.showSelectionError(error, volumeName: volumeName)
            }
        }
    }

    private func refreshAll() async {
        guard BackendActivationPolicy.canScan(
            helperState: helperInstaller.state,
            cliInstalled: cliInstallChecker.isInstalled,
            cliVerifiedForCurrentHelper: cliAutoStager.hasVerifiedCurrentCLI
        ) else { return }
        await driveScanner.refresh()
        await mountController.reconcile(knownDrives: driveScanner.drives)
    }

    private var headerSubtitle: String {
        switch appState.state {
        case .idle:
            HeaderDriveSummary.idleSubtitle(
                hasCompletedInitialScan: driveScanner.hasCompletedInitialScan,
                driveDiscoveryFailed: driveDiscoveryFailed,
                visibleDriveCount: visibleDrives.count
            )
        case .mounting: "Mounting…"
        case .mountedReadWrite: "Mounted read/write"
        case .mountedReadOnly: "Mounted read-only"
        case .mountedReadOnlyUnexpected: "Mounted read-only — cause unknown"
        case .mountedReadOnlyDirty: "Mounted read-only — Windows needs attention"
        case .mountedUnknown: "Mount state needs verification"
        case .error: "Error"
        }
    }

    /// `ui/prototype.html`'s idle empty-state block (comp lines 481-499) — icon + copy + Refresh
    /// pill. Previously missing entirely: `DriveListView` used to render its own plain-text
    /// fallback, but that was dropped when the liquid-glass `DriveRow` rewrite landed, leaving
    /// idle-with-nothing-detected showing nothing above the footer.
    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.secondary.opacity(0.12)))
                if !driveScanner.hasCompletedInitialScan {
                    ProgressView().controlSize(.small)
                } else {
                    DriveGlyphEmpty(color: .secondary)
                }
            }
            .frame(width: 44, height: 44)

            VStack(spacing: 4) {
                Text(driveScanner.hasCompletedInitialScan ? EmptyStateCopy.title : PreparingStateCopy.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(driveScanner.hasCompletedInitialScan ? EmptyStateCopy.subtitle : PreparingStateCopy.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            if driveScanner.hasCompletedInitialScan {
                Button {
                    Task { await refreshAll() }
                } label: {
                    HStack(spacing: 6) {
                        RefreshGlyph()
                        Text("Refresh")
                    }
                }
                .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                .ntfsmacKeyboardFocus()
                .accessibilityLabel("Refresh drives")
                .help(TooltipCopy.text(for: .refresh))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// `ui/prototype.html`'s footer (comp lines 230-238/504-513/617-626): exactly
    /// `[gear][Diagnose (flex:1)][Quit]` in every non-error state — no Refresh slot here at all
    /// (`DriveScanner` already performs visibility-aware periodic scans; the on-demand Refresh
    /// pill lives in `emptyState` only, per GUI-PLAN.md's "Popover — idle" table). Previously this
    /// had a 4th SF-Symbol
    /// refresh button in the wrong position, plus SF Symbols instead of the comp's literal glyphs.
    private var diagnosticPanel: some View {
        DiagnosePanel(
            runner: diagnoseRunner,
            mountState: appState.state,
            detectedDriveCount: driveDiscoveryFailed ? nil : visibleDrives.count,
            fullDiskAccessGranted: FullDiskAccessPresentationPolicy.diagnosticGrantEvidence(
                for: fullDiskAccessController.state
            ),
            contextIsCurrent: diagnoseReportContext == diagnoseStorageContext,
            onHide: { diagnosePresentation.hide() }
        )
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Button {
                navigation.showSettings()
            } label: {
                SettingsGearGlyph(color: .secondary)
            }
            .buttonStyle(.glassIcon(colorScheme: colorScheme))
            .ntfsmacKeyboardFocus()
            .disabled(verifiedCopyController.isActive)
            .accessibilityLabel("Open Settings")
            .help(TooltipCopy.text(for: .settings))

            Button {
                let mode = DiagnoseActionMode.resolve(
                    commandPressed: NSEvent.modifierFlags.contains(.command)
                )
                diagnosePresentation.show()
                Task {
                    diagnoseReportContext = nil
                    let diagnosedContext = diagnoseStorageContext
                    switch mode {
                    case .summary:
                        await diagnoseRunner.run()
                        diagnoseReportContext = diagnoseStorageContext == diagnosedContext
                            ? diagnosedContext
                            : nil
                    case .developerJSONExport:
                        if let document = await diagnoseRunner.runForDeveloperExport(driveDiscoveryFailed: driveDiscoveryFailed) {
                            diagnoseReportContext = diagnoseStorageContext == diagnosedContext
                                ? diagnosedContext
                                : nil
                            DeveloperDiagnoseSavePanel.present(document: document)
                        } else {
                            diagnoseReportContext = diagnoseStorageContext == diagnosedContext
                                ? diagnosedContext
                                : nil
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    DiagnoseGlyph()
                    Text("Diagnose")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
            }
            .buttonStyle(.glassFooter(colorScheme: colorScheme))
            .ntfsmacKeyboardFocus()
            .disabled(diagnoseRunner.isRunning || verifiedCopyController.isActive)
            .accessibilityLabel("Diagnose")
            .help(TooltipCopy.text(for: .diagnose))

            Button {
                requestQuit(commandPressed: NSEvent.modifierFlags.contains(.command))
            } label: {
                Text("Quit").frame(height: 28)
            }
            .buttonStyle(.glassFooter(colorScheme: colorScheme))
            .ntfsmacKeyboardFocus()
            .disabled(driveActionsDisabled)
            .accessibilityLabel("Quit ntfsmac")
            .help(TooltipCopy.text(for: .quit))
        }
    }

    private func requestQuit(commandPressed: Bool) {
        guard !verifiedCopyController.isActive, !mountController.hasStorageOperationInFlight else { return }
        if commandPressed {
            quitPreferenceStore.clear()
        }
        switch QuitRequestPolicy.resolve(
            hasMountedDrives: !mountController.mountedDrives.isEmpty,
            commandPressed: commandPressed,
            remembersSafeAction: quitPreferenceStore.remembersSafeAction
        ) {
        case .quitNow:
            // With no observed mount there is no filesystem service to preserve or dismantle.
            // Invalidating the lazy XPC connection keeps this path genuinely immediate even if a
            // stale ServiceManagement registration is currently wedged.
            helperClient.invalidateConnection()
            NSApp.terminate(nil)
        case .showConfirmation:
            diagnosePresentation.hide()
            quitPresentation.show()
        case .unmountAndQuit:
            quitPresentation.show()
            beginSafeQuit()
        }
    }

    private func beginSafeQuit() {
        let rememberAfterSuccess = quitPresentation.remembersSafeAction
        guard quitPresentation.beginSafeShutdown() else { return }
        Task {
            await mountController.ejectAll()
            guard mountController.mountedDrives.isEmpty else {
                quitPresentation.fail(
                    "One or more drives could not be unmounted. They remain available and ntfsmac stayed open."
                )
                return
            }

            do {
                let teardown = try await helperClient.teardown()
                guard teardown.exitCode == 0 else {
                    quitPresentation.fail(
                        "The drives were unmounted, but cleanup could not be confirmed. ntfsmac stayed open."
                    )
                    return
                }
                let stopped = try await helperClient.exitHelper()
                guard stopped.exitCode == 0 else {
                    quitPresentation.fail(
                        "The drives were unmounted, but ntfsmac could not finish shutting down safely."
                    )
                    return
                }
                if rememberAfterSuccess {
                    quitPreferenceStore.rememberSafeAction()
                }
                NSApp.terminate(nil)
            } catch {
                quitPresentation.fail(
                    "The drives were unmounted, but ntfsmac could not confirm final cleanup. Try Quit again."
                )
            }
        }
    }

    private var quitConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "externaldrive.badge.questionmark")
                    .foregroundStyle(Color.ntfsYellow)
                Text("Quit with mounted drives?")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            Text("Unmount and Quit is the safe choice. Quit Anyway leaves the mounted filesystems and their required services running.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(
                "Don't show again (always Unmount and Quit)",
                isOn: Binding(
                    get: { quitPresentation.remembersSafeAction },
                    set: { quitPresentation.setRememberSafeAction($0) }
                )
            )
            .toggleStyle(.checkbox)
            .font(.system(size: 10.5))
            .ntfsmacKeyboardFocus(cornerRadius: 5)
            .disabled(quitPresentation.isWorking)

            if let errorMessage = quitPresentation.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.ntfsRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if quitPresentation.isWorking {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Unmounting every drive safely…")
                        .font(.system(size: 10.5, weight: .medium))
                }
            } else {
                HStack(spacing: 6) {
                    Button("Cancel") { quitPresentation.cancel() }
                        .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                        .ntfsmacKeyboardFocus()
                    Spacer(minLength: 0)
                    Button("Quit Anyway") {
                        helperClient.invalidateConnection()
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.glassWarning())
                    .ntfsmacKeyboardFocus()
                    Button("Unmount and Quit") { beginSafeQuit() }
                        .buttonStyle(.glassPrimary())
                        .ntfsmacKeyboardFocus()
                }
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm quitting ntfsmac with mounted drives")
    }
}

private struct EjectAllReportView: View {
    let report: EjectAllReport
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(report.allSucceeded ? "All drives unmounted" : "Eject All results")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .ntfsmacKeyboardFocus()
                .accessibilityLabel("Dismiss Eject All results")
            }

            ForEach(report.results) { result in
                HStack(spacing: 6) {
                    Text(result.volumeName)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: result.status == .unmounted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.status == .unmounted ? Color.ntfsGreen : Color.ntfsYellow)
                    Text(result.status.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(result.status == .unmounted ? Color.secondary : Color.ntfsYellow)
                }
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Eject All per-drive results")
    }
}
