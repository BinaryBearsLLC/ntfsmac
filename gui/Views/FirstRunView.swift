import SwiftUI
import AppKit
import HelperShared

/// First-run helper-install prompt (GUI-PLAN.md "App shape": "No windows except Preferences and
/// the first-run helper prompt"). Performs a read-only registration check on appear, but never
/// starts registration or administrator authorization until the user explicitly chooses Install Helper.
/// Denial/failure renders
/// `ui/prototype.html`'s "Error — Helper Missing" card (comp lines 636-711) — red icon-box header,
/// message card, primary "Install Helper…" pill, and a footer so Quit/Settings stay reachable even
/// before the helper exists (previously this view had no footer at all — a real dead end).
/// ponytail: the comp's card also shows a separate "Retry" button next to "Diagnose", but this
/// app's `HelperInstaller` only exposes one unconditional `install()` path (Do clause: same path
/// Preferences' "Reinstall…" uses) — a second button calling the identical action would be a fake
/// distinction, so "Install Helper…" is the only action button; "Diagnose" is the other.
public struct FirstRunView: View {
    @ObservedObject public var installer: HelperInstaller
    @ObservedObject public var diagnoseRunner: DiagnoseRunner
    public let onOpenSettings: () -> Void
    public let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var diagnosePresentation = DiagnosePanelPresentation()

    public init(
        installer: HelperInstaller,
        diagnoseRunner: DiagnoseRunner,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.installer = installer
        self.diagnoseRunner = diagnoseRunner
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    public init(installer: HelperInstaller, diagnoseRunner: DiagnoseRunner, onQuit: @escaping () -> Void) {
        self.init(installer: installer, diagnoseRunner: diagnoseRunner, onOpenSettings: {}, onQuit: onQuit)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            switch installer.state {
            case .notChecked, .checking:
                ProgressView("Checking privileged helper…")
                    .frame(maxWidth: .infinity)
            case .readyToInstall:
                setupCard
                Button {
                    Task { await installer.installAfterConsent() }
                } label: {
                    HStack(spacing: 6) {
                        InstallHelperGlyph()
                        Text("Install Helper…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary())
                .ntfsmacKeyboardFocus()
            case .requiresApproval(let message):
                approvalCard(message: message)
                Button {
                    installer.openApprovalSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape.fill")
                        Text("Open Login Items…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary())
                .ntfsmacKeyboardFocus()

                Button("Refresh Approval") {
                    Task { await installer.checkWithoutInstalling() }
                }
                .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                .ntfsmacKeyboardFocus()
            case .installing:
                ProgressView("Installing privileged helper…")
                    .frame(maxWidth: .infinity)
            case .installed:
                Label("Privileged helper installed", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Color.ntfsGreen)
            case .denied(let message), .failed(let message):
                errorCard(message: message)
                Button {
                    Task { await installer.installAfterConsent() }
                } label: {
                    HStack(spacing: 6) {
                        InstallHelperGlyph()
                        Text("Install Helper…")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassPrimary())
                .ntfsmacKeyboardFocus()

                Button {
                    let mode = DiagnoseActionMode.resolve(
                        commandPressed: NSEvent.modifierFlags.contains(.command)
                    )
                    diagnosePresentation.show()
                    Task {
                        switch mode {
                        case .summary:
                            await diagnoseRunner.run()
                        case .developerJSONExport:
                            if let document = await diagnoseRunner.runForDeveloperExport() {
                                DeveloperDiagnoseSavePanel.present(document: document)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        DiagnoseGlyph()
                        Text("Diagnose")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                .ntfsmacKeyboardFocus()
                .disabled(diagnoseRunner.isRunning)
                .help(TooltipCopy.text(for: .diagnose))
            }

            if diagnosePresentation.isVisible {
                DiagnosePanel(runner: diagnoseRunner) {
                    diagnosePresentation.hide()
                }
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .task {
            await installer.checkWithoutInstalling()
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(headerColor.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(headerColor.opacity(0.28)))
                ErrorTriangleGlyph(color: headerColor)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("ntfsmac").font(.system(size: 13, weight: .semibold))
                Text(headerSubtitle).font(.system(size: 11)).foregroundStyle(headerColor.opacity(0.75))
            }
            Spacer()
            Circle().fill(headerColor).frame(width: 9, height: 9)
        }
    }

    private var headerColor: Color {
        switch installer.state {
        case .requiresApproval: .ntfsYellow
        case .denied, .failed: .ntfsRed
        case .installed: .ntfsGreen
        case .notChecked, .checking, .readyToInstall, .installing: .secondary
        }
    }

    private var headerSubtitle: String {
        switch installer.state {
        case .requiresApproval: "Approval required"
        case .denied, .failed: "Setup required"
        case .installed: "Privileged helper installed"
        case .notChecked, .checking: "Checking privileged helper…"
        case .readyToInstall: "Setup required"
        case .installing: "Installing privileged helper…"
        }
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Install the privileged helper")
                .font(.system(size: 12.5, weight: .semibold))
            Text(helperInstallExplanation)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.secondary.opacity(0.16)))
    }

    private var helperInstallExplanation: String {
        switch HelperDistributionVariant.current {
        case .modern:
            "ntfsmac uses a bundled helper to mount and unmount drives safely. macOS will ask you to approve ntfsmac in Login Items."
        case .legacy:
            "ntfsmac Legacy uses a compatibility helper to mount and unmount drives safely. macOS will ask for an administrator password."
        }
    }

    private func approvalCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Approve ntfsmac Helper")
                .font(.system(size: 12.5, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ntfsYellow.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.ntfsYellow.opacity(0.2)))
    }

    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Privileged helper not installed")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.ntfsRed.opacity(0.95))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ntfsRed.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.ntfsRed.opacity(0.2)))
    }

    private var footer: some View {
        HStack {
            Button {
                onOpenSettings()
            } label: {
                SettingsGearGlyph(color: .secondary)
            }
            .buttonStyle(.glassIcon(colorScheme: colorScheme))
            .ntfsmacKeyboardFocus()
            .accessibilityLabel("Open Settings")
            .help(TooltipCopy.text(for: .settings))
            Spacer()
            Button(action: onQuit) {
                Text("Quit").frame(height: 28)
            }
            .buttonStyle(.glassFooter(colorScheme: colorScheme))
            .ntfsmacKeyboardFocus()
            .help(TooltipCopy.text(for: .quit))
        }
    }
}
