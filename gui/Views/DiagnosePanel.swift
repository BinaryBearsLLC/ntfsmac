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

/// Plain-language summary row (this unit's Do clause: "render a plain-language summary" — not
/// a raw JSON/log dump).
public struct DiagnoseSummaryRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
    public let isHealthy: Bool
}

/// Pure mapping from the real `DiagnoseReport` JSON shape to display rows — separated from the
/// `View` below the same way `StatusIcon`/`SecurityIndicator` are, so `DiagnoseRunnerTests` can
/// assert on parsed rows without a SwiftUI view-inspection dependency.
public enum DiagnoseSummary {
    public static func rows(for report: DiagnoseReport) -> [DiagnoseSummaryRow] {
        [
            DiagnoseSummaryRow(
                id: "binaries",
                label: "Vendor binaries",
                value: report.missingBinaries == 0 ? "all present" : "\(report.missingBinaries) missing",
                isHealthy: report.missingBinaries == 0
            ),
            DiagnoseSummaryRow(
                id: "quarantine",
                label: "Quarantine",
                value: report.quarantinedBinaries == 0 ? "clear" : "\(report.quarantinedBinaries) quarantined",
                isHealthy: report.quarantinedBinaries == 0
            ),
            DiagnoseSummaryRow(
                id: "kernel",
                label: "Kernel pin",
                value: report.kernelPin,
                isHealthy: report.kernelPin == "match"
            ),
            DiagnoseSummaryRow(
                id: "bridge",
                label: "vmnet bridge",
                value: report.bridge,
                isHealthy: report.bridge == "up"
            ),
        ]
    }
}

/// Reachable from idle + error states (this unit's Do clause) — the caller decides when to show
/// it; this view just renders whatever `DiagnoseRunner` currently has.
public struct DiagnosePanel: View {
    @ObservedObject public var runner: DiagnoseRunner
    public let onHide: (() -> Void)?

    public init(runner: DiagnoseRunner) {
        self.runner = runner
        self.onHide = nil
    }

    public init(runner: DiagnoseRunner, onHide: @escaping () -> Void) {
        self.runner = runner
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
                    ForEach(DiagnoseSummary.rows(for: report)) { row in
                        Label("\(row.label): \(row.value)", systemImage: row.isHealthy ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(row.isHealthy ? Color.primary : Color.orange)
                            .font(.caption)
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
}
