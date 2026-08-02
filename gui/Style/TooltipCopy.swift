/// Centralized, concise native-help copy. Keeping pointer help separate from accessibility labels
/// prevents tooltips from becoming the only explanation available to VoiceOver users.
public enum TooltipCopy {
    public enum Control: CaseIterable, Sendable {
        case settings
        case refresh
        case diagnose
        case mount
        case unmount
        case mountReadWriteAnyway
        case quit
    }

    public static func text(for control: Control) -> String {
        switch control {
        case .settings:
            "Open Settings"
        case .refresh:
            "Scan again for connected NTFS drives"
        case .diagnose:
            "Check runtime components and the private network"
        case .mount:
            "Mount this NTFS drive using the configured defaults"
        case .unmount:
            "Safely unmount this drive and tear down its private network"
        case .mountReadWriteAnyway:
            "Retry read/write mounting despite the unclean journal warning"
        case .quit:
            "Quit ntfsmac and tear down its private network"
        }
    }

    public static func status(for state: MountState) -> String {
        switch state {
        case .idle: "Idle — no drive is mounted"
        case .mounting: "Mount in progress"
        case .mountedReadWrite: "Drive mounted read/write"
        case .mountedReadOnly: "Drive deliberately mounted read-only"
        case .mountedReadOnlyDirty: "Drive mounted read-only because its journal is unclean"
        case .error: "ntfsmac needs attention"
        }
    }

    public static func diagnosticExplanation(for rowID: String) -> String {
        switch rowID {
        case "binaries":
            "The four runtime components required by ntfsmac"
        case "quarantine":
            "Whether macOS quarantine can block a required runtime component"
        case "kernel":
            "Whether the installed kernel bundle matches the version tested by the project"
        case "bridge":
            "The private host-only network used for NFS traffic to the microVM"
        default:
            "Diagnostic status"
        }
    }
}
