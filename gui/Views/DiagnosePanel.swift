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

/// GUI-only semantic states. The CLI and exported JSON keep their detailed schema unchanged;
/// these values deliberately describe only what a person needs to decide next.
public enum DiagnoseMacroState: String, Equatable, Sendable {
    case idle
    case checking
    case ok
    case attention
    case failed
    case unavailable

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .checking: "Checking"
        case .ok: "OK"
        case .attention: "Attention"
        case .failed: "Failed"
        case .unavailable: "Unavailable"
        }
    }

    public var symbolName: String {
        switch self {
        case .idle: "pause.circle"
        case .checking: "arrow.triangle.2.circlepath"
        case .ok: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        case .unavailable: "questionmark.circle"
        }
    }
}

public struct DiagnoseMacroRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let state: DiagnoseMacroState
    public let summary: String
    public let explanation: String
    public let nextAction: String?

    public var userFacingText: String {
        [title, state.label, summary, explanation, nextAction].compactMap { $0 }.joined(separator: " ")
    }
}

/// Fail-closed presentation model for the normal GUI. It intentionally contains no service
/// identifiers, implementation names, raw reason codes, paths, versions, or network internals.
/// Those remain available through `ntfsmac diagnose` and Command-click Diagnose export.
public enum DiagnoseMacroSummary {
    public static let categoryTitles = [
        "App readiness", "Drive status", "Connection protection", "Permissions",
    ]

    public static var checkingRows: [DiagnoseMacroRow] {
        zip(["app", "drive", "protection", "permissions"], categoryTitles).map { id, title in
            .init(
                id: id,
                title: title,
                state: .checking,
                summary: "Checking…",
                explanation: "Reading the latest local status without changing your drives.",
                nextAction: nil
            )
        }
    }

    public static func rows(
        for report: DiagnoseReport,
        mountState: MountState?,
        detectedDriveCount: Int?,
        fullDiskAccessGranted: Bool?
    ) -> [DiagnoseMacroRow] {
        [
            appReadiness(report),
            driveStatus(report, mountState: mountState, detectedDriveCount: detectedDriveCount),
            connectionProtection(report, mountState: mountState),
            permissions(
                report,
                mountState: mountState,
                detectedDriveCount: detectedDriveCount,
                fullDiskAccessGranted: fullDiskAccessGranted
            ),
        ]
    }

    public static func failureRow(_ message: String) -> DiagnoseMacroRow {
        .init(
            id: "diagnostic",
            title: "Diagnostic check",
            state: .failed,
            summary: "Could not complete",
            explanation: message,
            nextAction: "Try Diagnose again. If it still fails, reinstall ntfsmac from a verified DMG."
        )
    }

    private static func appReadiness(_ report: DiagnoseReport) -> DiagnoseMacroRow {
        let unavailable = DiagnoseMacroRow(
            id: "app",
            title: "App readiness",
            state: .unavailable,
            summary: "Could not confirm",
            explanation: "ntfsmac could not confirm every app check required for drive access.",
            nextAction: "Run Diagnose again. If this persists, reinstall ntfsmac from a verified DMG."
        )

        guard report.missingBinaries >= 0, report.quarantinedBinaries >= 0 else { return unavailable }

        let confirmedRepair = report.missingBinaries > 0
            || report.quarantinedBinaries > 0
            || ["mismatch", "missing"].contains(report.kernelPin)
            || report.architecture.map { $0 != "arm64" } == true
            || unsupportedMacOS(report.macosVersion)
            || [report.anylinuxfsVersionStatus, report.gvproxyVersionStatus, report.vmnetHelperVersionStatus]
                .contains { status in
                    guard let status else { return false }
                    return status != "match"
                }
            || report.alpineRuntimeState.map {
                !["initialized", "not_initialized", "migration_available"].contains($0)
            } == true

        if confirmedRepair {
            return .init(
                id: "app",
                title: "App readiness",
                state: .failed,
                summary: "Repair needed",
                explanation: "Some files ntfsmac needs are missing, blocked, or incompatible.",
                nextAction: "Reinstall ntfsmac from a verified DMG, then run Diagnose again."
            )
        }

        if report.helperInstalled == false {
            return .init(
                id: "app",
                title: "App readiness",
                state: .attention,
                summary: "Setup needed",
                explanation: "ntfsmac still needs a macOS approval before it can manage drives.",
                nextAction: "Open Settings and choose Repair app access."
            )
        }

        guard report.diagnosticSchema.map({ $0 >= 6 }) == true,
              report.helperInstalled == true,
              report.architecture == "arm64",
              supportedMacOS(report.macosVersion),
              report.kernelPin == "match",
              report.anylinuxfsVersionStatus == "match",
              report.gvproxyVersionStatus == "match",
              report.vmnetHelperVersionStatus == "match",
              let appState = report.alpineRuntimeState,
              ["initialized", "not_initialized", "migration_available"].contains(appState)
        else { return unavailable }

        return .init(
            id: "app",
            title: "App readiness",
            state: .ok,
            summary: "Ready",
            explanation: "Everything ntfsmac needs is present and compatible.",
            nextAction: nil
        )
    }

    private static func driveStatus(
        _ report: DiagnoseReport,
        mountState: MountState?,
        detectedDriveCount: Int?
    ) -> DiagnoseMacroRow {
        switch mountState {
        case .mounting:
            return .init(id: "drive", title: "Drive status", state: .checking, summary: "Mounting…", explanation: "ntfsmac is waiting for macOS to confirm the mounted drive.", nextAction: nil)
        case .mountedReadWrite:
            return .init(id: "drive", title: "Drive status", state: .ok, summary: "Mounted read/write", explanation: "The drive is mounted and ready for normal use.", nextAction: nil)
        case .mountedReadOnly:
            return .init(id: "drive", title: "Drive status", state: .attention, summary: "Mounted read-only", explanation: "The drive is available, but changes are currently disabled.", nextAction: "Unmount it safely before checking or repairing it on the system that created it.")
        case .mountedReadOnlyDirty:
            return .init(id: "drive", title: "Drive status", state: .attention, summary: "Windows recovery needed", explanation: "The drive is protected in read-only mode because Windows did not leave it in a safe state.", nextAction: "Unmount it, fully shut down Windows, run its disk check, then reconnect it.")
        case .mountedUnknown:
            return .init(id: "drive", title: "Drive status", state: .unavailable, summary: "Mount needs verification", explanation: "ntfsmac cannot yet confirm the drive's current access mode.", nextAction: "Use Refresh. If this persists, unmount the drive before reconnecting it.")
        case .error:
            let unsafeWindowsState = report.mountFailureCategory == "unsafe_windows_state"
            return .init(
                id: "drive",
                title: "Drive status",
                state: unsafeWindowsState ? .attention : .failed,
                summary: unsafeWindowsState ? "Windows recovery needed" : "Mount failed",
                explanation: unsafeWindowsState
                    ? "ntfsmac refused a write operation to protect the drive."
                    : "ntfsmac could not complete the last drive operation.",
                nextAction: unsafeWindowsState
                    ? "Fully shut down Windows, run its disk check, then reconnect the drive."
                    : "Use Refresh and try once more. Keep the drive connected while recovery completes."
            )
        case .idle:
            guard let detectedDriveCount, detectedDriveCount >= 0 else {
                return .init(id: "drive", title: "Drive status", state: .unavailable, summary: "Could not confirm", explanation: "The current drive inventory is unavailable.", nextAction: "Use Refresh and run Diagnose again.")
            }
            if detectedDriveCount == 0 {
                return .init(id: "drive", title: "Drive status", state: .idle, summary: "No compatible drive", explanation: "Connect an NTFS or ext drive when you are ready.", nextAction: nil)
            }
            return .init(id: "drive", title: "Drive status", state: .idle, summary: "Ready to mount", explanation: detectedDriveCount == 1 ? "One compatible drive is detected." : "\(detectedDriveCount) compatible drives are detected.", nextAction: nil)
        case .none:
            return .init(id: "drive", title: "Drive status", state: .unavailable, summary: "Could not confirm", explanation: "The current drive state is unavailable.", nextAction: "Use Refresh and run Diagnose again.")
        }
    }

    private static func connectionProtection(
        _ report: DiagnoseReport,
        mountState: MountState?
    ) -> DiagnoseMacroRow {
        switch mountState {
        case .idle:
            return .init(id: "protection", title: "Connection protection", state: .idle, summary: "Not currently needed", explanation: "Protection activates automatically when ntfsmac mounts a drive.", nextAction: nil)
        case .mounting:
            return .init(id: "protection", title: "Connection protection", state: .checking, summary: "Starting…", explanation: "ntfsmac is confirming protection for the new mount.", nextAction: nil)
        case .mountedUnknown, .none:
            return .init(id: "protection", title: "Connection protection", state: .unavailable, summary: "Could not confirm", explanation: "The protection state is not available, so ntfsmac will not report it as safe.", nextAction: "Run Diagnose again before relying on this mount.")
        case .error where (report.securityActiveSessions ?? 0) == 0:
            return .init(id: "protection", title: "Connection protection", state: .unavailable, summary: "Could not confirm", explanation: "The last drive operation ended before protection could be verified.", nextAction: "Resolve the drive error, then run Diagnose again.")
        case .mountedReadWrite, .mountedReadOnly, .mountedReadOnlyDirty, .error:
            guard let activeSessions = report.securityActiveSessions else {
                return .init(id: "protection", title: "Connection protection", state: .unavailable, summary: "Could not confirm", explanation: "The protection evidence is incomplete, so ntfsmac will not report it as safe.", nextAction: "Run Diagnose again. If this persists, unmount the drive safely.")
            }
            guard activeSessions > 0 else {
                return .init(id: "protection", title: "Connection protection", state: .failed, summary: "Protection missing", explanation: "A mounted drive is active, but its required protection was not confirmed.", nextAction: "Unmount the drive safely and run Diagnose again before remounting it.")
            }
            switch report.securityOverall {
            case "enforced":
                return .init(id: "protection", title: "Connection protection", state: .ok, summary: "Protected", explanation: "The active drive connection is using ntfsmac's required safeguards.", nextAction: nil)
            case "notEnforced":
                return .init(id: "protection", title: "Connection protection", state: .failed, summary: "Protection incomplete", explanation: "One or more safeguards required for the active mount are not in place.", nextAction: "Unmount the drive safely, then run Diagnose again before remounting it.")
            default:
                return .init(id: "protection", title: "Connection protection", state: .unavailable, summary: "Could not confirm", explanation: "The protection evidence is incomplete, so ntfsmac will not report it as safe.", nextAction: "Run Diagnose again. If this persists, unmount the drive safely.")
            }
        }
    }

    private static func permissions(
        _ report: DiagnoseReport,
        mountState: MountState?,
        detectedDriveCount: Int?,
        fullDiskAccessGranted: Bool?
    ) -> DiagnoseMacroRow {
        if fullDiskAccessGranted == false {
            return .init(id: "permissions", title: "Permissions", state: .attention, summary: "Full Disk Access needed", explanation: "macOS has not yet allowed ntfsmac to read supported drives.", nextAction: "Open System Settings > Privacy & Security > Full Disk Access and enable ntfsmac.")
        }
        if report.helperInstalled == false {
            return .init(id: "permissions", title: "Permissions", state: .attention, summary: "Approval needed", explanation: "macOS has not yet approved ntfsmac's drive-access component.", nextAction: "Open System Settings > General > Login Items and allow ntfsmac.")
        }
        if fullDiskAccessGranted == nil, mountState == .idle, detectedDriveCount == 0 {
            return .init(
                id: "permissions",
                title: "Permissions",
                state: .idle,
                summary: "Checked when needed",
                explanation: "Connect a supported drive and ntfsmac will verify Full Disk Access before mounting.",
                nextAction: nil
            )
        }
        guard fullDiskAccessGranted == true, report.helperInstalled == true else {
            return .init(id: "permissions", title: "Permissions", state: .unavailable, summary: "Could not confirm", explanation: "ntfsmac could not confirm every macOS permission it needs.", nextAction: "Review ntfsmac in System Settings, then run Diagnose again.")
        }
        return .init(id: "permissions", title: "Permissions", state: .ok, summary: "Ready", explanation: "macOS permissions required for drive access are enabled.", nextAction: nil)
    }

    private static func supportedMacOS(_ value: String?) -> Bool {
        guard let value, let major = Int(value.split(separator: ".").first ?? "") else { return false }
        return major >= 13
    }

    private static func unsupportedMacOS(_ value: String?) -> Bool {
        guard let value, let major = Int(value.split(separator: ".").first ?? "") else { return false }
        return major < 13
    }
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
        if let transport = transportRow(
            helper: report.networkHelper,
            contract: report.nfsTransportContract
        ) {
            rows.append(transport)
        }
        rows.append(contentsOf: mountAttemptRows(report))
        rows.append(contentsOf: securityRows(report))
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
        case .mountedReadWrite, .mountedReadOnly, .mountedReadOnlyDirty, .mountedUnknown:
            return .init(id: "bridge", label: "vmnet bridge", value: "Inactive while a drive is mounted", status: .warning, explanation: explanation)
        case .error, .none:
            return .init(id: "bridge", label: "vmnet bridge", value: "Inactive — mount context unavailable", status: .unavailable, explanation: explanation)
        }
    }

    private static func transportRow(
        helper: String?,
        contract: String?
    ) -> DiagnoseSummaryRow? {
        guard helper != nil || contract != nil else { return nil }
        let explanation = "Whether an active NFS mount uses ntfsmac's required vmnet private transport. Values are fixed privacy-safe tokens; addresses and interface names are omitted."
        switch contract {
        case "expected_vmnet":
            return .init(id: "transport", label: "NFS transport", value: "Private vmnet path", status: .healthy, explanation: explanation)
        case "inactive":
            return .init(id: "transport", label: "NFS transport", value: "Idle", status: .informational, explanation: explanation)
        case "loopback_proxy":
            return .init(id: "transport", label: "NFS transport", value: "Unexpected loopback proxy", status: .warning, explanation: explanation)
        case "ambiguous":
            return .init(id: "transport", label: "NFS transport", value: "Ambiguous helpers", status: .warning, explanation: explanation)
        case "unverified":
            return .init(id: "transport", label: "NFS transport", value: "Unverified", status: .warning, explanation: explanation)
        default:
            return .init(id: "transport", label: "NFS transport", value: "Unknown", status: .unavailable, explanation: explanation)
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

    private static func mountAttemptRows(_ report: DiagnoseReport) -> [DiagnoseSummaryRow] {
        var rows: [DiagnoseSummaryRow] = []
        if let driver = report.selectedFSDriver {
            let value: String
            let status: DiagnoseStatus
            switch driver {
            case "ntfs-3g": value = "ntfs-3g · compatibility default"; status = .informational
            case "ntfs3": value = "NTFS3 · experimental"; status = .informational
            case "ext": value = "Linux ext"; status = .informational
            case "none": value = "No mount attempt"; status = .informational
            default: value = "Unknown"; status = .unavailable
            }
            rows.append(.init(
                id: "mount_driver",
                label: "Mount driver",
                value: value,
                status: status,
                explanation: "Driver selected for the latest mount attempt. NTFS3 is always explicit and never falls back automatically to ntfs-3g."
            ))
        }
        if let failure = report.mountFailureCategory {
            let value: String
            let status: DiagnoseStatus
            switch failure {
            case "none": value = "Succeeded"; status = .healthy
            case "in_progress": value = "In progress"; status = .informational
            case "invalid_request": value = "Invalid request"; status = .warning
            case "runtime_unavailable": value = "Runtime unavailable"; status = .warning
            case "unsafe_windows_state": value = "Unsafe Windows state"; status = .warning
            case "backend_failed": value = "Backend failed"; status = .warning
            case "backend_timeout": value = "Backend timed out"; status = .warning
            case "mount_not_observed": value = "Mount not observed"; status = .warning
            default: value = "Unknown"; status = .unavailable
            }
            rows.append(.init(
                id: "mount_result",
                label: "Latest mount",
                value: value,
                status: status,
                explanation: "Privacy-safe result category for the latest mount attempt; device names, paths, labels, and backend output are omitted."
            ))
        }
        return rows
    }

    private static func securityRows(_ report: DiagnoseReport) -> [DiagnoseSummaryRow] {
        let fields: [(String, String, String?, String?)] = [
            ("security_private", "Private VM link", report.securityPrivateLink, report.securityPrivateReason),
            ("security_route", "VPN-safe route", report.securityVPNRoute, report.securityVPNRouteReason),
            ("security_pf", "PF policy enforced", report.securityPFPolicy, report.securityPFReason),
        ]
        return fields.compactMap { id, label, rawState, reason in
            guard rawState != nil || reason != nil else { return nil }
            let value: String
            let status: DiagnoseStatus
            switch rawState {
            case "enforced": value = "Enforced"; status = .healthy
            case "notRequired": value = "Not required"; status = .informational
            case "notEnforced": value = "Not enforced"; status = .warning
            default: value = "Unknown"; status = .unavailable
            }
            let safeReason = reason?.isEmpty == false ? reason! : "STATUS_UNAVAILABLE"
            return .init(
                id: id,
                label: label,
                value: "\(value) · \(safeReason)",
                status: status,
                explanation: "Measured security state published by the privileged mount transaction. The reason is a fixed privacy-safe code; device, volume, network, and VPN identity are omitted."
            )
        }
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
    public let detectedDriveCount: Int?
    public let fullDiskAccessGranted: Bool?
    public let onHide: (() -> Void)?

    public init(runner: DiagnoseRunner) {
        self.runner = runner
        self.mountState = nil
        self.detectedDriveCount = nil
        self.fullDiskAccessGranted = nil
        self.onHide = nil
    }

    public init(runner: DiagnoseRunner, onHide: @escaping () -> Void) {
        self.runner = runner
        self.mountState = nil
        self.detectedDriveCount = nil
        self.fullDiskAccessGranted = nil
        self.onHide = onHide
    }

    public init(
        runner: DiagnoseRunner,
        mountState: MountState?,
        detectedDriveCount: Int? = nil,
        fullDiskAccessGranted: Bool? = nil,
        onHide: (() -> Void)? = nil
    ) {
        self.runner = runner
        self.mountState = mountState
        self.detectedDriveCount = detectedDriveCount
        self.fullDiskAccessGranted = fullDiskAccessGranted
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
                        .ntfsmacKeyboardFocus()
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Hide diagnostics")
                        .help("Hide the diagnostic panel")
                }
            }

            Group {
                if runner.isRunning {
                    macroRows(DiagnoseMacroSummary.checkingRows)
                } else if let report = runner.report {
                    macroRows(DiagnoseMacroSummary.rows(
                        for: report,
                        mountState: mountState,
                        detectedDriveCount: detectedDriveCount,
                        fullDiskAccessGranted: fullDiskAccessGranted
                    ))
                } else if let errorMessage = runner.errorMessage {
                    macroRows([DiagnoseMacroSummary.failureRow(errorMessage)])
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

    private func macroRows(_ rows: [DiagnoseMacroRow]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.state.symbolName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(color(for: row.state))
                        .frame(width: 16, height: 17)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(row.title)
                                .font(.system(size: 11.5, weight: .semibold))
                            Spacer(minLength: 5)
                            Text(row.state.label.uppercased())
                                .font(.system(size: 8.5, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(color(for: row.state))
                        }
                        Text(row.summary)
                            .font(.system(size: 11, weight: .medium))
                        Text(row.explanation)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let nextAction = row.nextAction {
                            Text(nextAction)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(color(for: row.state))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color(for: row.state).opacity(row.state == .idle || row.state == .unavailable ? 0.04 : 0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(color(for: row.state).opacity(0.12), lineWidth: 1)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.userFacingText)
            }
        }
    }

    private func color(for state: DiagnoseMacroState) -> Color {
        switch state {
        case .idle, .unavailable: .secondary
        case .checking: .ntfsBlue
        case .ok: .ntfsGreen
        case .attention: .ntfsYellow
        case .failed: .ntfsRed
        }
    }
}
