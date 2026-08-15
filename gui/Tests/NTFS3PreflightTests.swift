import Testing
@testable import NtfsmacGUI

@Test func ntfs3PreflightIsExplicitAndNeverSuggestsSilentFallback() {
    #expect(NTFS3PreflightCopy.title.contains("Experimental"))
    #expect(NTFS3PreflightCopy.guidance.contains("Fast Startup"))
    #expect(NTFS3PreflightCopy.guidance.contains("fully shut down"))
    #expect(NTFS3PreflightCopy.guidance.contains("chkdsk"))
    #expect(NTFS3PreflightCopy.guidance.contains("Symbolic links"))
    #expect(NTFS3PreflightCopy.guidance.contains("no automatic fallback"))
    #expect(!NTFS3PreflightCopy.guidance.contains("ntfsfix"))
    #expect(NTFS3PreflightCopy.isAvailable(for: "ntfs"))
    #expect(!NTFS3PreflightCopy.isAvailable(for: "BitLocker"))
    #expect(!NTFS3PreflightCopy.isAvailable(for: "ext4"))
}
