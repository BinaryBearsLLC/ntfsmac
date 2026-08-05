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
