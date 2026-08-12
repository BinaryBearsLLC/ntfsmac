import Foundation
import Darwin

public struct SecurityEvidence: Equatable, Sendable {
    public let status: SecurityIndicatorStatus
    public let reason: String

    public init(status: SecurityIndicatorStatus, reason: String) {
        self.status = status
        self.reason = reason
    }
}

public struct SecurityStatusSnapshot: Equatable, Sendable {
    public let activeSessions: Int?
    public let privateLink: SecurityEvidence
    public let vpnRoute: SecurityEvidence
    public let pfPolicy: SecurityEvidence
    public let overall: SecurityEvidence

    public static let unknown = SecurityStatusSnapshot(
        activeSessions: nil,
        privateLink: .init(status: .unknown, reason: "STATUS_UNAVAILABLE"),
        vpnRoute: .init(status: .unknown, reason: "STATUS_UNAVAILABLE"),
        pfPolicy: .init(status: .unknown, reason: "STATUS_UNAVAILABLE"),
        overall: .init(status: .unknown, reason: "STATUS_UNAVAILABLE")
    )
}

/// Strict parser for the public root-authored summary. Unknown keys, duplicate keys, free-form
/// text, and identifier-shaped additions are rejected as one fail-closed unknown snapshot.
public enum SecurityStatusFileParser {
    private static let keys: Set<String> = [
        "schema", "active_sessions", "private_link", "private_reason", "vpn_route",
        "vpn_route_reason", "pf_policy", "pf_reason", "overall", "overall_reason",
    ]

    public static func parse(_ raw: String) -> SecurityStatusSnapshot? {
        guard raw.utf8.count <= 4096 else { return nil }
        var values: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) where !line.isEmpty {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            let key = String(parts[0])
            let value = String(parts[1])
            guard keys.contains(key), values.updateValue(value, forKey: key) == nil else { return nil }
        }

        guard values.count == keys.count, values["schema"] == "1",
              let privateLink = evidence(state: values["private_link"], reason: values["private_reason"]),
              let vpnRoute = evidence(state: values["vpn_route"], reason: values["vpn_route_reason"]),
              let pfPolicy = evidence(state: values["pf_policy"], reason: values["pf_reason"]),
              let overall = evidence(state: values["overall"], reason: values["overall_reason"])
        else { return nil }

        let activeSessions: Int?
        if values["active_sessions"] == "unknown" {
            activeSessions = nil
        } else if let rawCount = values["active_sessions"],
                  !rawCount.isEmpty,
                  rawCount.allSatisfy(\.isNumber),
                  let count = Int(rawCount), count >= 0 {
            activeSessions = count
        } else {
            return nil
        }

        return SecurityStatusSnapshot(
            activeSessions: activeSessions,
            privateLink: privateLink,
            vpnRoute: vpnRoute,
            pfPolicy: pfPolicy,
            overall: overall
        )
    }

    private static func evidence(state: String?, reason: String?) -> SecurityEvidence? {
        guard let state, let status = SecurityIndicatorStatus(rawValue: state),
              let reason, !reason.isEmpty,
              reason.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") })
        else { return nil }
        return SecurityEvidence(status: status, reason: reason)
    }
}

@MainActor
public final class SecurityStatusReader: ObservableObject {
    @Published public private(set) var snapshot: SecurityStatusSnapshot = .unknown

    private let path: String
    private let load: (String) -> String?
    private var pollTask: Task<Void, Never>?

    public init(
        path: String = "/var/run/ntfsmac/security-status",
        load: ((String) -> String?)? = nil
    ) {
        self.path = path
        self.load = load ?? Self.loadSecureFile(at:)
    }

    deinit { pollTask?.cancel() }

    public func startPolling(interval: Duration = .seconds(5)) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    public func refresh() {
        snapshot = load(path).flatMap(SecurityStatusFileParser.parse) ?? .unknown
    }

    private nonisolated static func loadSecureFile(at path: String) -> String? {
        let descriptor = Darwin.open(path, O_RDONLY | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == 0,
              metadata.st_mode & 0o022 == 0,
              metadata.st_size >= 0,
              metadata.st_size <= 4096
        else { return nil }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            data.append(buffer, count: count)
            guard data.count <= 4096 else { return nil }
        }
        return String(data: data, encoding: .utf8)
    }
}
