import SwiftUI
import HelperShared

/// MenuBarExtra uses a transient window. A native `confirmationDialog` dismisses that window as
/// its destructive button is selected, which made the uninstall action appear to vanish before
/// it reliably reached `HelperUninstaller`. Keep confirmation state in the popover itself instead.
public struct UninstallConfirmationPresentation: Equatable, Sendable {
    public private(set) var isVisible: Bool

    public init(isVisible: Bool = false) {
        self.isVisible = isVisible
    }

    public mutating func request() { isVisible = true }
    public mutating func cancel() { isVisible = false }

    /// Consumes one explicit confirmation. A stale/double action cannot start two uninstalls.
    public mutating func confirm() -> Bool {
        guard isVisible else { return false }
        isVisible = false
        return true
    }
}

public struct SettingsUpdatePresentation: Equatable, Sendable {
    public let symbolName: String
    public let accessibilityLabel: String
    public let help: String
    public let usesAccent: Bool
    public let isChecking: Bool

    public static func resolve(_ state: UpdateCheckState) -> Self {
        switch state {
        case .idle:
            .init(
                symbolName: "arrow.clockwise",
                accessibilityLabel: "Check for updates",
                help: "Check for updates",
                usesAccent: false,
                isChecking: false
            )
        case .checking:
            .init(
                symbolName: "arrow.clockwise",
                accessibilityLabel: "Checking for updates",
                help: "Checking GitHub Releases…",
                usesAccent: true,
                isChecking: true
            )
        case .upToDate:
            .init(
                symbolName: "checkmark.circle.fill",
                accessibilityLabel: "ntfsmac is up to date",
                help: "ntfsmac is up to date",
                usesAccent: false,
                isChecking: false
            )
        case .updateAvailable(let release):
            .init(
                symbolName: "arrow.down.circle.fill",
                accessibilityLabel: "Update available",
                help: "Version \(release.version) is available on GitHub",
                usesAccent: true,
                isChecking: false
            )
        case .failed(let message):
            .init(
                symbolName: "exclamationmark.triangle",
                accessibilityLabel: "Update check unavailable",
                help: message,
                usesAccent: false,
                isChecking: false
            )
        }
    }
}

public struct HelperRepairPresentation: Equatable, Sendable {
    public let subtitle: String
    public let primaryButtonLabel: String
    public let showsApprovalButton: Bool

    public static func resolve(
        _ state: HelperInstallState,
        variant: HelperDistributionVariant = .current
    ) -> Self {
        switch state {
        case .requiresApproval(let message):
            return .init(
                subtitle: message,
                primaryButtonLabel: "Refresh",
                showsApprovalButton: true
            )
        case .installing:
            return .init(
                subtitle: "Repairing app access…",
                primaryButtonLabel: "Repair…",
                showsApprovalButton: false
            )
        case .denied(let message), .failed(let message):
            return .init(
                subtitle: "Repair failed: \(message)",
                primaryButtonLabel: "Repair…",
                showsApprovalButton: false
            )
        case .notChecked, .checking, .readyToInstall, .installed:
            return .init(
                subtitle: variant == .modern
                    ? "Repair the component ntfsmac uses for drive access"
                    : "Repair the Legacy compatibility component",
                primaryButtonLabel: "Repair…",
                showsApprovalButton: false
            )
        }
    }
}

/// GUI-PLAN.md "Settings page" table, using the same controls and application-owned state as the
/// former Preferences window. "Repair app access" reuses `HelperInstaller.install()`
/// directly — the same path `3-first-run-install` built for first-run, per that unit's Do clause.
public struct PreferencesView: View {
    @ObservedObject public var settings: Settings
    @ObservedObject public var installer: HelperInstaller
    @ObservedObject public var uninstaller: HelperUninstaller
    @ObservedObject public var updateChecker: UpdateChecker
    public let onBack: (() -> Void)?
    public let productVersion: ProductVersion

    @Environment(\.colorScheme) private var colorScheme
    @State private var uninstallConfirmation: UninstallConfirmationPresentation

    public init(
        settings: Settings,
        installer: HelperInstaller,
        uninstaller: HelperUninstaller,
        onBack: (() -> Void)?,
        updateChecker: UpdateChecker = UpdateChecker()
    ) {
        self.init(
            settings: settings,
            installer: installer,
            uninstaller: uninstaller,
            onBack: onBack,
            productVersion: .current(),
            updateChecker: updateChecker,
            uninstallConfirmation: .init()
        )
    }

    public init(
        settings: Settings,
        installer: HelperInstaller,
        uninstaller: HelperUninstaller,
        onBack: (() -> Void)?,
        productVersion: ProductVersion,
        updateChecker: UpdateChecker = UpdateChecker()
    ) {
        self.init(
            settings: settings,
            installer: installer,
            uninstaller: uninstaller,
            onBack: onBack,
            productVersion: productVersion,
            updateChecker: updateChecker,
            uninstallConfirmation: .init()
        )
    }

    init(
        settings: Settings,
        installer: HelperInstaller,
        uninstaller: HelperUninstaller,
        onBack: (() -> Void)?,
        productVersion: ProductVersion,
        updateChecker: UpdateChecker = UpdateChecker(),
        uninstallConfirmation: UninstallConfirmationPresentation
    ) {
        self.settings = settings
        self.installer = installer
        self.uninstaller = uninstaller
        self.onBack = onBack
        self.productVersion = productVersion
        self.updateChecker = updateChecker
        _uninstallConfirmation = State(initialValue: uninstallConfirmation)
    }

    /// Source-compatible initializer for existing embeddings. The production app always supplies
    /// `onBack` and presents this view inside the menu-bar popover.
    public init(settings: Settings, installer: HelperInstaller, uninstaller: HelperUninstaller) {
        self.init(settings: settings, installer: installer, uninstaller: uninstaller, onBack: nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let onBack {
                ZStack {
                    VStack(spacing: 1) {
                        Text("Settings")
                            .font(.system(size: 13, weight: .semibold))
                        Text(productVersion.settingsText)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.72))
                            .accessibilityLabel("ntfsmac \(productVersion.settingsText)")
                        if HelperDistributionVariant.current == .legacy {
                            Text("Legacy")
                                .font(.system(size: 9, weight: .regular))
                                .foregroundStyle(.secondary.opacity(0.72))
                        }
                    }
                    HStack {
                        Button {
                            onBack()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                        }
                        .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                        .ntfsmacKeyboardFocus()
                        .accessibilityLabel("Back")
                        .help(TooltipCopy.text(for: .back))
                        .frame(width: 82, alignment: .leading)
                        Spacer()
                        updateButton
                            .frame(width: 82, alignment: .trailing)
                    }
                }
                Divider()
            }

            row("Launch at login", launchAtLoginSubtitle) {
                HStack(spacing: 8) {
                    if settings.isUpdatingLaunchAtLogin {
                        ProgressView().controlSize(.small)
                    }
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { settings.launchAtLogin },
                            set: { settings.setLaunchAtLogin($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .ntfsmacKeyboardFocus()
                    .disabled(settings.isUpdatingLaunchAtLogin)
                    .accessibilityLabel("Launch at login")
                }
            }

            row("Notifications", notificationsSubtitle) {
                HStack(spacing: 8) {
                    if settings.isUpdatingNotifications {
                        ProgressView().controlSize(.small)
                    }
                    Toggle(
                        "Notifications",
                        isOn: Binding(
                            get: { settings.notificationsEnabled },
                            set: { settings.setNotificationsEnabled($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .ntfsmacKeyboardFocus()
                    .disabled(settings.isUpdatingNotifications)
                    .accessibilityLabel("Mount notifications")
                }
            }

            row("Repair app access", helperRepairSubtitle) {
                HStack(spacing: 6) {
                    if installer.state == .installing {
                        ProgressView().controlSize(.small)
                    }
                    if helperRepairPresentation.showsApprovalButton {
                        Button("Approve…") {
                            installer.openApprovalSettings()
                        }
                        .ntfsmacKeyboardFocus()
                    }
                    Button(helperRepairPresentation.primaryButtonLabel) {
                        Task {
                            if helperRepairPresentation.showsApprovalButton {
                                await installer.installAfterConsent()
                            } else {
                                await installer.reinstallAfterConsent()
                            }
                        }
                    }
                    .ntfsmacKeyboardFocus()
                }
            }

            row("Uninstall ntfsmac", uninstallSubtitle) {
                HStack(spacing: 6) {
                    if uninstaller.state == .removingDependencies || uninstaller.state == .removingHelper {
                        ProgressView().controlSize(.small)
                    }
                    Button("Uninstall…", role: .destructive) {
                        uninstallConfirmation.request()
                    }
                    .ntfsmacKeyboardFocus()
                    .disabled(
                        uninstaller.state == .removingDependencies
                            || uninstaller.state == .removingHelper
                            || isUninstallComplete
                    )
                }
            }

            if uninstallConfirmation.isVisible {
                inlineUninstallConfirmation
            }

            Link("Binary Bears LLC", destination: URL(string: "https://www.binarybears.com")!)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.72))
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
                .help("Visit www.binarybears.com")
        }
        .padding(16)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            settings.refreshLaunchAtLoginStatus()
            settings.refreshNotificationStatus()
        }
    }

    private var uninstallSubtitle: String {
        switch uninstaller.state {
        case .idle:
            return "Remove the CLI, dependencies, and this helper — no leftovers"
        case .removingDependencies:
            return "Removing CLI and dependencies…"
        case .removingHelper:
            return "Removing privileged helper…"
        case .done:
            return "Uninstalled. Safe to drag ntfsmac.app to the Trash."
        case .failed(let message):
            return "Failed: \(message)"
        }
    }

    private var launchAtLoginSubtitle: String {
        settings.launchAtLoginMessage ?? "Start ntfsmac automatically on login"
    }

    private var notificationsSubtitle: String {
        settings.notificationsMessage ?? "Mount, unmount, and error results"
    }

    private var helperRepairSubtitle: String {
        helperRepairPresentation.subtitle
    }

    private var helperRepairPresentation: HelperRepairPresentation {
        HelperRepairPresentation.resolve(installer.state)
    }

    private var updateButton: some View {
        let presentation = SettingsUpdatePresentation.resolve(updateChecker.state)
        return Button {
            if case .updateAvailable = updateChecker.state {
                updateChecker.openAvailableRelease()
            } else {
                Task {
                    await updateChecker.checkManually(currentVersion: productVersion.release)
                }
            }
        } label: {
            ZStack {
                if presentation.isChecking {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: presentation.symbolName)
                        .foregroundStyle(presentation.usesAccent ? Color.ntfsBlue : Color.secondary)
                }
            }
            .frame(width: 30, height: 28)
        }
        .buttonStyle(.glassIcon(colorScheme: colorScheme))
        .ntfsmacKeyboardFocus(cornerRadius: 7)
        .disabled(presentation.isChecking)
        .accessibilityLabel(presentation.accessibilityLabel)
        .help(presentation.help)
    }

    /// Inline (in-popover) two-step confirmation — a native `confirmationDialog` would dismiss
    /// MenuBarExtra's transient window before the destructive action reliably reached the helper
    /// (per PR #10). `uninstallConfirmation.confirm()` consumes one explicit tap so a stale/double
    /// action can never start two uninstalls.
    private var inlineUninstallConfirmation: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Uninstall ntfsmac completely?")
                .font(.system(size: 13, weight: .semibold))
            Text("Removes the CLI, all vendored dependencies, and this privileged helper. Afterward, you can drag ntfsmac.app to the Trash. This can't be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") {
                    uninstallConfirmation.cancel()
                }
                .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                .ntfsmacKeyboardFocus()

                Button("Uninstall Everything", role: .destructive) {
                    guard uninstallConfirmation.confirm() else { return }
                    Task { await uninstaller.uninstallEverything() }
                }
                .buttonStyle(.glassDestructive(colorScheme: colorScheme))
                .ntfsmacKeyboardFocus()
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm complete ntfsmac uninstall")
    }

    private var isUninstallComplete: Bool {
        if case .done = uninstaller.state { return true }
        return false
    }

    @ViewBuilder
    private func row<Control: View>(
        _ title: String, _ subtitle: String, @ViewBuilder control: () -> Control
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
        .glassCard()
    }

}
