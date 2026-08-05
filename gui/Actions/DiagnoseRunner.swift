import Foundation
import HelperShared

/// Summary fields decoded from `ntfsmac diagnose --json` (`cli/commands/diagnose.sh`'s `main()`,
/// `json_mode` branch). The CLI also emits `macos_version`; Swift's decoder deliberately ignores
/// that extra field for the four-row UI summary, while `DeveloperDiagnoseDocument` preserves the
/// complete raw JSON for support reports.
public struct DiagnoseReport: Codable, Equatable, Sendable {
    public let healthy: Bool
    public let missingBinaries: Int
    public let quarantinedBinaries: Int
    public let kernelPin: String
    public let bridge: String

    enum CodingKeys: String, CodingKey {
        case healthy
        case missingBinaries = "missing_binaries"
        case quarantinedBinaries = "quarantined_binaries"
        case kernelPin = "kernel_pin"
        case bridge
    }

    public init(healthy: Bool, missingBinaries: Int, quarantinedBinaries: Int, kernelPin: String, bridge: String) {
        self.healthy = healthy
        self.missingBinaries = missingBinaries
        self.quarantinedBinaries = quarantinedBinaries
        self.kernelPin = kernelPin
        self.bridge = bridge
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
