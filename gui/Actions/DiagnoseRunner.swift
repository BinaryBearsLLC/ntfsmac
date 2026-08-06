import Foundation
import HelperShared

/// Summary fields decoded from `ntfsmac diagnose --json` (`cli/commands/diagnose.sh`'s `main()`,
/// `json_mode` branch). Fixed runtime identifiers are privacy-safe; paths and cache contents are
/// deliberately absent. `DeveloperDiagnoseDocument` preserves the complete raw JSON for support.
public struct DiagnoseReport: Codable, Equatable, Sendable {
    public let diagnosticSchema: Int?
    public let healthy: Bool
    public let ntfsmacVersion: String?
    public let buildVersion: String?
    public let macosVersion: String?
    public let architecture: String?
    public let helperInstalled: Bool?
    public let missingBinaries: Int
    public let missingComponents: [String]?
    public let quarantinedBinaries: Int
    public let quarantinedComponents: [String]?
    public let kernelPin: String
    public let anylinuxfsVersion: String?
    public let anylinuxfsExpectedVersion: String?
    public let anylinuxfsVersionStatus: String?
    public let anylinuxfsSourceCommit: String?
    public let vmproxySourceVersion: String?
    public let libkrunVersion: String?
    public let libkrunfwVersion: String?
    public let gvproxyVersion: String?
    public let gvproxyExpectedVersion: String?
    public let gvproxyVersionStatus: String?
    public let gvproxySourceCommit: String?
    public let vmnetHelperVersion: String?
    public let vmnetHelperExpectedVersion: String?
    public let vmnetHelperVersionStatus: String?
    public let vmnetHelperSourceCommit: String?
    public let alpineRuntimeTag: String?
    public let alpineRuntimeDigest: String?
    public let alpineRuntimeState: String?
    public let alpineInstalledCache: String?
    public let alpineInstalledVersion: String?
    public let ntfs3gVersion: String?
    public let nfsUtilsVersion: String?
    public let bridge: String
    public let networkHelper: String?
    public let nfsTransportContract: String?
    public let vpnDefaultRoute: Bool?
    public let nfsMountCount: Int?

    enum CodingKeys: String, CodingKey {
        case diagnosticSchema = "diagnostic_schema"
        case healthy
        case ntfsmacVersion = "ntfsmac_version"
        case buildVersion = "build_version"
        case macosVersion = "macos_version"
        case architecture
        case helperInstalled = "helper_installed"
        case missingBinaries = "missing_binaries"
        case missingComponents = "missing_components"
        case quarantinedBinaries = "quarantined_binaries"
        case quarantinedComponents = "quarantined_components"
        case kernelPin = "kernel_pin"
        case anylinuxfsVersion = "anylinuxfs_version"
        case anylinuxfsExpectedVersion = "anylinuxfs_expected_version"
        case anylinuxfsVersionStatus = "anylinuxfs_version_status"
        case anylinuxfsSourceCommit = "anylinuxfs_source_commit"
        case vmproxySourceVersion = "vmproxy_source_version"
        case libkrunVersion = "libkrun_version"
        case libkrunfwVersion = "libkrunfw_version"
        case gvproxyVersion = "gvproxy_version"
        case gvproxyExpectedVersion = "gvproxy_expected_version"
        case gvproxyVersionStatus = "gvproxy_version_status"
        case gvproxySourceCommit = "gvproxy_source_commit"
        case vmnetHelperVersion = "vmnet_helper_version"
        case vmnetHelperExpectedVersion = "vmnet_helper_expected_version"
        case vmnetHelperVersionStatus = "vmnet_helper_version_status"
        case vmnetHelperSourceCommit = "vmnet_helper_source_commit"
        case alpineRuntimeTag = "alpine_runtime_tag"
        case alpineRuntimeDigest = "alpine_runtime_digest"
        case alpineRuntimeState = "alpine_runtime_state"
        case alpineInstalledCache = "alpine_installed_cache"
        case alpineInstalledVersion = "alpine_installed_version"
        case ntfs3gVersion = "ntfs_3g_version"
        case nfsUtilsVersion = "nfs_utils_version"
        case bridge
        case networkHelper = "network_helper"
        case nfsTransportContract = "nfs_transport_contract"
        case vpnDefaultRoute = "vpn_default_route"
        case nfsMountCount = "nfs_mount_count"
    }

    public init(
        healthy: Bool,
        missingBinaries: Int,
        quarantinedBinaries: Int,
        kernelPin: String,
        bridge: String
    ) {
        self.init(
            healthy: healthy,
            missingBinaries: missingBinaries,
            quarantinedBinaries: quarantinedBinaries,
            kernelPin: kernelPin,
            bridge: bridge,
            diagnosticSchema: nil,
            ntfsmacVersion: nil,
            buildVersion: nil,
            macosVersion: nil,
            architecture: nil,
            helperInstalled: nil,
            missingComponents: nil,
            quarantinedComponents: nil,
            networkHelper: nil,
            nfsTransportContract: nil,
            vpnDefaultRoute: nil,
            nfsMountCount: nil,
            anylinuxfsVersion: nil,
            anylinuxfsExpectedVersion: nil,
            anylinuxfsVersionStatus: nil,
            anylinuxfsSourceCommit: nil,
            vmproxySourceVersion: nil,
            libkrunVersion: nil,
            libkrunfwVersion: nil,
            gvproxyVersion: nil,
            gvproxyExpectedVersion: nil,
            gvproxyVersionStatus: nil,
            gvproxySourceCommit: nil,
            vmnetHelperVersion: nil,
            vmnetHelperExpectedVersion: nil,
            vmnetHelperVersionStatus: nil,
            vmnetHelperSourceCommit: nil,
            alpineRuntimeTag: nil,
            alpineRuntimeDigest: nil,
            alpineRuntimeState: nil,
            alpineInstalledCache: nil,
            alpineInstalledVersion: nil,
            ntfs3gVersion: nil,
            nfsUtilsVersion: nil
        )
    }

    public init(
        healthy: Bool,
        missingBinaries: Int,
        quarantinedBinaries: Int,
        kernelPin: String,
        bridge: String,
        diagnosticSchema: Int?,
        ntfsmacVersion: String?,
        buildVersion: String?,
        macosVersion: String?,
        architecture: String?,
        helperInstalled: Bool?,
        missingComponents: [String]?,
        quarantinedComponents: [String]?,
        networkHelper: String? = nil,
        nfsTransportContract: String? = nil,
        vpnDefaultRoute: Bool?,
        nfsMountCount: Int?,
        anylinuxfsVersion: String? = nil,
        anylinuxfsExpectedVersion: String? = nil,
        anylinuxfsVersionStatus: String? = nil,
        anylinuxfsSourceCommit: String? = nil,
        vmproxySourceVersion: String? = nil,
        libkrunVersion: String? = nil,
        libkrunfwVersion: String? = nil,
        gvproxyVersion: String? = nil,
        gvproxyExpectedVersion: String? = nil,
        gvproxyVersionStatus: String? = nil,
        gvproxySourceCommit: String? = nil,
        vmnetHelperVersion: String? = nil,
        vmnetHelperExpectedVersion: String? = nil,
        vmnetHelperVersionStatus: String? = nil,
        vmnetHelperSourceCommit: String? = nil,
        alpineRuntimeTag: String? = nil,
        alpineRuntimeDigest: String? = nil,
        alpineRuntimeState: String? = nil,
        alpineInstalledCache: String? = nil,
        alpineInstalledVersion: String? = nil,
        ntfs3gVersion: String? = nil,
        nfsUtilsVersion: String? = nil
    ) {
        self.diagnosticSchema = diagnosticSchema
        self.healthy = healthy
        self.ntfsmacVersion = ntfsmacVersion
        self.buildVersion = buildVersion
        self.macosVersion = macosVersion
        self.architecture = architecture
        self.helperInstalled = helperInstalled
        self.missingBinaries = missingBinaries
        self.missingComponents = missingComponents
        self.quarantinedBinaries = quarantinedBinaries
        self.quarantinedComponents = quarantinedComponents
        self.kernelPin = kernelPin
        self.anylinuxfsVersion = anylinuxfsVersion
        self.anylinuxfsExpectedVersion = anylinuxfsExpectedVersion
        self.anylinuxfsVersionStatus = anylinuxfsVersionStatus
        self.anylinuxfsSourceCommit = anylinuxfsSourceCommit
        self.vmproxySourceVersion = vmproxySourceVersion
        self.libkrunVersion = libkrunVersion
        self.libkrunfwVersion = libkrunfwVersion
        self.gvproxyVersion = gvproxyVersion
        self.gvproxyExpectedVersion = gvproxyExpectedVersion
        self.gvproxyVersionStatus = gvproxyVersionStatus
        self.gvproxySourceCommit = gvproxySourceCommit
        self.vmnetHelperVersion = vmnetHelperVersion
        self.vmnetHelperExpectedVersion = vmnetHelperExpectedVersion
        self.vmnetHelperVersionStatus = vmnetHelperVersionStatus
        self.vmnetHelperSourceCommit = vmnetHelperSourceCommit
        self.alpineRuntimeTag = alpineRuntimeTag
        self.alpineRuntimeDigest = alpineRuntimeDigest
        self.alpineRuntimeState = alpineRuntimeState
        self.alpineInstalledCache = alpineInstalledCache
        self.alpineInstalledVersion = alpineInstalledVersion
        self.ntfs3gVersion = ntfs3gVersion
        self.nfsUtilsVersion = nfsUtilsVersion
        self.bridge = bridge
        self.networkHelper = networkHelper
        self.nfsTransportContract = nfsTransportContract
        self.vpnDefaultRoute = vpnDefaultRoute
        self.nfsMountCount = nfsMountCount
    }
}

/// `Diagnose` (GUI-PLAN.md v1 feature 7): read-only, reachable from idle + error states — this
/// unit's Do clause. Reuses `HelperShared`'s `PrivilegedCommandRunning`/`RealCommandRunner` seam
/// (same non-privileged-call pattern as `DriveScanner`) since `ntfsmac diagnose` never touches
/// pf/route/mount state (`diagnose.sh`'s own header comment).
@MainActor
public final class DiagnoseRunner: ObservableObject {
    @Published public private(set) var report: DiagnoseReport?
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isRunning = false

    private let runner: any PrivilegedCommandRunning
    private let ntfsmacPath: String
    private let fileExists: (String) -> Bool

    public init(
        runner: any PrivilegedCommandRunning = RealCommandRunner(),
        ntfsmacPath: String = "\(installPrefix)/bin/ntfsmac",
        fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.runner = runner
        self.ntfsmacPath = ntfsmacPath
        self.fileExists = fileExists
    }

    public func run() async {
        _ = execute()
    }

    /// Runs the exact same read-only CLI diagnostic as the visible summary, then returns a
    /// validated, formatted attachment. A degraded diagnosis still produces a useful document:
    /// `diagnose.sh` deliberately uses its exit code for health while keeping stdout valid JSON.
    public func runForDeveloperExport() async -> DeveloperDiagnoseDocument? {
        guard let rawJSON = execute() else { return nil }
        do {
            return try DeveloperDiagnoseDocument(rawJSON: rawJSON)
        } catch {
            report = nil
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func execute() -> String? {
        guard !isRunning else { return nil }
        isRunning = true
        // Clear the previous result up front — otherwise a stale report/error stays on screen
        // for the entire re-diagnose run, and `DiagnosePanel`'s `ProgressView` branch (checked
        // after `report`/`errorMessage`) never becomes reachable past the first run.
        report = nil
        errorMessage = nil
        defer { isRunning = false }

        // Real bug (reported, reproduces on real hardware too, not VM-specific): without this
        // check, a missing binary surfaces `RealCommandRunner`'s raw
        // `NSCocoaErrorDomain Code=4 "The file ... doesn't exist."` text verbatim — happens
        // whenever Diagnose is tapped before `CLIAutoStager`'s background staging finishes (or
        // if it failed). This is a knowable, plain-language case, not a genuine diagnose
        // failure; surfacing the raw Cocoa error was the actual defect, not the missing file
        // itself (staging still being in progress right after a fresh install is expected).
        guard fileExists(ntfsmacPath) else {
            errorMessage = "ntfsmac isn't installed yet. If you just installed the helper, this can take a few seconds — try again, or use Preferences ▸ Reinstall privileged helper."
            return nil
        }

        let result = runner.run(ntfsmacPath, ["diagnose", "--json"])
        guard let data = result.output.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(DiagnoseReport.self, from: data)
        else {
            report = nil
            errorMessage = result.output.isEmpty ? "diagnose produced no output" : result.output
            return nil
        }
        report = parsed
        errorMessage = nil
        return result.output
    }
}
