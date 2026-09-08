import Foundation
import Testing
@testable import NtfsmacGUI

private enum FakeReleaseError: Error { case offline }

private final class CountingReleaseClient: LatestReleaseFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<PublishedRelease, Error>
    private var storedCount = 0

    init(_ result: Result<PublishedRelease, Error>) {
        self.result = result
    }

    func fetchLatestRelease() async throws -> PublishedRelease {
        lock.withLock { storedCount += 1 }
        return try result.get()
    }

    var count: Int { lock.withLock { storedCount } }
}

private func updateDefaults() -> UserDefaults {
    let suite = "com.binarybears.ntfsmac.tests.updates.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
@Test(arguments: [true, false])
func sameVersionStableReleaseReplacesOnlyAPrerelease(isBeta: Bool) async {
    let release = PublishedRelease(version: SemanticVersion(tag: "3.1.3")!,
        pageURL: URL(string: "https://github.com/BinaryBearsLLC/ntfsmac/releases/tag/v3.1.3")!)
    let checker = UpdateChecker(client: CountingReleaseClient(.success(release)),
        defaults: updateDefaults(), isPrerelease: isBeta)
    await checker.checkManually(currentVersion: "3.1.3")
    #expect(checker.state == (isBeta ? .updateAvailable(release) : .upToDate))
}

@Test func semanticVersionsAreStrictAndComparable() {
    #expect(SemanticVersion(tag: "v3.0.1")! > SemanticVersion(tag: "3.0.0")!)
    #expect(SemanticVersion(tag: "3.1.0")! > SemanticVersion(tag: "3.0.99")!)
    #expect(SemanticVersion(tag: "3.1.1")! > SemanticVersion(tag: "3.1.0")!)
    #expect(SemanticVersion(tag: "3.0") == nil)
    #expect(SemanticVersion(tag: "3.0.0-beta") == nil)
    #expect(SemanticVersion(tag: "03.0.0") == nil)
}

@MainActor
@Test func manualCheckReportsAndOpensANewerGitHubRelease() async {
    let page = URL(string: "https://github.com/BinaryBearsLLC/ntfsmac/releases/tag/v3.0.1")!
    let release = PublishedRelease(version: SemanticVersion(tag: "3.0.1")!, pageURL: page)
    let client = CountingReleaseClient(.success(release))
    var openedURL: URL?
    let checker = UpdateChecker(
        client: client,
        defaults: updateDefaults(),
        openURL: { openedURL = $0; return true }
    )

    await checker.checkManually(currentVersion: "3.0.0")

    #expect(checker.state == .updateAvailable(release))
    #expect(checker.openAvailableRelease())
    #expect(openedURL == page)
    #expect(client.count == 1)
}

@MainActor
@Test func automaticCheckRunsAtMostOncePerDay() async {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let release = PublishedRelease(
        version: SemanticVersion(tag: "3.0.0")!,
        pageURL: URL(string: "https://github.com/BinaryBearsLLC/ntfsmac/releases/tag/v3.0.0")!
    )
    let client = CountingReleaseClient(.success(release))
    let checker = UpdateChecker(client: client, defaults: updateDefaults(), now: { now })

    await checker.checkAutomaticallyIfNeeded(currentVersion: "3.0.0")
    await checker.checkAutomaticallyIfNeeded(currentVersion: "3.0.0")

    #expect(client.count == 1)
    #expect(checker.state == .idle)
}

@MainActor
@Test func automaticNetworkFailureIsSilentButManualFailureIsVisible() async {
    let client = CountingReleaseClient(.failure(FakeReleaseError.offline))
    let checker = UpdateChecker(client: client, defaults: updateDefaults())

    await checker.checkAutomaticallyIfNeeded(currentVersion: "3.0.0")
    #expect(checker.state == .idle)

    await checker.checkManually(currentVersion: "3.0.0")
    #expect(checker.state == .failed("Could not check GitHub Releases."))
}

@MainActor
@Test func manualUpToDateAcknowledgementReturnsToIdleWithoutLayoutChange() async {
    let release = PublishedRelease(
        version: SemanticVersion(tag: "3.1.0")!,
        pageURL: URL(string: "https://github.com/BinaryBearsLLC/ntfsmac/releases/tag/v3.1.0")!
    )
    let checker = UpdateChecker(
        client: CountingReleaseClient(.success(release)),
        defaults: updateDefaults(),
        successAcknowledgementDuration: .milliseconds(10)
    )

    await checker.checkManually(currentVersion: "3.1.0")
    #expect(checker.state == .upToDate)
    // A loaded CI runner may not schedule the reset task within 30 ms.
    // Wait for the observable transition, with a bounded failure deadline.
    let deadline = ContinuousClock.now.advanced(by: .seconds(2))
    while checker.state == .upToDate && ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(checker.state == .idle)
}
