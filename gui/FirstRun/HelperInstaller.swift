import Foundation
import ServiceManagement
import HelperShared
import os.log

private let helperInstallerLog = Logger(subsystem: "com.binarybears.ntfsmac", category: "HelperInstaller")

/// Outcome of a real `SMJobBless` attempt. v3 deliberately keeps this compatibility mechanism;
/// changing the helper architecture belongs to P2, never to an incidental repair.
public enum HelperInstallOutcome: Equatable, Sendable {
    case installed
    case denied(String)
    case failed(String)
}

/// Seam over `ServiceManagement`'s real, synchronous, blocking C APIs — `SMJobCopyDictionary`/
/// `SMJobBless` neither suspend nor come in an async flavor; they block the calling thread for
/// the whole (potentially long, user-driven) admin auth prompt. `Sendable`-constrained so
/// `HelperInstaller` can run this off the main actor without freezing the menu-bar UI for
/// however long the user takes to authenticate.
public protocol HelperInstallService: Sendable {
    func isInstalled(label: String) -> Bool
    func bless(label: String) -> HelperInstallOutcome
    func migrateLegacyHelper(legacyLabel: String, newLabel: String) -> HelperInstallOutcome?
}

public extension HelperInstallService {
    func migrateLegacyHelper(legacyLabel: String, newLabel: String) -> HelperInstallOutcome? { nil }
}

/// Strips `com.apple.quarantine` from this app's own bundle before every `bless()` attempt.
/// Real-world failure this exists for: quarantine-aware transfers can propagate a quarantine tag
/// onto every file Finder extracts from a DMG, including the embedded helper tool. `SMJobBless`
/// then copies the helper tool *out* of
/// the bundle into `/Library/PrivilegedHelperTools/` as a standalone file, still quarantined —
/// launchd's later attempt to actually run that daemon gets silently blocked by Gatekeeper (no
/// dialog, since a background daemon has no interactive session to approve through). `bless()`
/// itself still reports success (it only copies files and registers with launchd), so this reads
/// exactly like "installed the helper" followed by "can't communicate with helper" for
/// everything — install and uninstall alike. Clearing quarantine on files this app already owns
/// is not a privileged operation (no XPC helper round-trip needed, no L5 concern).
public protocol QuarantineStripping: Sendable {
    func stripQuarantine()
}

public struct RealQuarantineStripper: QuarantineStripping {
    public init() {}

    public func stripQuarantine() {
        Self.stripQuarantine(at: Bundle.main.bundleURL)
    }

    static func stripQuarantine(at bundleURL: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsPackageDescendants]
        ) else { return }
        removeQuarantineIfPresent(at: bundleURL.path)
        for case let fileURL as URL in enumerator {
            removeQuarantineIfPresent(at: fileURL.path)
        }
    }

    private static func removeQuarantineIfPresent(at path: String) {
        let name = "com.apple.quarantine"
        guard getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW) >= 0 else { return }
        removexattr(path, name, XATTR_NOFOLLOW)
    }
}

public struct RealHelperInstallService: HelperInstallService {
    public init() {}

    /// `SMJobCopyDictionary` is the documented, real way to check whether a `SMJobBless`-style
    /// launchd job is already registered — deliberately not `SMAppService.status` (that's the
    /// newer `SMAppService.daemon` API, a different install mechanism PLAN.md never adopted;
    /// swapping to it here would be exactly the kind of signing/entitlement architecture
    /// deviation L4/L5 calls a HARD-STOP). Still functions on macOS 13+ despite the
    /// deprecation annotation.
    ///
    /// This registration probe only
    /// checks that *some* job is registered under `label`, not that its on-disk binary still
    /// matches this app's expected identifier. The subsequent XPC identity check and official
    /// release signature remain the authorization boundary.
    public func isInstalled(label: String) -> Bool {
        SMJobCopyDictionary(kSMDomainSystemLaunchd, label as CFString) != nil
    }

    public func bless(label: String) -> HelperInstallOutcome {
        let authorization = authorization(for: [kSMRightBlessPrivilegedHelper])
        guard let authRef = authorization.reference else { return authorization.failure! }
        defer { AuthorizationFree(authRef, [.destroyRights]) }
        return bless(label: label, authorization: authRef)
    }

    /// Removes the pre-v3 job and blesses the new v3 helper under one explicit administrator
    /// transaction. The old daemon correctly rejects the new app's identity, so it cannot be
    /// asked to uninstall itself over its former XPC service.
    public func migrateLegacyHelper(
        legacyLabel: String,
        newLabel: String
    ) -> HelperInstallOutcome? {
        guard isInstalled(label: legacyLabel) else { return nil }
        let authorization = authorization(for: [
            kSMRightModifySystemDaemons,
            kSMRightBlessPrivilegedHelper,
        ])
        guard let authRef = authorization.reference else { return authorization.failure! }
        defer { AuthorizationFree(authRef, [.destroyRights]) }

        var removalError: Unmanaged<CFError>?
        guard SMJobRemove(
            kSMDomainSystemLaunchd,
            legacyLabel as CFString,
            authRef,
            true,
            &removalError
        ) else {
            if let removalError {
                return .failed(
                    "Could not remove the previous ntfsmac Helper: "
                        + (removalError.takeRetainedValue() as Error).localizedDescription
                )
            }
            return .failed("Could not remove the previous ntfsmac Helper.")
        }
        return bless(label: newLabel, authorization: authRef)
    }

    private func bless(label: String, authorization: AuthorizationRef) -> HelperInstallOutcome {
        var cfError: Unmanaged<CFError>?
        guard SMJobBless(kSMDomainSystemLaunchd, label as CFString, authorization, &cfError) else {
            if let cfError {
                return .failed((cfError.takeRetainedValue() as Error).localizedDescription)
            }
            return .failed("SMJobBless failed for an unknown reason.")
        }
        return .installed
    }

    private func authorization(
        for rightNames: [String]
    ) -> (reference: AuthorizationRef?, failure: HelperInstallOutcome?) {
        var authRef: AuthorizationRef?
        let createStatus = AuthorizationCreate(nil, nil, [], &authRef)
        guard createStatus == errAuthorizationSuccess, let authRef else {
            return (nil, Self.authorizationFailure(status: createStatus))
        }

        let flags: AuthorizationFlags = [.interactionAllowed, .extendRights, .preAuthorize]
        for rightName in rightNames {
            let status = rightName.withCString { namePtr -> OSStatus in
                var item = AuthorizationItem(name: namePtr, valueLength: 0, value: nil, flags: 0)
                return withUnsafeMutablePointer(to: &item) { itemPtr -> OSStatus in
                    var rights = AuthorizationRights(count: 1, items: itemPtr)
                    return AuthorizationCopyRights(authRef, &rights, nil, flags, nil)
                }
            }
            guard status == errAuthorizationSuccess else {
                AuthorizationFree(authRef, [.destroyRights])
                return (nil, Self.authorizationFailure(status: status))
            }
        }
        return (authRef, nil)
    }

    private static func authorizationFailure(status: OSStatus) -> HelperInstallOutcome {
        switch status {
        case errAuthorizationCanceled:
            return .denied("Authorization was cancelled.")
        case errAuthorizationDenied:
            return .denied("Authorization was denied — an administrator password is required.")
        default:
            return .failed("Authorization request failed (status \(status)).")
        }
    }
}

/// Narrow seam over `HelperClient`'s `version`/`uninstallHelper` — lets `HelperInstaller` tell a
/// stale daemon (left running from a previous build, before this session's XPC-protocol/hash-pin
/// changes) apart from a current one, and clear it out. Same retroactive-conformance pattern as
/// `HelperUninstalling`/`CLIStaging` — `HelperClient` wraps a real `NSXPCConnection`, no seam of
/// its own to fake in tests.
@MainActor
public protocol StaleHelperDetecting: Sendable {
    func version() async throws -> String
    func uninstallHelper() async throws -> CommandResult
}

extension HelperClient: StaleHelperDetecting {}

public enum HelperInstallState: Equatable, Sendable {
    case notChecked
    case checking
    case readyToInstall
    case installed
    case installing
    case denied(String)
    case failed(String)

    /// Drives the menu-bar icon red (`ui/prototype.html`'s "Error — Helper Missing" state,
    /// `NtfsmacApp.swift`) — the only two states where the user actually needs to act.
    public var isDeniedOrFailed: Bool {
        switch self {
        case .denied, .failed: true
        case .notChecked, .checking, .readyToInstall, .installed, .installing: false
        }
    }
}

/// Drives the privileged-helper install flow (GUI-PLAN.md v1 feature 8): exactly one auth
/// prompt, detects already-installed and skips it, denial/mismatch surfaces a plain-language
/// cause + lets the caller retry (red icon in `FirstRunView`). `install()` is the exact same
/// path both first-run and the Preferences "Reinstall privileged helper" button use — this
/// unit's Do clause requires that reuse, so there's deliberately no separate "reinstall" method.
@MainActor
public final class HelperInstaller: ObservableObject {
    @Published public private(set) var state: HelperInstallState = .notChecked

    private let service: any HelperInstallService
    private let staleDetector: any StaleHelperDetecting
    private let quarantineStripper: any QuarantineStripping
    private let label: String
    private let legacyLabel: String
    private let expectedVersion: String
    private let staleCheckTimeoutNanoseconds: UInt64

    public init(
        service: any HelperInstallService = RealHelperInstallService(),
        staleDetector: any StaleHelperDetecting = HelperClient(),
        quarantineStripper: any QuarantineStripping = RealQuarantineStripper(),
        label: String = helperMachServiceName,
        legacyLabel: String = legacyHelperMachServiceName,
        expectedVersion: String = helperBuildIdentity(cliTreeHash: GeneratedCLIManifest.expectedTreeHashHex),
        staleCheckTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.service = service
        self.staleDetector = staleDetector
        self.quarantineStripper = quarantineStripper
        self.label = label
        self.legacyLabel = legacyLabel
        self.expectedVersion = expectedVersion
        self.staleCheckTimeoutNanoseconds = staleCheckTimeoutNanoseconds
    }

    /// First-launch inspection that never invokes `SMJobBless` and therefore can never display
    /// an unexpected administrator-password prompt. A missing or stale helper becomes an
    /// explicit, user-actionable state; only `installAfterConsent()` may continue from there.
    public func checkWithoutInstalling() async {
        switch state {
        case .checking, .installing, .denied, .failed:
            return
        case .notChecked, .readyToInstall, .installed:
            break
        }
        state = .checking
        let alreadyInstalled = await runOffCooperativePool { [service, label] in
            service.isInstalled(label: label)
        }
        guard alreadyInstalled else {
            state = .readyToInstall
            return
        }
        state = await isRegisteredHelperCurrent() ? .installed : .readyToInstall
    }

    /// Explicit first-run action. Rechecks the registration after the user has chosen Install,
    /// clears a stale helper if necessary, then follows the same single `SMJobBless` path used by
    /// Preferences. No privileged prompt is reachable before this method is called by a button.
    public func installAfterConsent() async {
        guard state != .installing else { return }
        state = .checking
        let alreadyInstalled = await runOffCooperativePool { [service, label] in
            service.isInstalled(label: label)
        }
        if alreadyInstalled {
            if await isRegisteredHelperCurrent() {
                state = .installed
                return
            }
            await uninstallStaleHelper()
        }
        await install()
    }

    /// First-run entry point: detect already-installed and skip (Do clause) — never re-prompts
    /// for an install that's already live. Guards against a stray re-trigger (e.g. SwiftUI
    /// `.task` re-running) while a check/install is already in flight, and — critically — against
    /// re-running after a `.denied`/`.failed` outcome: `MenuBarExtra(.window)` recreates
    /// `FirstRunView` (and refires its `.task`) every time the popover reopens, so without this
    /// guard closing and reopening the menu after a denial re-triggers `bless()` and shows a new
    /// OS auth prompt with no user action. Only the explicit "Retry" button (which calls
    /// `install()` directly) may attempt again once denied/failed.
    ///
    /// "already installed" per `SMJobCopyDictionary` only proves *some* job is registered under
    /// `label` (`RealHelperInstallService.isInstalled`'s own doc comment) — it says nothing about
    /// whether that daemon is *this build's* helper. A daemon left running from an earlier build
    /// (common mid-development, rebuilding the app without ever un-blessing the old helper) is
    /// live enough to satisfy that check while being out of protocol sync with the current GUI —
    /// exactly the failure mode behind both a permanently-stuck "Setup incomplete" (`stageCLI`
    /// rejects on the hash it was actually built with) and "couldn't connect with helper"
    /// (`removeDependencies`/`uninstallHelper` calls hitting a daemon that doesn't match). So a
    /// registered helper only counts as installed if it reports the same build hash this GUI was
    /// built with; otherwise it's cleared out (best-effort, via its own still-live
    /// `uninstallHelper` — works for any helper new enough to have that method, i.e. everything
    /// from this point forward) and a fresh `bless()` runs, same single-auth-prompt path a
    /// first-time install takes.
    public func installIfNeeded() async {
        switch state {
        case .checking, .readyToInstall, .installing, .denied, .failed:
            return
        case .notChecked, .installed:
            break
        }
        state = .checking
        let alreadyInstalled = await runOffCooperativePool { [service, label] in service.isInstalled(label: label) }
        guard alreadyInstalled else {
            await install()
            return
        }
        if await isRegisteredHelperCurrent() {
            state = .installed
            return
        }
        // Bounded, same reason `isRegisteredHelperCurrent` below is: a helper old enough to
        // predate `uninstallHelper` itself (or one that's simply wedged) must not be able to
        // hang this indefinitely — worst case, `bless()` still runs next and SMJobBless's own
        // install path takes over from whatever state the stale daemon was left in.
        // Silent-failure-hunter finding (2026-07-13, MEDIUM): this result was fully discarded
        // with no logging — a real failure clearing the stale daemon (e.g. a permission error
        // deleting its plist, not just a timeout) then surfaced only as a generic `bless()`
        // failure next, with no trail pointing back at the actual root cause. Best-effort
        // discard-and-continue is still correct (SMJobBless's own install path recovers
        // regardless), but it should leave a diagnostic trail.
        await uninstallStaleHelper()
        await install()
    }

    private func uninstallStaleHelper() async {
        let staleUninstallResult = await withStaleCheckTimeout { [staleDetector] in try await staleDetector.uninstallHelper() }
        if let staleUninstallResult {
            helperInstallerLog.notice("stale helper uninstall: exitCode=\(staleUninstallResult.exitCode, privacy: .public) output=\(staleUninstallResult.output, privacy: .public)")
        } else {
            helperInstallerLog.notice("stale helper uninstall: no response within timeout (wedged or predates uninstallHelper)")
        }
    }

    public func reset() {
        state = .notChecked
    }

    /// A daemon old enough to predate `version()` entirely doesn't just fail to answer — an XPC
    /// message for a selector the exported interface never declared can leave the reply
    /// continuation unresolved rather than erroring cleanly (the exact hang class `HelperClient`'s
    /// `call()` already documents fixing for the *known* protocol; an *unknown* future one is the
    /// same risk in the other direction). `withStaleCheckTimeout` bounds it: no matter how an old
    /// or wedged helper actually fails, staleness detection resolves within
    /// `staleCheckTimeoutNanoseconds` and reads as stale, never blocks `installIfNeeded()` forever.
    private func isRegisteredHelperCurrent() async -> Bool {
        guard let reported = await withStaleCheckTimeout({ [staleDetector] in try await staleDetector.version() }) else { return false }
        return reported == expectedVersion
    }

    private func withStaleCheckTimeout<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async -> T? {
        let timeoutNanoseconds = staleCheckTimeoutNanoseconds
        return await withTaskGroup(of: T?.self) { group in
            group.addTask {
                try? await work()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// Unconditional install/reinstall — the one path both `installIfNeeded()` and any future
    /// "Reinstall privileged helper" caller use. Guards against a double-tap firing two
    /// concurrent `SMJobBless` calls (each would show its own OS auth prompt).
    public func install() async {
        guard state != .installing else { return }
        state = .installing
        let outcome = await runOffCooperativePool { [service, label, legacyLabel, quarantineStripper] in
            quarantineStripper.stripQuarantine()
            if let migration = service.migrateLegacyHelper(
                legacyLabel: legacyLabel,
                newLabel: label
            ) {
                return migration
            }
            return service.bless(label: label)
        }
        switch outcome {
        case .installed:
            state = .installed
        case .denied(let message):
            state = .denied(message)
        case .failed(let message):
            state = .failed(message)
        }
    }

    /// `SMJobCopyDictionary`/`SMJobBless` block for an indefinite, user-driven duration (the
    /// system auth prompt) — dispatched to a dedicated GCD queue, not `Task.detached` (which
    /// would occupy a slot on Swift Concurrency's small, shared cooperative thread pool for
    /// that entire indefinite wait, starving unrelated `async` work elsewhere in the process).
    private nonisolated func runOffCooperativePool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}
