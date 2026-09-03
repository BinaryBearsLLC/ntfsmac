import SwiftUI

public struct ReadOnlyWarningCopy: Equatable, Sendable {
    public let title: String
    public let message: String
}

/// A read-only landing becomes a Windows warning only when the mount output contains matching
/// evidence. Other causes stay explicit and never inherit dirty-volume repair advice.
public enum DirtyBanner {
    /// Prefer the most safety-relevant warning when multiple drives are mounted. Array order is
    /// not a diagnosis: an unknown read-only drive must not hide explicit Windows evidence from
    /// another mounted drive.
    public static func preferredReason(among reasons: [ReadOnlyReason]) -> ReadOnlyReason? {
        let actionable = reasons.filter(\.requiresAttention)
        return actionable.first(where: \.requiresWindowsRepair) ?? actionable.first
    }

    public static func copy(for reason: ReadOnlyReason?) -> ReadOnlyWarningCopy? {
        switch reason {
        case .windowsDirty:
            return .init(
                title: "Windows volume needs repair",
                message: "Mounted read-only because Windows marked this drive dirty. Run chkdsk, then eject it safely."
            )
        case .windowsHibernated:
            return .init(
                title: "Windows volume is hibernated",
                message: "Mounted read-only. Disable Fast Startup and fully shut down Windows before reconnecting it."
            )
        case .unsafeWindowsState:
            return .init(
                title: "Unsafe Windows state",
                message: "Mounted read-only to protect the drive. Run chkdsk, disable Fast Startup, then fully shut down Windows."
            )
        case .readOnlyMedia:
            return .init(
                title: "Drive is write-protected",
                message: "The device reports read-only media. Check its lock or adapter before reconnecting it."
            )
        case .unsupportedWriteMode:
            return .init(
                title: "Write mode is unavailable",
                message: "This filesystem or mount mode is available read-only. Run Diagnose for details."
            )
        case .unknown:
            return .init(
                title: "Write access unavailable",
                message: "The drive mounted read-only for an unconfirmed reason. Run Diagnose before retrying."
            )
        case .requested, .none:
            return nil
        }
    }
}

/// Non-dismissable while read-only needs attention. Recovery guidance never exposes a forced
/// read/write override.
public struct DirtyBannerView: View {
    public let reason: ReadOnlyReason

    public init(reason: ReadOnlyReason) {
        self.reason = reason
    }

    public var body: some View {
        if let copy = DirtyBanner.copy(for: reason) {
            HStack(alignment: .top, spacing: 9) {
                WarningTriangleGlyph(color: .ntfsYellow)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(copy.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ntfsYellow.opacity(0.9))
                    Text(copy.message)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.ntfsYellow.opacity(0.62))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ntfsYellow.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.ntfsYellow.opacity(0.22))
            )
        }
    }
}
