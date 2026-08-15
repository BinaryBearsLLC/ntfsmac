import SwiftUI

/// GUI-PLAN.md "Read-only (dirty) state" table — exact copy, pure predicate. Split from the
/// `View` below the same way `StatusIcon`/`StatusIconView` split (`gui/Status/StatusIcon.swift`)
/// so `DirtyStateTests` can assert visibility without a SwiftUI view-inspection dependency.
public enum DirtyBanner {
    public static let bannerCopy =
        "Mounted read-only — Windows left this drive in an unsafe state. Run chkdsk, disable Fast Startup, then fully shut down Windows."

    public static func isVisible(for state: MountState) -> Bool {
        state == .mountedReadOnlyDirty
    }
}

/// Non-dismissable while RO-dirty. Production policy offers recovery guidance only: it never
/// exposes a read/write override for an unclean or hibernated Windows volume.
public struct DirtyBannerView: View {
    @ObservedObject public var appState: AppState
    @ObservedObject public var remountController: RemountController
    public let drive: Drive

    public init(appState: AppState, remountController: RemountController, drive: Drive) {
        self.appState = appState
        self.remountController = remountController
        self.drive = drive
    }

    public var body: some View {
        if DirtyBanner.isVisible(for: appState.state) {
            HStack(alignment: .top, spacing: 9) {
                WarningTriangleGlyph(color: .ntfsYellow)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Unclean journal detected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ntfsYellow.opacity(0.9))
                    Text(DirtyBanner.bannerCopy)
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
