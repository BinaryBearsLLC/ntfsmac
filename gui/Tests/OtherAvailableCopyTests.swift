import Testing
@testable import NtfsmacGUI

// "Other available drives" section split (PopoverContentView): before anything is mounted the
// detected drives are just "the drives", not "other" — nothing is primary yet, so the labeled
// section must not appear. Once one drive is mounted, the "Other available devices" header +
// small Refresh button render below the mounted list (above security) and STAY rendered even
// when no unmounted drive is currently listed — the Refresh button must stay accessible so the
// user can re-scan for newly connected drives without unmounting first. The per-drive rows render
// only when unmounted drives are actually detected. Mirrors `EmptyStateCopy`: extract the copy +
// the gating decision into testable pure symbols so the behavior is covered without rendering an
// image (which `PopoverStateRenderTests` can't grep for text).

@Suite struct OtherAvailableCopyTests {
    @Test func labelSaysDevicesNotDrives() {
        let label = OtherAvailableCopy.label
        #expect(label.lowercased().contains("device"), "section header must say 'devices' — got: \(label)")
        #expect(!label.lowercased().contains("drive"), "section header must not say 'drives' — got: \(label)")
    }

    @Test func hiddenWhenIdleEvenWithAvailableDrives() {
        // Before mounting anything: no "other available" section, regardless of how many drives
        // the scanner sees. The drives render as the primary list, not under an "other" header.
        #expect(OtherAvailableSection.shouldRender(isMounted: false) == false)
    }

    @Test func rendersWhenMountedEvenWithNothingElseAvailable() {
        // Mounted: the section (header + Refresh button) must render even when no unmounted drive
        // is currently listed, so the Refresh button stays available to surface newly connected
        // drives. The empty-list case is a header + refresh with no rows, not a hidden section.
        #expect(OtherAvailableSection.shouldRender(isMounted: true) == true)
    }

    @Test func rowsRenderOnlyWhenUnmountedDrivesAvailable() {
        // The header+refresh gate on `shouldRender`; the per-drive rows gate on a non-empty
        // unmounted list. A mounted state with zero other drives shows the header but no rows.
        #expect(OtherAvailableSection.rowsRender(availableCount: 0) == false)
        #expect(OtherAvailableSection.rowsRender(availableCount: 2) == true)
    }
}