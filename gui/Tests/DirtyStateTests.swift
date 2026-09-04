import Testing
@testable import NtfsmacGUI

@Suite struct ReadOnlyReasonTests {
    @Test func requestedReadOnlyNeedsNoWarning() {
        #expect(DirtyBanner.copy(for: .requested) == nil)
    }

    @Test(arguments: [
        ReadOnlyReason.windowsDirty,
        .windowsHibernated,
        .unsafeWindowsState,
        .readOnlyMedia,
        .unsupportedWriteMode,
        .unknown,
    ])
    func unexpectedReadOnlyReasonsHaveConciseGuidance(reason: ReadOnlyReason) {
        let copy = DirtyBanner.copy(for: reason)

        #expect(copy != nil)
        #expect(copy?.title.isEmpty == false)
        #expect(copy?.message.isEmpty == false)
        #expect(copy?.message.contains("Mount read/write anyway") == false)
    }

    @Test func windowsReasonsAndUnknownReasonStayDistinct() {
        #expect(ReadOnlyReason.windowsDirty.requiresWindowsRepair)
        #expect(ReadOnlyReason.windowsHibernated.requiresWindowsRepair)
        #expect(ReadOnlyReason.unsafeWindowsState.requiresWindowsRepair)
        #expect(!ReadOnlyReason.unknown.requiresWindowsRepair)
        #expect(ReadOnlyReason.unknown.requiresAttention)
    }

    @Test func explicitWindowsEvidenceWinsAcrossMultipleMountedDrives() {
        #expect(DirtyBanner.preferredReason(
            among: [.unknown, .requested, .windowsHibernated]
        ) == .windowsHibernated)
    }
}
