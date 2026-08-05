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
        var rows: [DiagnoseSummaryRow] = []
        if let version = versionRow(release: report.ntfsmacVersion, build: report.buildVersion) {
            rows.append(version)
        }
        if let system = systemRow(
            macOSVersion: report.macosVersion,
            architecture: report.architecture
        ) {
            rows.append(system)
        }
        rows.append(contentsOf: [
            binariesRow(
                missingCount: report.missingBinaries,
                components: report.missingComponents
            ),
            quarantineRow(
                quarantinedCount: report.quarantinedBinaries,
                components: report.quarantinedComponents
            ),
            kernelRow(rawValue: report.kernelPin),
        ])
        if let anylinuxfs = anylinuxfsRow(report) {
            rows.append(anylinuxfs)
        }
        if let virtualization = virtualizationRow(report) {
            rows.append(virtualization)
        }
        if let alpine = alpineRuntimeRow(
            tag: report.alpineRuntimeTag,
            digest: report.alpineRuntimeDigest,
            state: report.alpineRuntimeState
        ) {
            rows.append(alpine)
        }
        if let guest = guestVersionsRow(report) {
            rows.append(guest)
        }
        if let networking = networkToolsRow(report) {
            rows.append(networking)
        }
        rows.append(bridgeRow(rawValue: report.bridge, mountState: mountState))
        if let helperInstalled = report.helperInstalled {
            rows.append(helperRow(installed: helperInstalled))
        }
        if let vpnDefaultRoute = report.vpnDefaultRoute {
            rows.append(vpnRow(detected: vpnDefaultRoute))
        }
        if let mountCount = report.nfsMountCount {
            rows.append(mountCountRow(count: mountCount))
        }
        return rows
    }

    private static func versionRow(release: String?, build: String?) -> DiagnoseSummaryRow? {
        guard let release, !release.isEmpty else { return nil }
        let value = build.map {
            $0.isEmpty || $0 == release ? release : "\(release) (\($0))"
        } ?? release
        return .init(
            id: "version",
            label: "ntfsmac",
            value: value,
            status: release == "unknown" ? .unavailable : .informational,
            explanation: "The product and build versions that produced this diagnostic report."
        )
    }

    private static func systemRow(
        macOSVersion: String?,
        architecture: String?
    ) -> DiagnoseSummaryRow? {
        guard macOSVersion != nil || architecture != nil else { return nil }
        let os = macOSVersion ?? "unknown"
        let arch = architecture ?? "unknown architecture"
        let macOSMajor = macOSVersion.flatMap { Int($0.split(separator: ".").first ?? "") }
        let status: DiagnoseStatus
        if let architecture, architecture != "arm64" {
            status = .warning
        } else if let macOSMajor, macOSMajor < 13 {
            status = .warning
        } else if architecture == "arm64", let macOSMajor, macOSMajor >= 13 {
            status = .healthy
        } else {
            status = .unavailable
        }
        return .init(
            id: "system",
            label: "System",
            value: "macOS \(os) · \(arch)",
            status: status,
            explanation: "ntfsmac requires Apple Silicon and macOS 13.0 or newer."
        )
    }

    private static func binariesRow(
        missingCount: Int,
        components: [String]?
    ) -> DiagnoseSummaryRow {
        let explanation = "These are the four runtime components required by ntfsmac. Missing components require installation or repair."
        guard missingCount >= 0 else {
            return .init(id: "binaries", label: "Vendor binaries", value: "Unknown", status: .unavailable, explanation: explanation)
        }
        let namedMissing = components?.filter { !$0.isEmpty } ?? []
        let missingValue = namedMissing.isEmpty
            ? "\(missingCount) missing"
            : "Missing: \(namedMissing.joined(separator: ", "))"
        return .init(
            id: "binaries",
            label: "Vendor binaries",
            value: missingCount == 0 ? "All present" : missingValue,
            status: missingCount == 0 ? .healthy : .warning,
            explanation: explanation
        )
    }

    private static func quarantineRow(
        quarantinedCount: Int,
        components: [String]?
    ) -> DiagnoseSummaryRow {
        let explanation = "macOS quarantine can prevent downloaded runtime components from executing."
        guard quarantinedCount >= 0 else {
            return .init(id: "quarantine", label: "Quarantine", value: "Unknown", status: .unavailable, explanation: explanation)
        }
        let namedQuarantined = components?.filter { !$0.isEmpty } ?? []
        let quarantinedValue = namedQuarantined.isEmpty
            ? "\(quarantinedCount) quarantined"
            : "Quarantined: \(namedQuarantined.joined(separator: ", "))"
        return .init(
            id: "quarantine",
            label: "Quarantine",
            value: quarantinedCount == 0 ? "Clear" : quarantinedValue,
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

    private static func versionStatus(_ rawValue: String?) -> DiagnoseStatus {
        switch rawValue {
        case "match": .healthy
        case "mismatch", "not_installed", "quarantined": .warning
        default: .unavailable
        }
    }

    private static func displayVersion(_ rawValue: String?) -> String {
        switch rawValue {
        case nil, "", "unknown": "Unknown"
        case "not_installed": "Not installed"
        case "quarantined": "Quarantined"
        case let value?: value
        }
    }

    private static func shortCommit(_ rawValue: String?) -> String? {
        guard let rawValue, rawValue.count == 40,
              rawValue.allSatisfy({ $0.isHexDigit }) else { return nil }
        return String(rawValue.prefix(12))
    }

    private static func anylinuxfsRow(_ report: DiagnoseReport) -> DiagnoseSummaryRow? {
        guard report.anylinuxfsVersion != nil || report.anylinuxfsSourceCommit != nil else { return nil }
        var value = displayVersion(report.anylinuxfsVersion)
        if report.anylinuxfsVersionStatus == "mismatch",
           let expected = report.anylinuxfsExpectedVersion {
            value += " · expected \(expected)"
        }
        if let commit = shortCommit(report.anylinuxfsSourceCommit) {
            value += " · \(commit)"
        }
        return .init(
            id: "anylinuxfs",
            label: "anylinuxfs",
            value: value,
            status: versionStatus(report.anylinuxfsVersionStatus),
            explanation: "Detected host runtime version, compared with the version and audited source commit approved by this build."
        )
    }

    private static func virtualizationRow(_ report: DiagnoseReport) -> DiagnoseSummaryRow? {
        let values = [
            report.vmproxySourceVersion.map { "vmproxy \($0)" },
            report.libkrunVersion.map { "libkrun \($0)" },
            report.libkrunfwVersion.map { "libkrunfw \($0)" },
        ].compactMap { $0 }
        guard !values.isEmpty else { return nil }
        return .init(
            id: "virtualization",
            label: "VM runtime",
            value: values.joined(separator: " · "),
            status: values.contains(where: { $0.contains("unknown") }) ? .unavailable : .informational,
            explanation: "Pinned guest-agent, hypervisor-library, and kernel/firmware versions used by the microVM. Binary presence and kernel hash are reported separately."
        )
    }

    private static func guestVersionsRow(_ report: DiagnoseReport) -> DiagnoseSummaryRow? {
        guard report.alpineInstalledVersion != nil || report.ntfs3gVersion != nil || report.nfsUtilsVersion != nil else { return nil }
        let value = [
            "Alpine \(displayVersion(report.alpineInstalledVersion))",
            "ntfs-3g \(displayVersion(report.ntfs3gVersion))",
            "nfs-utils \(displayVersion(report.nfsUtilsVersion))",
        ].joined(separator: " · ")
        let status: DiagnoseStatus
        switch report.alpineInstalledCache {
        case "pinned" where report.ntfs3gVersion != "not_installed" && report.nfsUtilsVersion != "not_installed":
            status = .healthy
        case "none", "legacy":
            status = .informational
        case "invalid", "pinned_unusable":
            status = .warning
        default:
            status = .unavailable
        }
        return .init(
            id: "guest_versions",
            label: "Installed guest",
            value: value,
            status: status,
            explanation: "Versions read from the selected Alpine cache and its local APK database. No VM is started and no package is downloaded."
        )
    }

    private static func networkToolsRow(_ report: DiagnoseReport) -> DiagnoseSummaryRow? {
        guard report.gvproxyVersion != nil || report.vmnetHelperVersion != nil else { return nil }
        let statuses = [versionStatus(report.gvproxyVersionStatus), versionStatus(report.vmnetHelperVersionStatus)]
        let status: DiagnoseStatus = statuses.contains(.warning)
            ? .warning
            : (statuses.allSatisfy { $0 == .healthy } ? .healthy : .unavailable)
        return .init(
            id: "network_tools",
            label: "Network tools",
            value: "gvproxy \(displayVersion(report.gvproxyVersion)) · vmnet-helper \(displayVersion(report.vmnetHelperVersion))",
            status: status,
            explanation: "Detected versions of the host networking tools, compared with the versions approved by this build."
        )
    }

    private static func alpineRuntimeRow(
        tag: String?,
        digest: String?,
        state: String?
    ) -> DiagnoseSummaryRow? {
        guard tag != nil || digest != nil || state != nil else { return nil }
        let explanation = "The Linux runtime is pinned to the exact Alpine tag and arm64 image digest approved by this build. Upgrades keep earlier caches for rollback."
        let safeTag = tag.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        let digestPrefix: String = {
            guard let digest, digest.hasPrefix("sha256:"), digest.count >= 19 else { return "unknown digest" }
            return "sha256:\(digest.dropFirst(7).prefix(12))…"
        }()

        switch state {
        case "initialized":
            return .init(id: "alpine", label: "Alpine runtime", value: "\(safeTag) · \(digestPrefix)", status: .healthy, explanation: explanation)
        case "not_initialized":
            return .init(id: "alpine", label: "Alpine runtime", value: "\(safeTag) · not initialized", status: .informational, explanation: explanation)
        case "migration_available":
            return .init(id: "alpine", label: "Alpine runtime", value: "\(safeTag) · safe migration on next mount", status: .informational, explanation: explanation)
        case "mismatch", "incomplete", "invalid":
            return .init(id: "alpine", label: "Alpine runtime", value: "Needs safe reinitialization", status: .warning, explanation: explanation)
        default:
            return .init(id: "alpine", label: "Alpine runtime", value: "Unknown", status: .unavailable, explanation: explanation)
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

    private static func helperRow(installed: Bool) -> DiagnoseSummaryRow {
        .init(
            id: "helper",
            label: "Privileged helper",
            value: installed ? "Installed" : "Not installed",
            status: installed ? .healthy : .informational,
            explanation: "The GUI uses its SMJobBless helper for mount, unmount, firewall, and route operations. A CLI-only installation may not need it."
        )
    }

    private static func vpnRow(detected: Bool) -> DiagnoseSummaryRow {
        .init(
            id: "vpn",
            label: "VPN routing",
            value: detected ? "Default route uses a tunnel" : "No tunnel default route detected",
            status: .informational,
            explanation: "Only a yes/no tunnel signal is reported; ntfsmac never includes the VPN provider, interface name, addresses, DNS, or routes."
        )
    }

    private static func mountCountRow(count: Int) -> DiagnoseSummaryRow {
        let explanation = "Number of active NFS mounts, without device names, labels, or paths."
        guard count >= 0 else {
            return .init(
                id: "mounts",
                label: "NFS mounts",
                value: "Unknown",
                status: .unavailable,
                explanation: explanation
            )
        }
        return .init(
            id: "mounts",
            label: "NFS mounts",
            value: count == 0 ? "None" : "\(count) active",
            status: count == 0 ? .informational : .healthy,
            explanation: explanation
        )
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
