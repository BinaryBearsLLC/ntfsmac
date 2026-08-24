import AppKit
import Foundation

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(tag: String) {
        let value = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Self.component(parts[0]),
              let minor = Self.component(parts[1]),
              let patch = Self.component(parts[2])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    private static func component(_ value: Substring) -> Int? {
        guard !value.isEmpty, value.allSatisfy(\.isNumber) else { return nil }
        if value.count > 1, value.first == "0" { return nil }
        return Int(value)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }
}

public struct PublishedRelease: Equatable, Sendable {
    public let version: SemanticVersion
    public let pageURL: URL

    public init(version: SemanticVersion, pageURL: URL) {
        self.version = version
        self.pageURL = pageURL
    }
}

public protocol LatestReleaseFetching: Sendable {
    func fetchLatestRelease() async throws -> PublishedRelease
}

public enum LatestReleaseError: Error {
    case invalidResponse
    case invalidRelease
}

public struct GitHubLatestReleaseClient: LatestReleaseFetching {
    public static let endpoint = URL(
        string: "https://api.github.com/repos/BinaryBearsLLC/ntfsmac/releases/latest"
    )!

    public init() {}

    public func fetchLatestRelease() async throws -> PublishedRelease {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 10
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ntfsmac/3", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LatestReleaseError.invalidResponse
        }
        let payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
        guard !payload.draft,
              !payload.prerelease,
              let version = SemanticVersion(tag: payload.tagName),
              payload.pageURL.scheme == "https",
              payload.pageURL.host == "github.com"
        else { throw LatestReleaseError.invalidRelease }
        return PublishedRelease(version: version, pageURL: payload.pageURL)
    }
}

private struct GitHubReleasePayload: Decodable {
    let tagName: String
    let pageURL: URL
    let draft: Bool
    let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case pageURL = "html_url"
        case draft
        case prerelease
    }
}

public enum UpdateCheckState: Equatable, Sendable {
    case idle
    case checking
    case upToDate
    case updateAvailable(PublishedRelease)
    case failed(String)
}

@MainActor
public final class UpdateChecker: ObservableObject {
    public static let automaticInterval: TimeInterval = 24 * 60 * 60

    @Published public private(set) var state: UpdateCheckState = .idle

    private let client: any LatestReleaseFetching
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    private let openURL: (URL) -> Bool
    private let successAcknowledgementDuration: Duration
    private var transientResetTask: Task<Void, Never>?

    public init(
        client: any LatestReleaseFetching = GitHubLatestReleaseClient(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init,
        openURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        successAcknowledgementDuration: Duration = .seconds(2)
    ) {
        self.client = client
        self.defaults = defaults
        self.now = now
        self.openURL = openURL
        self.successAcknowledgementDuration = successAcknowledgementDuration
    }

    public func checkAutomaticallyIfNeeded(currentVersion: String) async {
        let currentDate = now()
        if let lastCheck = defaults.object(forKey: Keys.lastCheckDate) as? Date {
            let elapsed = currentDate.timeIntervalSince(lastCheck)
            if elapsed >= 0, elapsed < Self.automaticInterval { return }
        }
        await check(currentVersion: currentVersion, manual: false, at: currentDate)
    }

    public func checkManually(currentVersion: String) async {
        await check(currentVersion: currentVersion, manual: true, at: now())
    }

    @discardableResult
    public func openAvailableRelease() -> Bool {
        guard case .updateAvailable(let release) = state else { return false }
        return openURL(release.pageURL)
    }

    private func check(currentVersion: String, manual: Bool, at date: Date) async {
        guard state != .checking else { return }
        transientResetTask?.cancel()
        transientResetTask = nil
        guard let installed = SemanticVersion(tag: currentVersion) else {
            if manual { state = .failed("The installed version could not be read.") }
            return
        }

        state = .checking
        defaults.set(date, forKey: Keys.lastCheckDate)
        do {
            let latest = try await client.fetchLatestRelease()
            if latest.version > installed {
                state = .updateAvailable(latest)
            } else {
                state = manual ? .upToDate : .idle
                if manual {
                    transientResetTask = Task { @MainActor [weak self] in
                        guard let self else { return }
                        try? await Task.sleep(for: self.successAcknowledgementDuration)
                        guard !Task.isCancelled, self.state == .upToDate else { return }
                        self.state = .idle
                        self.transientResetTask = nil
                    }
                }
            }
        } catch {
            state = manual ? .failed("Could not check GitHub Releases.") : .idle
        }
    }

    private enum Keys {
        static let lastCheckDate = "com.binarybears.ntfsmac.updates.lastCheckDate"
    }
}
