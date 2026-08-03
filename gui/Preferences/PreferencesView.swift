import SwiftUI

/// GUI-PLAN.md "Settings page" table, using the same controls and application-owned state as the
/// former Preferences window. "Reinstall privileged helper" reuses `HelperInstaller.install()`
/// directly — the same path `3-first-run-install` built for first-run, per that unit's Do clause.
public struct PreferencesView: View {
    @ObservedObject public var settings: Settings
    @ObservedObject public var installer: HelperInstaller
    @ObservedObject public var uninstaller: HelperUninstaller
    public let onBack: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isConfirmingUninstall = false

    public init(
        settings: Settings,
        installer: HelperInstaller,
        uninstaller: HelperUninstaller,
        onBack: (() -> Void)?
    ) {
        self.settings = settings
        self.installer = installer
        self.uninstaller = uninstaller
        self.onBack = onBack
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
                Text("Settings").font(.system(size: 13, weight: .semibold))
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
                        isConfirmingUninstall = true
                    }
                    .disabled(uninstaller.state == .removingDependencies || uninstaller.state == .removingHelper)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog(
            "Uninstall ntfsmac completely?",
            isPresented: $isConfirmingUninstall
        ) {
            Button("Uninstall Everything", role: .destructive) {
                Task { await uninstaller.uninstallEverything() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the CLI, all vendored dependencies, and this privileged helper. After this, dragging ntfsmac.app to the Trash leaves nothing behind. This can't be undone — you'll need to reinstall to use ntfsmac again.")
        }
    }

    private var uninstallSubtitle: String {
        switch uninstaller.state {
        case .idle, .removingDependencies, .removingHelper:
            return "Remove the CLI, dependencies, and this helper — no leftovers"
        case .done:
            return "Uninstalled. Safe to drag ntfsmac.app to the Trash."
        case .failed(let message):
            return "Failed: \(message)"
        }
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
