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

/// GUI-PLAN.md "Settings page" table, using the same controls and application-owned state as the
/// former Preferences window. "Reinstall privileged helper" reuses `HelperInstaller.install()`
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
                // ZStack so "Settings" centers over the full popover width — an HStack with two
                // Spacers would center it in the *remaining* space after the Back button, sitting
                // right-of-true-center. The title is the visual anchor; Back is overlaid leading.
                ZStack {
                    VStack(spacing: 1) {
                        Text("Settings")
                            .font(.system(size: 13, weight: .semibold))
                        Text(productVersion.settingsText)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.72))
                            .accessibilityLabel("ntfsmac \(productVersion.settingsText)")
                        Text(HelperDistributionVariant.current.settingsLabel)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.secondary.opacity(0.72))
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
                        .focusable(true)
                        .accessibilityLabel("Back")
                        .help(TooltipCopy.text(for: .back))
                        Spacer()
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
                    .focusable(true)
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
                    .focusable(true)
                    .disabled(settings.isUpdatingNotifications)
                    .accessibilityLabel("Mount notifications")
                }
            }

            row("Software update", updateSubtitle) {
                if case .updateAvailable = updateChecker.state {
                    Button("View on GitHub") {
                        updateChecker.openAvailableRelease()
                    }
                    .focusable(true)
                } else {
                    HStack(spacing: 6) {
                        if updateChecker.state == .checking {
                            ProgressView().controlSize(.small)
                        }
                        Button("Check…") {
                            Task {
                                await updateChecker.checkManually(
                                    currentVersion: productVersion.release
                                )
                            }
                        }
                        .focusable(true)
                        .disabled(updateChecker.state == .checking)
                    }
                }
            }

            Divider()

            row("Reinstall privileged helper", helperRepairSubtitle) {
                HStack(spacing: 6) {
                    if installer.state == .installing {
                        ProgressView().controlSize(.small)
                    }
                    if case .requiresApproval = installer.state {
                        Button("Approve…") {
                            installer.openApprovalSettings()
                        }
                        .focusable(true)
                    }
                    Button(helperRequiresApproval ? "Refresh" : "Reinstall…") {
                        Task {
                            if helperRequiresApproval {
                                await installer.installAfterConsent()
                            } else {
                                await installer.reinstallAfterConsent()
                            }
                        }
                    }
                    .focusable(true)
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
                    .focusable(true)
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
        switch HelperDistributionVariant.current {
        case .modern:
            return "Repair the bundled modern XPC helper"
        case .legacy:
            return "Repair the Legacy SMJobBless XPC helper"
        }
    }

    private var helperRequiresApproval: Bool {
        if case .requiresApproval = installer.state { return true }
        return false
    }

    private var updateSubtitle: String {
        switch updateChecker.state {
        case .idle:
            return "Checks published GitHub Releases only"
        case .checking:
            return "Checking GitHub Releases…"
        case .upToDate:
            return "Version \(productVersion.release) is up to date"
        case .updateAvailable(let release):
            return "Version \(release.version) is available"
        case .failed(let message):
            return message
        }
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
                .focusable(true)

                Button("Uninstall Everything", role: .destructive) {
                    guard uninstallConfirmation.confirm() else { return }
                    Task { await uninstaller.uninstallEverything() }
                }
                .buttonStyle(.glassDestructive(colorScheme: colorScheme))
                .focusable(true)
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
