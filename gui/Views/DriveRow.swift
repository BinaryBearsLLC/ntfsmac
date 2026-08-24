import SwiftUI

public enum NTFS3PreflightCopy {
    public static let title = "NTFS3 · Experimental"
    public static let guidance = "Use only after Windows Fast Startup is disabled, Windows is fully shut down, and filesystem errors are repaired with chkdsk. Symbolic links created by macOS/ntfs-3g are not portable to NTFS3 and Verified Copy rejects them. There is no automatic fallback."

    public static func isAvailable(for fsType: String) -> Bool {
        fsType.lowercased() == "ntfs"
    }
}

/// One row per detected drive — `ui/prototype.html`'s "Drive row" comp (mounted/light/dirty
/// variants, lines 134-161/313-339/583-613): icon-box + label/fsType·device + size, then a
/// button row. Not-yet-mounted rows have no comp reference (the comp only shows mounted/idle-
/// empty/dirty/error), so their single `[Mount]` pill is a reasonable extrapolation of the same
/// visual language rather than an invented new one.
public struct DriveRow: View {
    @Environment(\.colorScheme) private var colorScheme
    public let drive: Drive
    public let isMounted: Bool
    public let isDirty: Bool
    public let actionsDisabled: Bool
    public let onMount: () -> Void
    public let onOpenInFinder: (() -> Void)?
    public let onVerifiedCopy: (() -> Void)?
    public let onUnmount: () -> Void
    public let onMountAnyway: (() -> Void)?
    public let onMountExperimental: (() -> Void)?
    @State private var showsNTFS3Preflight = false

    public init(
        drive: Drive,
        isMounted: Bool = false,
        isDirty: Bool = false,
        actionsDisabled: Bool = false,
        onMount: @escaping () -> Void = {},
        onOpenInFinder: (() -> Void)? = nil,
        onVerifiedCopy: (() -> Void)? = nil,
        onUnmount: @escaping () -> Void = {},
        onMountAnyway: (() -> Void)? = nil,
        onMountExperimental: (() -> Void)? = nil
    ) {
        self.drive = drive
        self.isMounted = isMounted
        self.isDirty = isDirty
        self.actionsDisabled = actionsDisabled
        self.onMount = onMount
        self.onOpenInFinder = onOpenInFinder
        self.onVerifiedCopy = onVerifiedCopy
        self.onUnmount = onUnmount
        self.onMountAnyway = onMountAnyway
        self.onMountExperimental = onMountExperimental
    }

    private var accentColor: Color { isDirty ? .ntfsYellow : .ntfsBlue }

    public var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                DriveRowGlyph(color: accentColor)
                    .padding(8.5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(accentColor.opacity(isDirty ? 0.1 : 0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(accentColor.opacity(isDirty ? 0.2 : 0.22))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(drive.label.isEmpty ? drive.identifier : drive.label)
                        .font(.system(size: 13, weight: .semibold))
                    Text("\(drive.fsType.uppercased()) · /dev/\(drive.identifier)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(drive.size)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if isMounted {
                HStack(spacing: 6) {
                    Button {
                        onOpenInFinder?()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .font(.system(size: 10.5))
                            Text("Open")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                    .ntfsmacKeyboardFocus()
                    .disabled(onOpenInFinder == nil || actionsDisabled)
                    .accessibilityLabel("Open in Finder")
                    .help(TooltipCopy.text(for: .openInFinder))

                    Button {
                        onUnmount()
                    } label: {
                        HStack(spacing: 5) {
                            EjectGlyph()
                            Text("Unmount")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassDestructive(colorScheme: colorScheme))
                    .ntfsmacKeyboardFocus()
                    .disabled(actionsDisabled)
                    .help(TooltipCopy.text(for: .unmount))

                    if let onVerifiedCopy {
                        Menu {
                            Button("Verified Copy…") { onVerifiedCopy() }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 22)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .ntfsmacKeyboardFocus()
                        .disabled(actionsDisabled)
                        .accessibilityLabel("More drive actions")
                        .help(TooltipCopy.text(for: .verifiedCopy))
                    }
                }

                if isDirty, let onMountAnyway {
                    Button {
                        onMountAnyway()
                    } label: {
                        HStack(spacing: 5) {
                            MountAnywayGlyph()
                            Text("Mount read/write anyway…")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassWarning())
                    .ntfsmacKeyboardFocus()
                    .disabled(actionsDisabled)
                    .help(TooltipCopy.text(for: .mountReadWriteAnyway))
                }
            } else {
                if showsNTFS3Preflight, let onMountExperimental {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(NTFS3PreflightCopy.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.ntfsYellow)
                        Text(NTFS3PreflightCopy.guidance)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Button("Cancel") { showsNTFS3Preflight = false }
                                .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                                .ntfsmacKeyboardFocus()
                            Button("Mount with NTFS3") {
                                showsNTFS3Preflight = false
                                onMountExperimental()
                            }
                            .buttonStyle(.glassWarning())
                            .ntfsmacKeyboardFocus()
                        }
                        .disabled(actionsDisabled)
                    }
                } else {
                    HStack(spacing: 5) {
                        Button {
                            onMount()
                        } label: {
                            Text("Mount")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                        .ntfsmacKeyboardFocus()
                        .disabled(actionsDisabled)
                        .accessibilityLabel("Mount \(drive.label.isEmpty ? drive.identifier : drive.label)")
                        .help("Mount with ntfs-3g, the compatibility-first default")

                        if onMountExperimental != nil {
                            Menu {
                                Button("NTFS3 (Experimental)…") {
                                    showsNTFS3Preflight = true
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 22)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .ntfsmacKeyboardFocus()
                            .disabled(actionsDisabled)
                            .accessibilityLabel("More drive actions")
                            .help("Choose the experimental NTFS3 driver for this mount only")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// No drive rows to render — `PopoverContentView` shows the comp's rich empty-state block
/// (icon + copy + Refresh) itself when idle with nothing detected; this view only composes the
/// per-drive rows once at least one exists.
public struct DriveListView: View {
    public let drives: [Drive]
    public let mountedDriveID: String?
    public let isDirty: Bool
    public let onMount: (Drive) -> Void
    public let onUnmount: (Drive) -> Void
    public let onMountAnyway: (() -> Void)?

    public init(
        drives: [Drive],
        mountedDriveID: String? = nil,
        isDirty: Bool = false,
        onMount: @escaping (Drive) -> Void = { _ in },
        onUnmount: @escaping (Drive) -> Void = { _ in },
        onMountAnyway: (() -> Void)? = nil
    ) {
        self.drives = drives
        self.mountedDriveID = mountedDriveID
        self.isDirty = isDirty
        self.onMount = onMount
        self.onUnmount = onUnmount
        self.onMountAnyway = onMountAnyway
    }

    public var body: some View {
        ForEach(drives) { drive in
            DriveRow(
                drive: drive,
                isMounted: drive.id == mountedDriveID,
                isDirty: isDirty && drive.id == mountedDriveID,
                onMount: { onMount(drive) },
                onOpenInFinder: nil,
                onUnmount: { onUnmount(drive) },
                onMountAnyway: onMountAnyway
            )
        }
    }
}
