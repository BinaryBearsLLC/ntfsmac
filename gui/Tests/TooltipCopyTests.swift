import Testing
@testable import NtfsmacGUI

@Test(arguments: TooltipCopy.Control.allCases)
func everyTooltipControlHasConciseCopy(control: TooltipCopy.Control) {
    let copy = TooltipCopy.text(for: control)

    #expect(!copy.isEmpty)
    #expect(copy.count <= 80)
    #expect(!copy.hasSuffix("."))
}

@Test(arguments: [
    (MountState.idle, "Idle — no supported drive is mounted"),
    (.mounting, "Mount in progress"),
    (.mountedReadWrite, "All mounted drives are read/write"),
    (.mountedReadOnly, "At least one mounted drive is read-only"),
    (.mountedReadOnlyDirty, "At least one mounted NTFS drive has an unclean journal"),
    (.mountedUnknown, "Mounted state needs independent host verification"),
    (.error, "ntfsmac needs attention"),
])
func everyMountStateHasDistinctStatusHelp(argument: (MountState, String)) {
    #expect(TooltipCopy.status(for: argument.0) == argument.1)
}

@Test func diagnosticHelpCoversEverySummaryRow() {
    let report = DiagnoseReport(healthy: true, missingBinaries: 0, quarantinedBinaries: 0, kernelPin: "match", bridge: "up")
    let rows = DiagnoseSummary.rows(for: report)
    let explanations = rows.map { TooltipCopy.diagnosticExplanation(for: $0.id) }

    #expect(explanations.count == rows.count)
    #expect(explanations.allSatisfy { !$0.isEmpty && $0 != "Diagnostic status" })
}
