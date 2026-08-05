/// Centralized, concise native-help copy. Keeping pointer help separate from accessibility labels
/// prevents tooltips from becoming the only explanation available to VoiceOver users.
public enum TooltipCopy {
    public enum Control: CaseIterable, Sendable {
        case back
        case settings
        case refresh
        case diagnose
        case mount
        case unmount
        case mountReadWriteAnyway
        case hideSecurity
        case showSecurity
        case quit
    }

    public static func text(for control: Control) -> String {
        switch control {
        case .back:
            "Return to the main popover"
        case .settings:
            "Open Settings"
        case .refresh:
            "Scan again for supported drives"
        case .diagnose:
            "Check runtime components and the private network"
        case .mount:
            "Mount this NTFS drive using the configured defaults"
        case .unmount:
            "Safely unmount this drive and tear down its private network"
        case .mountReadWriteAnyway:
            "Retry read/write mounting despite the unclean journal warning"
        case .hideSecurity:
            "Hide security status without changing the mount or helper"
        case .showSecurity:
            "Show security status"
        case .quit:
            "Quit ntfsmac and tear down its private network"
        }
    }

    public static func status(for state: MountState) -> String {
        switch state {
        case .idle: "Idle — no supported drive is mounted"
        case .mounting: "Mount in progress"
        case .mountedReadWrite: "All mounted drives are read/write"
        case .mountedReadOnly: "At least one mounted drive is read-only"
        case .mountedReadOnlyDirty: "At least one mounted NTFS drive has an unclean journal"
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
