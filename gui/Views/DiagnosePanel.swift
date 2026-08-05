import SwiftUI

public enum DiagnosePanelPhase: Equatable, Sendable {
    case hidden
    case running
    case result
    case error
    case empty
}

/// Visibility is independent from diagnostic data: hiding the panel must never clear a result,
/// cancel work, or change helper/mount state. Keeping this as a small value type also makes every
/// visibility transition testable without coupling tests to SwiftUI internals.
public struct DiagnosePanelPresentation: Equatable, Sendable {
    public private(set) var isVisible = false

    public init() {}

    public mutating func show() { isVisible = true }
    public mutating func hide() { isVisible = false }

    public func phase(report: DiagnoseReport?, errorMessage: String?, isRunning: Bool) -> DiagnosePanelPhase {
        guard isVisible else { return .hidden }
        if isRunning { return .running }
        if report != nil { return .result }
        if errorMessage != nil { return .error }
        return .empty
    }
}

/// Diagnostics need more than a healthy/unhealthy Boolean. In particular, a stopped vmnet
/// bridge is expected while ntfsmac is idle, while an unknown raw value must not be presented as
/// a confirmed failure.
public enum DiagnoseStatus: String, Equatable, Sendable {
    case healthy
    case informational
    case warning
    case unavailable
}

/// Plain-language summary row (this unit's Do clause: "render a plain-language summary" — not
/// a raw JSON/log dump).
public struct DiagnoseSummaryRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let status: DiagnoseStatus
    public let explanation: String

    /// Retained for source compatibility with callers that only distinguish confirmed health.
    public var isHealthy: Bool { status == .healthy }
}

/// Pure mapping from the real `DiagnoseReport` JSON shape to display rows — separated from the
/// `View` below the same way `StatusIcon`/`SecurityIndicator` are, so `DiagnoseRunnerTests` can
/// assert on parsed rows without a SwiftUI view-inspection dependency.
public enum DiagnoseSummary {
    public static func rows(for report: DiagnoseReport) -> [DiagnoseSummaryRow] {
        rows(for: report, mountState: nil)
    }

    public static func rows(for report: DiagnoseReport, mountState: MountState?) -> [DiagnoseSummaryRow] {
        [
            binariesRow(missingCount: report.missingBinaries),
            quarantineRow(quarantinedCount: report.quarantinedBinaries),
            kernelRow(rawValue: report.kernelPin),
            bridgeRow(rawValue: report.bridge, mountState: mountState),
        ]
    }

    private static func binariesRow(missingCount: Int) -> DiagnoseSummaryRow {
        let explanation = "These are the four runtime components required by ntfsmac. Missing components require installation or repair."
        guard missingCount >= 0 else {
            return .init(id: "binaries", label: "Vendor binaries", value: "Unknown", status: .unavailable, explanation: explanation)
        }
        return .init(
            id: "binaries",
            label: "Vendor binaries",
            value: missingCount == 0 ? "All present" : "\(missingCount) missing",
            status: missingCount == 0 ? .healthy : .warning,
            explanation: explanation
        )
    }

    private static func quarantineRow(quarantinedCount: Int) -> DiagnoseSummaryRow {
        let explanation = "macOS quarantine can prevent downloaded runtime components from executing."
        guard quarantinedCount >= 0 else {
            return .init(id: "quarantine", label: "Quarantine", value: "Unknown", status: .unavailable, explanation: explanation)
        }
        return .init(
            id: "quarantine",
            label: "Quarantine",
            value: quarantinedCount == 0 ? "Clear" : "\(quarantinedCount) quarantined",
            status: quarantinedCount == 0 ? .healthy : .warning,
            explanation: explanation
        )
    }

    private static func kernelRow(rawValue: String) -> DiagnoseSummaryRow {
        let explanation = "The installed kernel module bundle is checked against the exact version tested by the project."
        switch rawValue {
        case "match":
            return .init(id: "kernel", label: "Kernel pin", value: "Match", status: .healthy, explanation: explanation)
        case "mismatch":
            return .init(id: "kernel", label: "Kernel pin", value: "Mismatch", status: .warning, explanation: explanation)
        case "missing":
            return .init(id: "kernel", label: "Kernel pin", value: "Missing", status: .warning, explanation: explanation)
        case "unknown":
            return .init(id: "kernel", label: "Kernel pin", value: "Unknown", status: .unavailable, explanation: explanation)
        default:
            return .init(id: "kernel", label: "Kernel pin", value: "Unknown", status: .unavailable, explanation: explanation)
        }
    }

    private static func bridgeRow(rawValue: String, mountState: MountState?) -> DiagnoseSummaryRow {
        let explanation = "ntfsmac's private host-only network carries NFS traffic between macOS and the microVM."
        guard rawValue == "down" else {
            if rawValue == "up" {
                return .init(id: "bridge", label: "vmnet bridge", value: "Active", status: .healthy, explanation: explanation)
            }
            return .init(id: "bridge", label: "vmnet bridge", value: "Unknown", status: .unavailable, explanation: explanation)
        }

        switch mountState {
        case .idle:
            return .init(id: "bridge", label: "vmnet bridge", value: "Idle — starts when a drive is mounted", status: .informational, explanation: explanation)
        case .mounting:
            return .init(id: "bridge", label: "vmnet bridge", value: "Starting with the mount", status: .informational, explanation: explanation)
        case .mountedReadWrite, .mountedReadOnly, .mountedReadOnlyDirty:
            return .init(id: "bridge", label: "vmnet bridge", value: "Inactive while a drive is mounted", status: .warning, explanation: explanation)
        case .error, .none:
            return .init(id: "bridge", label: "vmnet bridge", value: "Inactive — mount context unavailable", status: .unavailable, explanation: explanation)
        }
    }
}

/// Reachable from idle + error states (this unit's Do clause) — the caller decides when to show
/// it; this view just renders whatever `DiagnoseRunner` currently has.
public struct DiagnosePanel: View {
    @ObservedObject public var runner: DiagnoseRunner
    public let mountState: MountState?
    public let onHide: (() -> Void)?

    public init(runner: DiagnoseRunner) {
        self.runner = runner
        self.mountState = nil
        self.onHide = nil
    }

    public init(runner: DiagnoseRunner, onHide: @escaping () -> Void) {
        self.runner = runner
        self.mountState = nil
        self.onHide = onHide
    }

    public init(runner: DiagnoseRunner, mountState: MountState?, onHide: (() -> Void)? = nil) {
        self.runner = runner
        self.mountState = mountState
        self.onHide = onHide
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let onHide {
                HStack(spacing: 8) {
                    Text("Diagnostics")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Hide", action: onHide)
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Hide diagnostics")
                        .help("Hide the diagnostic panel")
                }
            }

            Group {
                if let report = runner.report {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(DiagnoseSummary.rows(for: report, mountState: mountState)) { row in
                            Label("\(row.label): \(row.value)", systemImage: iconName(for: row.status))
                                .foregroundStyle(color(for: row.status))
                                .font(.caption)
                                .help(row.explanation)
                                .accessibilityHint(row.explanation)
                        }
                    }
                } else if let errorMessage = runner.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Color.ntfsRed.opacity(0.95))
                } else if runner.isRunning {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(panelBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(panelBorderColor))
        .padding(.top, 4)
    }

    private var panelBackgroundColor: Color {
        runner.errorMessage == nil ? Color.secondary.opacity(0.08) : Color.ntfsRed.opacity(0.09)
    }

    private var panelBorderColor: Color {
        runner.errorMessage == nil ? Color.secondary.opacity(0.12) : Color.ntfsRed.opacity(0.2)
    }

    private func iconName(for status: DiagnoseStatus) -> String {
        switch status {
        case .healthy: "checkmark.circle"
        case .informational: "info.circle"
        case .warning: "exclamationmark.circle"
        case .unavailable: "questionmark.circle"
        }
    }

    private func color(for status: DiagnoseStatus) -> Color {
        switch status {
        case .healthy: .primary
        case .informational: .ntfsBlue
        case .warning: .orange
        case .unavailable: .secondary
        }
    }
}
