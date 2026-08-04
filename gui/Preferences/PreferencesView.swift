import SwiftUI

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
    public let onBack: (() -> Void)?
    public let productVersion: ProductVersion

    @Environment(\.colorScheme) private var colorScheme
    @State private var uninstallConfirmation: UninstallConfirmationPresentation

    public init(
        settings: Settings,
        installer: HelperInstaller,
        uninstaller: HelperUninstaller,
        onBack: (() -> Void)?
    ) {
        self.init(
            settings: settings,
            installer: installer,
            uninstaller: uninstaller,
            onBack: onBack,
            productVersion: .current(),
            uninstallConfirmation: .init()
        )
    }

    public init(
        settings: Settings,
        installer: HelperInstaller,
        uninstaller: HelperUninstaller,
        onBack: (() -> Void)?,
        productVersion: ProductVersion
    ) {
        self.init(
            settings: settings,
            installer: installer,
            uninstaller: uninstaller,
            onBack: onBack,
            productVersion: productVersion,
            uninstallConfirmation: .init()
        )
    }

    init(
        settings: Settings,
        installer: HelperInstaller,
        uninstaller: HelperUninstaller,
        onBack: (() -> Void)?,
        productVersion: ProductVersion,
        uninstallConfirmation: UninstallConfirmationPresentation
    ) {
        self.settings = settings
        self.installer = installer
        self.uninstaller = uninstaller
        self.onBack = onBack
        self.productVersion = productVersion
        _uninstallConfirmation = State(initialValue: uninstallConfirmation)
    }

    /// Source-compatible initializer for existing embeddings. The production app always supplies
    /// `onBack` and presents this view inside the menu-bar popover.
    public init(settings: Settings, installer: HelperInstaller, uninstaller: HelperUninstaller) {
        self.init(settings: settings, installer: installer, uninstaller: uninstaller, onBack: nil)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let onBack {
                    Button(action: onBack) {
                        HStack(spacing: 5) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                    .accessibilityLabel("Back to drives")
                } else {
                    Color.clear.frame(width: 57, height: 1)
                }

                Spacer()
                VStack(spacing: 1) {
                    Text("Settings")
                        .font(.system(size: 13, weight: .semibold))
                    Text(productVersion.settingsText)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.72))
                        .accessibilityLabel("ntfsmac \(productVersion.settingsText)")
                }
                Spacer()

                // Balance the Back pill so the title stays centered without adding a second
                // action or a hidden duplicate Settings control.
                Color.clear.frame(width: 57, height: 1)
            }

            Divider()

            row("Launch at login", "Start ntfsmac automatically on login") {
                Toggle("", isOn: $settings.launchAtLogin).labelsHidden()
            }

            Divider()

            row("Reinstall privileged helper", "Repair the SMJobBless XPC helper") {
                HStack(spacing: 6) {
                    if installer.state == .installing {
                        ProgressView().controlSize(.small)
                    }
                    Button("Reinstall…") {
                        Task { await installer.install() }
                    }
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
        .padding(12)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

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

                Button("Uninstall Everything", role: .destructive) {
                    guard uninstallConfirmation.confirm() else { return }
                    Task { await uninstaller.uninstallEverything() }
                }
                .buttonStyle(.glassDestructive(colorScheme: colorScheme))
            }
        }
        .glassCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Confirm complete ntfsmac uninstall")
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
