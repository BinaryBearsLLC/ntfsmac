import Foundation
import HelperShared
import ServiceManagement

/// Narrow seam over `HelperClient`'s two uninstall methods, same retroactive-conformance
/// pattern as `HelperMounting` (`MountController.swift`) — `HelperClient` is a concrete class
/// wrapping a real `NSXPCConnection`, no seam of its own to fake in tests.
@MainActor
public protocol HelperUninstalling {
    func removeDependencies() async throws -> CommandResult
    func uninstallHelper() async throws -> CommandResult
}

/// Production adapter. The Legacy helper removes its standalone launchd files and boots itself
/// out over XPC. For a complete standard uninstall, the still-healthy root daemon first removes
/// retired standalone helpers; it then prepares itself and the app asks SMAppService to unregister
/// the embedded daemon so macOS owns that lifecycle atomically.
@MainActor
public final class RealHelperUninstallService: HelperUninstalling {
    private let client: HelperClient

    public init(client: HelperClient = HelperClient()) {
        self.client = client
    }

    public func removeDependencies() async throws -> CommandResult {
        try await client.removeDependencies()
    }

    public func uninstallHelper() async throws -> CommandResult {
        #if !NTFSMAC_LEGACY_HELPER
        let cleanup = try await client.cleanupRetiredHelpers()
        guard cleanup.exitCode == 0 else { return cleanup }
        #endif

        let result = try await client.uninstallHelper()
        guard result.exitCode == 0 else { return result }

        #if NTFSMAC_LEGACY_HELPER
        return result
        #else
        let service = SMAppService.daemon(plistName: modernHelperLaunchDaemonPlistName)
        switch service.status {
        case .notRegistered, .notFound:
            return result
        case .enabled, .requiresApproval:
            do {
                try await service.unregister()
                return result
            } catch {
                return CommandResult(
                    output: "Could not unregister ntfsmac Helper: \(error.localizedDescription)",
                    exitCode: 1
                )
            }
        @unknown default:
            return CommandResult(
                output: "Could not determine the ntfsmac Helper registration state.",
                exitCode: 1
            )
        }
        #endif
    }
}

public enum HelperUninstallState: Equatable, Sendable {
    case idle
    case removingDependencies
    case removingHelper
    case done(String)
    case failed(String)
}

/// Drives the "Uninstall ntfsmac" flow from Preferences: removes `$installPrefix` + the real
/// user's `~/.anylinuxfs`/logs (`HelperService.removeDependencies`), then un-blesses the
/// privileged helper itself (`HelperService.uninstallHelper`) — always in that order, since
/// `uninstallHelper` makes the mach service disappear and nothing can be requested through it
/// afterward. Once both steps succeed, dragging the .app to Trash leaves no leftovers.
@MainActor
public final class HelperUninstaller: ObservableObject {
    @Published public private(set) var state: HelperUninstallState = .idle

    private let client: any HelperUninstalling
    private let onUninstallComplete: (@MainActor @Sendable () -> Void)?

    public init(
        client: any HelperUninstalling = RealHelperUninstallService(),
        onUninstallComplete: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.client = client
        self.onUninstallComplete = onUninstallComplete
    }

    public func uninstallEverything() async {
        guard state != .removingDependencies, state != .removingHelper else { return }

        state = .removingDependencies
        do {
            let depsResult = try await client.removeDependencies()
            guard depsResult.exitCode == 0 else {
                state = .failed(depsResult.output)
                return
            }

            state = .removingHelper
            let helperResult = try await client.uninstallHelper()
            guard helperResult.exitCode == 0 else {
                state = .failed(helperResult.output)
                return
            }

            state = .done(depsResult.output)
            onUninstallComplete?()
        } catch {
            state = .failed(MountController.describe(error))
        }
    }
}
