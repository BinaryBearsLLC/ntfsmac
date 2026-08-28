import AppKit
import Foundation
import HelperShared
import SwiftUI

@MainActor
public protocol FullDiskAccessChecking: Sendable {
    func checkDeviceAccess(device: String) async throws -> CommandResult
}

extension HelperClient: FullDiskAccessChecking {}

public enum FullDiskAccessState: Equatable, Sendable {
    case notChecked
    case checking
    case waitingForDrive
    case needsAuthorization
    case waitingForAuthorization
    case granted
    case failed(String)
}

/// Decides whether drive access needs UI attention without treating an absent drive as an
/// incomplete installation. Full Disk Access cannot be verified without a real partition, but
/// there is also nothing privileged to authorize while no supported drive is connected.
///
/// The grant itself deliberately remains session-scoped: every launch probes the helper again as
/// soon as a supported partition appears. This policy changes presentation only; it never caches
/// or assumes permission.
enum FullDiskAccessPresentationPolicy {
    static func shouldPresentSetup(
        state: FullDiskAccessState,
        deviceID: String?,
        driveDiscoveryFailed: Bool
    ) -> Bool {
        guard state != .granted else { return false }
        return deviceID != nil || driveDiscoveryFailed
    }

    /// Diagnose accepts three values: confirmed, denied, or unavailable. An unprobed no-drive
    /// session is unavailable evidence, not a denial.
    static func diagnosticGrantEvidence(for state: FullDiskAccessState) -> Bool? {
        switch state {
        case .granted:
            true
        case .needsAuthorization, .waitingForAuthorization:
            false
        case .notChecked, .checking, .waitingForDrive, .failed:
            nil
        }
    }
}

/// Session-scoped gate for the helper's raw-device permission. It deliberately does not cache a
/// prior success across launches: a quick read-only probe catches permission revocation or a
/// replaced helper before the main Mount button becomes available. When no drive exists, the
/// presentation policy above allows the normal idle UI without weakening this gate.
@MainActor
public final class FullDiskAccessController: ObservableObject {
    @Published public private(set) var state: FullDiskAccessState
    @Published public private(set) var authorizationAttempt = 0

    private let checker: any FullDiskAccessChecking

    public init(
        checker: any FullDiskAccessChecking = HelperClient(),
        initialState: FullDiskAccessState = .notChecked
    ) {
        self.checker = checker
        self.state = initialState
    }

    public var isGranted: Bool { state == .granted }

    public func check(deviceID: String?, whileWaiting: Bool = false) async {
        guard let deviceID else {
            state = .waitingForDrive
            return
        }
        state = whileWaiting ? .waitingForAuthorization : .checking
        do {
            let result = try await checker.checkDeviceAccess(device: deviceID)
            if result.exitCode == 0 {
                state = .granted
            } else {
                state = whileWaiting ? .waitingForAuthorization : .needsAuthorization
            }
        } catch {
            state = .failed(MountController.describe(error))
        }
    }

    public func beginAuthorization() {
        authorizationAttempt += 1
        state = .waitingForAuthorization
    }

    public func reset() {
        authorizationAttempt = 0
        state = .notChecked
    }
}

enum FDAPromptCopy {
    static var helperServiceName: String { helperMachServiceName }

    static var instructions: String {
        switch HelperDistributionVariant.current {
        case .modern:
            "In Full Disk Access, enable ntfsmac. If macOS shows its drive-access component separately, enable ntfsmac Helper (\(helperServiceName)) too."
        case .legacy:
            "In Full Disk Access, enable ntfsmac Helper (\(helperServiceName)). macOS may show a generic executable icon for this Legacy component."
        }
    }
}

/// Drive discovery runs before the Full Disk Access probe. Keep its raw command output out of
/// the setup UI because it can contain user paths; the detailed evidence remains in Diagnose.
enum DriveDiscoveryFailureCopy {
    static let title = "Unable to check connected drives"
    static let message = "ntfsmac could not prepare its disk runtime. Try again, or open Settings to check for an update."

    static func isVisible(for rawError: String?) -> Bool { rawError != nil }
}

enum NoDriveAccessCopy {
    static let title = "No drives found"
    static let message = "Connect an NTFS or ext drive when ready. ntfsmac will verify access before mounting."
}

/// Minimal setup step shown after helper/CLI preparation and before the normal popover. The
/// controller keeps probing after System Settings opens, so granting access completes setup
/// automatically instead of consuming and losing the user's first Mount action.
public struct FullDiskAccessSetupView: View {
    @ObservedObject public var controller: FullDiskAccessController
    public let deviceID: String?
    public let driveDiscoveryFailed: Bool
    public let onRetryDriveDiscovery: () -> Void
    public let onOpenSettings: () -> Void
    public let onQuit: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        controller: FullDiskAccessController,
        deviceID: String?,
        driveDiscoveryFailed: Bool = false,
        onRetryDriveDiscovery: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.controller = controller
        self.deviceID = deviceID
        self.driveDiscoveryFailed = driveDiscoveryFailed
        self.onRetryDriveDiscovery = onRetryDriveDiscovery
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            Divider()
            HStack {
                Button {
                    onOpenSettings()
                } label: {
                    SettingsGearGlyph(color: .secondary)
                }
                .buttonStyle(.glassIcon(colorScheme: colorScheme))
                .ntfsmacKeyboardFocus()
                .accessibilityLabel("Open Settings")
                .help(TooltipCopy.text(for: .settings))
                Spacer()
                Button("Quit", action: onQuit)
                    .buttonStyle(.glassFooter(colorScheme: colorScheme))
                    .ntfsmacKeyboardFocus()
                    .accessibilityLabel("Quit ntfsmac")
            }
        }
        .padding(12)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
        .task(id: deviceID) {
            guard !controller.isGranted else { return }
            await controller.check(deviceID: deviceID)
        }
        .task(id: controller.authorizationAttempt) {
            guard controller.authorizationAttempt > 0 else { return }
            while !Task.isCancelled && !controller.isGranted {
                await controller.check(deviceID: deviceID, whileWaiting: true)
                guard !controller.isGranted else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.ntfsYellow.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.ntfsYellow.opacity(0.28)))
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.ntfsYellow)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("ntfsmac").font(.system(size: 13, weight: .semibold))
                Text("Full Disk Access").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(controller.isGranted ? Color.ntfsGreen : Color.ntfsYellow).frame(width: 9, height: 9)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .notChecked, .checking:
            progressCard("Checking disk access…")
        case .waitingForDrive:
            if driveDiscoveryFailed {
                messageCard(
                    title: DriveDiscoveryFailureCopy.title,
                    message: DriveDiscoveryFailureCopy.message
                )
                Button("Try Again", action: onRetryDriveDiscovery)
                    .buttonStyle(.glassNeutral(colorScheme: colorScheme))
                    .ntfsmacKeyboardFocus()
            } else {
                messageCard(
                    title: NoDriveAccessCopy.title,
                    message: NoDriveAccessCopy.message
                )
            }
        case .needsAuthorization:
            authorizationCard(waiting: false)
        case .waitingForAuthorization:
            authorizationCard(waiting: true)
        case .granted:
            Label("Full Disk Access ready", systemImage: "checkmark.seal.fill")
                .foregroundStyle(Color.ntfsGreen)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            messageCard(title: "Unable to verify disk access", message: message)
            Button("Try Again") {
                Task { await controller.check(deviceID: deviceID) }
            }
            .buttonStyle(.glassNeutral(colorScheme: colorScheme))
            .ntfsmacKeyboardFocus()
        }
    }

    private func progressCard(_ title: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(title).font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }

    private func authorizationCard(waiting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                if let iconURL = Bundle.main.url(forResource: "HelperIcon", withExtension: "png"),
                   let icon = NSImage(contentsOf: iconURL) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 42, height: 42)
                        .accessibilityHidden(true)
                }
                if waiting {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Full Disk Access…")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                } else {
                    Text("Allow access for ntfsmac Helper")
                        .font(.system(size: 12.5, weight: .semibold))
                }
            }
            Text(FDAPromptCopy.instructions)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(waiting ? "Open Settings Again" : "Open Full Disk Access") {
                controller.beginAuthorization()
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.glassPrimary())
            .ntfsmacKeyboardFocus()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.ntfsYellow.opacity(0.09)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.ntfsYellow.opacity(0.2)))
    }

    private func messageCard(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.secondary.opacity(0.08)))
    }
}
