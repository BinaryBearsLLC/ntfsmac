import SwiftUI

/// GUI-PLAN.md "Menu-bar icon states" — the storage states rendered by the icon and popover.
/// Styling (exact colors) lives in `StatusIcon.swift`; `3-liquid-glass` refines hex values later.
public enum MountState: Equatable, Sendable {
    case idle
    case mounting
    case mountedReadWrite
    /// Mounted read-only by request. This is intentional and healthy.
    case mountedReadOnly
    /// Read-only was observed, but explicit evidence does not attribute it to a Windows unsafe
    /// state. Keep the UI yellow without inventing a dirty bit or hibernation diagnosis.
    case mountedReadOnlyUnexpected
    /// Explicit backend evidence identified an unsafe Windows state (dirty, hibernated, or an
    /// equivalent fail-closed refusal). The historical case name remains source-compatible.
    case mountedReadOnlyDirty
    /// A mount was observed or a mount command succeeded, but the independent host snapshot was
    /// incomplete or contradictory. Never use green or claim read/write while in this state.
    case mountedUnknown
    case error
}

@MainActor
public final class AppState: ObservableObject {
    @Published public var state: MountState = .idle

    public init() {}
}
