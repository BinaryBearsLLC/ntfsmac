import Foundation
import Testing
import HelperShared
@testable import NtfsmacGUI

// GUI-PLAN.md v1 feature 7. Acceptance: parse sample `diagnose --json` output (healthy +
// degraded) into summary rows. Sample JSON matches `cli/commands/diagnose.sh`'s real emit line
// exactly (field names/types), not invented.

private let healthyJSON = """
{"healthy":true,"missing_binaries":0,"quarantined_binaries":0,"kernel_pin":"match","bridge":"up"}
"""

private let degradedJSON = """
{"healthy":false,"missing_binaries":2,"quarantined_binaries":1,"kernel_pin":"mismatch","bridge":"down"}
"""

private let expandedJSON = """
{"diagnostic_schema":5,"healthy":true,"ntfsmac_version":"1.0","build_version":"1","macos_version":"26.6","architecture":"arm64","helper_installed":true,"missing_binaries":0,"missing_components":[],"quarantined_binaries":0,"quarantined_components":[],"kernel_pin":"match","anylinuxfs_version":"0.18.0","anylinuxfs_expected_version":"0.18.0","anylinuxfs_version_status":"match","anylinuxfs_source_commit":"8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3","vmproxy_source_version":"0.18.0","libkrun_version":"1.19.3","libkrunfw_version":"v6.12.62-rev1","gvproxy_version":"v0.8.9","gvproxy_expected_version":"v0.8.9","gvproxy_version_status":"match","gvproxy_source_commit":"9cfc86f66679ef0feed0f20ba1df558fe2bef5c6","vmnet_helper_version":"v0.12.0","vmnet_helper_expected_version":"v0.12.0","vmnet_helper_version_status":"match","vmnet_helper_source_commit":"0caef043005c7d9f03422a9914bc9d3d4637dc84","alpine_runtime_tag":"3.23.5","alpine_runtime_digest":"sha256:d858bb5442632a31bd4bca6c5e601dbe6b536fd7942092ea6a08a0a95805693c","alpine_runtime_state":"initialized","alpine_installed_cache":"pinned","alpine_installed_version":"3.23.5","ntfs_3g_version":"2026.2.25-r0","nfs_utils_version":"2.6.4-r6","bridge":"up","network_helper":"vmnet","nfs_transport_contract":"expected_vmnet","vpn_default_route":true,"nfs_mount_count":1}
"""

private let developerExportJSON = """
{"diagnostic_schema":5,"healthy":false,"ntfsmac_version":"1.0","build_version":"1","macos_version":"26.5","architecture":"arm64","helper_installed":true,"missing_binaries":1,"missing_components":["vmproxy"],"quarantined_binaries":0,"quarantined_components":[],"kernel_pin":"match","anylinuxfs_version":"0.18.0","anylinuxfs_expected_version":"0.18.0","anylinuxfs_version_status":"match","anylinuxfs_source_commit":"8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3","vmproxy_source_version":"0.18.0","libkrun_version":"1.19.3","libkrunfw_version":"v6.12.62-rev1","gvproxy_version":"v0.8.9","gvproxy_expected_version":"v0.8.9","gvproxy_version_status":"match","gvproxy_source_commit":"9cfc86f66679ef0feed0f20ba1df558fe2bef5c6","vmnet_helper_version":"v0.12.0","vmnet_helper_expected_version":"v0.12.0","vmnet_helper_version_status":"match","vmnet_helper_source_commit":"0caef043005c7d9f03422a9914bc9d3d4637dc84","alpine_runtime_tag":"3.23.5","alpine_runtime_digest":"sha256:d858bb5442632a31bd4bca6c5e601dbe6b536fd7942092ea6a08a0a95805693c","alpine_runtime_state":"not_initialized","alpine_installed_cache":"none","alpine_installed_version":"not_installed","ntfs_3g_version":"not_installed","nfs_utils_version":"not_installed","bridge":"down","network_helper":"none","nfs_transport_contract":"inactive","vpn_default_route":false,"nfs_mount_count":0}
"""

private final class FakeRunner: PrivilegedCommandRunning {
    var result = CommandResult(output: healthyJSON, exitCode: 0)
    private(set) var calls: [(String, [String])] = []

    func run(_ executablePath: String, _ arguments: [String]) -> CommandResult {
        calls.append((executablePath, arguments))
        return result
    }

    func runPipingStdin(_ input: String, to executablePath: String, _ arguments: [String]) -> CommandResult {
        CommandResult(output: "", exitCode: 0)
    }
}

@Test func healthyReportProducesAllHealthyRows() {
    let report = try! JSONDecoder().decode(DiagnoseReport.self, from: Data(healthyJSON.utf8))
    let rows = DiagnoseSummary.rows(for: report)

    #expect(rows.count == 4)
    #expect(rows.allSatisfy { $0.isHealthy })
    #expect(rows.first(where: { $0.id == "binaries" })?.value == "All present")
    #expect(rows.first(where: { $0.id == "kernel" })?.value == "Match")
    #expect(rows.first(where: { $0.id == "bridge" })?.value == "Active")
}

@Test func degradedReportProducesUnhealthyRowsWithCounts() {
    let report = try! JSONDecoder().decode(DiagnoseReport.self, from: Data(degradedJSON.utf8))
    let rows = DiagnoseSummary.rows(for: report)

    #expect(rows.count == 4)
    #expect(rows.first(where: { $0.id == "binaries" })?.value == "2 missing")
    #expect(rows.first(where: { $0.id == "quarantine" })?.value == "1 quarantined")
    #expect(rows.first(where: { $0.id == "kernel" })?.status == .warning)
    #expect(rows.first(where: { $0.id == "bridge" })?.status == .unavailable)
}

@Test func expandedReportProducesPrivacySafeDeveloperRows() throws {
    let report = try JSONDecoder().decode(DiagnoseReport.self, from: Data(expandedJSON.utf8))
    let rows = DiagnoseSummary.rows(for: report)

    #expect(report.diagnosticSchema == 5)
    #expect(rows.map(\.id) == [
        "version", "system", "binaries", "quarantine", "kernel", "anylinuxfs", "virtualization", "alpine", "guest_versions", "network_tools", "bridge", "transport", "helper", "vpn", "mounts",
    ])
    #expect(rows.first(where: { $0.id == "version" })?.value == "1.0 (1)")
    #expect(rows.first(where: { $0.id == "system" })?.value == "macOS 26.6 · arm64")
    #expect(rows.first(where: { $0.id == "helper" })?.value == "Installed")
    #expect(rows.first(where: { $0.id == "anylinuxfs" })?.value == "0.18.0 · 8aa9ccd6504e")
    #expect(rows.first(where: { $0.id == "alpine" })?.value == "3.23.5 · sha256:d858bb544263…")
    #expect(rows.first(where: { $0.id == "guest_versions" })?.value == "Alpine 3.23.5 · ntfs-3g 2026.2.25-r0 · nfs-utils 2.6.4-r6")
    #expect(rows.first(where: { $0.id == "network_tools" })?.value == "gvproxy v0.8.9 · vmnet-helper v0.12.0")
    #expect(rows.first(where: { $0.id == "transport" })?.value == "Private vmnet path")
    #expect(rows.first(where: { $0.id == "vpn" })?.value == "Default route uses a tunnel")
    #expect(rows.first(where: { $0.id == "mounts" })?.value == "1 active")
}

@Test func expandedReportNamesOnlyFixedFailingComponents() throws {
    let report = try JSONDecoder().decode(DiagnoseReport.self, from: Data(developerExportJSON.utf8))
    let rows = DiagnoseSummary.rows(for: report)

    #expect(rows.first(where: { $0.id == "binaries" })?.value == "Missing: vmproxy")
    #expect(rows.first(where: { $0.id == "quarantine" })?.value == "Clear")
}

@Test func expandedSystemRowWarnsForUnsupportedHost() {
    let report = DiagnoseReport(
        healthy: false,
        missingBinaries: 0,
        quarantinedBinaries: 0,
        kernelPin: "match",
        bridge: "down",
        diagnosticSchema: 2,
        ntfsmacVersion: "1.0",
        buildVersion: "1",
        macosVersion: "12.6",
        architecture: "arm64",
        helperInstalled: true,
        missingComponents: [],
        quarantinedComponents: [],
        vpnDefaultRoute: false,
        nfsMountCount: 0
    )

    #expect(DiagnoseSummary.rows(for: report).first(where: { $0.id == "system" })?.status == .warning)
}

@Test(arguments: ["match", "mismatch", "missing", "unknown", "malformed"])
func kernelPinRawValuesAreRepresentedHonestly(rawValue: String) {
    let report = DiagnoseReport(healthy: false, missingBinaries: 0, quarantinedBinaries: 0, kernelPin: rawValue, bridge: "up")
    let row = DiagnoseSummary.rows(for: report).first { $0.id == "kernel" }!

    let expected: DiagnoseStatus = rawValue == "match" ? .healthy : (["mismatch", "missing"].contains(rawValue) ? .warning : .unavailable)
    #expect(row.status == expected)
    #expect((rawValue == "unknown" || rawValue == "malformed") ? row.value == "Unknown" : true)
}

@Test(arguments: [
    (MountState.idle, DiagnoseStatus.informational, "Idle — starts when a drive is mounted"),
    (.mounting, .informational, "Starting with the mount"),
    (.mountedReadWrite, .warning, "Inactive while a drive is mounted"),
    (.mountedReadOnly, .warning, "Inactive while a drive is mounted"),
    (.mountedReadOnlyDirty, .warning, "Inactive while a drive is mounted"),
    (.error, .unavailable, "Inactive — mount context unavailable"),
])
func bridgeDownUsesMountContext(argument: (MountState, DiagnoseStatus, String)) {
    let report = DiagnoseReport(healthy: true, missingBinaries: 0, quarantinedBinaries: 0, kernelPin: "match", bridge: "down")
    let row = DiagnoseSummary.rows(for: report, mountState: argument.0).first { $0.id == "bridge" }!

    #expect(row.status == argument.1)
    #expect(row.value == argument.2)
}

@Test func bridgeDownWithoutKnownMountContextIsNeutralRatherThanWarning() {
    let report = DiagnoseReport(healthy: true, missingBinaries: 0, quarantinedBinaries: 0, kernelPin: "match", bridge: "down")
    let row = DiagnoseSummary.rows(for: report).first { $0.id == "bridge" }!

    #expect(row.status == .unavailable)
    #expect(!row.isHealthy)
}

@Test func malformedCountsAndBridgeAreUnavailable() {
    let report = DiagnoseReport(healthy: false, missingBinaries: -1, quarantinedBinaries: -1, kernelPin: "match", bridge: "starting")
    let rows = DiagnoseSummary.rows(for: report, mountState: .mountedReadWrite)

    #expect(rows.first { $0.id == "binaries" }?.status == .unavailable)
    #expect(rows.first { $0.id == "quarantine" }?.status == .unavailable)
    #expect(rows.first { $0.id == "bridge" }?.status == .unavailable)
}

@MainActor
@Test func runParsesRealCommandOutputIntoReport() async {
    let fake = FakeRunner()
    fake.result = CommandResult(output: degradedJSON, exitCode: 0)
    let runner = DiagnoseRunner(runner: fake, ntfsmacPath: "/fake/ntfsmac", fileExists: { _ in true })

    await runner.run()

    #expect(fake.calls.count == 1)
    #expect(fake.calls[0].0 == "/fake/ntfsmac")
    #expect(fake.calls[0].1 == ["diagnose", "--json"])
    #expect(runner.report?.healthy == false)
    #expect(runner.errorMessage == nil)
}

@MainActor
@Test func developerExportReusesDiagnoseJsonAndWorksForDegradedExitStatus() async throws {
    let fake = FakeRunner()
    fake.result = CommandResult(output: developerExportJSON, exitCode: 1)
    let runner = DiagnoseRunner(runner: fake, ntfsmacPath: "/fake/ntfsmac", fileExists: { _ in true })

    let document = await runner.runForDeveloperExport()

    #expect(fake.calls.count == 1)
    #expect(fake.calls[0].1 == ["diagnose", "--json"])
    #expect(runner.report?.healthy == false)
    #expect(runner.errorMessage == nil)
    #expect(document != nil)
    let object = try JSONSerialization.jsonObject(with: document!.data) as? [String: Any]
    #expect(object?["diagnostic_schema"] as? Int == 5)
    #expect(object?["ntfsmac_version"] as? String == "1.0")
    #expect(object?["macos_version"] as? String == "26.5")
    #expect(object?["missing_components"] as? [String] == ["vmproxy"])
    #expect(object?["anylinuxfs_version"] as? String == "0.18.0")
    #expect(object?["ntfs_3g_version"] as? String == "not_installed")
    #expect(object?["network_helper"] as? String == "none")
    #expect(object?["nfs_transport_contract"] as? String == "inactive")
}

@MainActor
@Test func runSurfacesErrorOnUnparseableOutput() async {
    let fake = FakeRunner()
    fake.result = CommandResult(output: "diagnose: command not found", exitCode: 127)
    let runner = DiagnoseRunner(runner: fake, ntfsmacPath: "/fake/ntfsmac", fileExists: { _ in true })

    await runner.run()

    #expect(runner.report == nil)
    #expect(runner.errorMessage == "diagnose: command not found")
}

@MainActor
@Test func runSurfacesPlainLanguageErrorWhenBinaryIsMissingWithoutRunningAnything() async {
    // Real bug (reported, reproduces on real hardware, not VM-specific): tapping Diagnose
    // before the CLI is staged used to surface a raw `NSCocoaErrorDomain Code=4 "The file ...
    // doesn't exist."` string verbatim. This is the fix's behavior contract: no raw Cocoa error,
    // and the runner must never even be invoked against a binary that isn't there.
    let fake = FakeRunner()
    let runner = DiagnoseRunner(runner: fake, ntfsmacPath: "/fake/ntfsmac", fileExists: { _ in false })

    await runner.run()

    #expect(fake.calls.isEmpty, "must never shell out to a binary confirmed missing")
    #expect(runner.report == nil)
    #expect(runner.errorMessage?.contains("NSCocoaErrorDomain") == false)
    #expect(runner.errorMessage == "ntfsmac isn't installed yet. If you just installed the helper, this can take a few seconds — try again, or use Preferences ▸ Reinstall privileged helper.")
}

@Test func diagnosticPresentationCoversHiddenRunningResultAndErrorPhases() {
    let report = DiagnoseReport(healthy: true, missingBinaries: 0, quarantinedBinaries: 0, kernelPin: "match", bridge: "up")
    var presentation = DiagnosePanelPresentation()

    #expect(presentation.phase(report: report, errorMessage: "failure", isRunning: true) == .hidden)
    presentation.show()
    #expect(presentation.phase(report: nil, errorMessage: nil, isRunning: true) == .running)
    #expect(presentation.phase(report: report, errorMessage: nil, isRunning: false) == .result)
    #expect(presentation.phase(report: nil, errorMessage: "failure", isRunning: false) == .error)
    presentation.hide()
    #expect(presentation.phase(report: report, errorMessage: nil, isRunning: false) == .hidden)
}

@MainActor
@Test func hidingKeepsDiagnosticDataAndReopeningRunsExactlyOnceAgain() async {
    let fake = FakeRunner()
    let runner = DiagnoseRunner(runner: fake, ntfsmacPath: "/fake/ntfsmac", fileExists: { _ in true })
    var presentation = DiagnosePanelPresentation()

    presentation.show()
    await runner.run()
    #expect(fake.calls.count == 1)
    let firstReport = runner.report

    presentation.hide()
    #expect(!presentation.isVisible)
    #expect(runner.report == firstReport)

    presentation.show()
    await runner.run()
    #expect(presentation.isVisible)
    #expect(fake.calls.count == 2)
    #expect(runner.report == firstReport)
}
