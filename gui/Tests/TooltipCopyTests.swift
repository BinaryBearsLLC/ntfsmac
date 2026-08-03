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
    (.error, "ntfsmac needs attention"),
])
func everyMountStateHasDistinctStatusHelp(argument: (MountState, String)) {
    #expect(TooltipCopy.status(for: argument.0) == argument.1)
}
