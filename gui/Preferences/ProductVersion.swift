import Foundation

/// Product/build version shown in Settings. The packaged app reads this from its own Info.plist;
/// keeping the formatting in a value type makes missing/malformed bundle metadata testable.
public struct ProductVersion: Equatable, Sendable {
    public let release: String
    public let build: String
    public let releaseLabel: String?

    public init(release: String, build: String, releaseLabel: String? = nil) {
        self.release = release
        self.build = build
        self.releaseLabel = releaseLabel
    }

    public static func current(bundle: Bundle = .main) -> Self {
        resolve(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func resolve(infoDictionary: [String: Any]) -> Self {
        let release = normalized(infoDictionary["CFBundleShortVersionString"]) ?? "Unknown"
        let build = normalized(infoDictionary["CFBundleVersion"]) ?? "Unknown"
        return .init(release: release, build: build,
                     releaseLabel: normalized(infoDictionary["NTFSMACReleaseLabel"]))
    }

    public var settingsText: String {
        let display = releaseLabel.map { "\(release) \($0)" } ?? release
        guard build != "Unknown", build != release else { return "Version \(display)" }
        return "Version \(display) (\(build))"
    }

    private static func normalized(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
