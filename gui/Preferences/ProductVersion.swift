import Foundation

/// Product/build version shown in Settings. The packaged app reads this from its own Info.plist;
/// keeping the formatting in a value type makes missing/malformed bundle metadata testable.
public struct ProductVersion: Equatable, Sendable {
    public let release: String
    public let build: String

    public init(release: String, build: String) {
        self.release = release
        self.build = build
    }

    public static func current(bundle: Bundle = .main) -> Self {
        resolve(infoDictionary: bundle.infoDictionary ?? [:])
    }

    public static func resolve(infoDictionary: [String: Any]) -> Self {
        let release = normalized(infoDictionary["CFBundleShortVersionString"]) ?? "Unknown"
        let build = normalized(infoDictionary["CFBundleVersion"]) ?? "Unknown"
        return .init(release: release, build: build)
    }

    public var settingsText: String {
        guard build != "Unknown", build != release else { return "Version \(release)" }
        return "Version \(release) (\(build))"
    }

    private static func normalized(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
