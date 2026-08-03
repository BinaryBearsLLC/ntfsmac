import Testing
@testable import NtfsmacGUI

// No-drives copy must reflect that the app supports NTFS *and* ext (ext2/3/4 list support
// landed in 1be5bf2). Mirrors the `DirtyBanner.bannerCopy` pattern: extract user-facing copy
// into a testable constant so a string change is covered without rendering an image (which
// `PopoverStateRenderTests` can't grep).
@Suite struct EmptyStateCopyTests {

    @Test func titleMentionsNtfsAndExt() {
        let title = EmptyStateCopy.title
        #expect(title.contains("NTFS"), "title must mention NTFS — got: \(title)")
        #expect(title.lowercased().contains("ext"), "title must mention ext — got: \(title)")
    }

    @Test func subtitleMentionsNtfsAndExt() {
        let subtitle = EmptyStateCopy.subtitle
        #expect(subtitle.contains("NTFS") || subtitle.lowercased().contains("ntfs"), "subtitle must mention NTFS — got: \(subtitle)")
        #expect(subtitle.lowercased().contains("ext"), "subtitle must mention ext — got: \(subtitle)")
    }
}