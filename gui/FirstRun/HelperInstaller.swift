import Foundation
import ServiceManagement
import HelperShared
import os.log

private let helperInstallerLog = Logger(subsystem: "com.binarybears.ntfsmac", category: "HelperInstaller")

/// `SMAppService.register()` can report a denied/revoked background-item decision as a generic
/// EPERM even while `status` still reads `.notRegistered` (notably after replacing a development
/// build under the same bundle identifier). Treat only Apple's two documented denial shapes as
/// recoverable Login Items approval; signature, plist, and all unrelated failures stay failures.
enum ModernRegistrationErrorPolicy {
    private static let appServiceDomain = "SMAppServiceErrorDomain"

    static func requiresLoginItemsRecovery(_ error: NSError) -> Bool {
        var candidate: NSError? = error
        for _ in 0..<4 {
            guard let current = candidate else { return false }
            if current.domain == appServiceDomain,
               current.code == Int(POSIXErrorCode.EPERM.rawValue) {
                return true
            }
            if current.domain == NSOSStatusErrorDomain,
               current.code == Int(kSMErrorLaunchDeniedByUser) {
                return true
            }
            candidate = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

/// Outcome shared by the modern SMAppService registration and the Legacy SMJobBless path.
public enum HelperInstallOutcome: Equatable, Sendable {
    case installed
    case requiresApproval(String)
    case denied(String)
    case failed(String)
}

/// Seam over both ServiceManagement lifecycles. The Legacy calls are synchronous and may block
/// for an administrator prompt; the standard registration can instead transition to a separate
/// System Settings approval state. `Sendable` keeps both paths off the menu-bar main actor.
public protocol HelperInstallService: Sendable {
    var requiresPostInstallHealthCheck: Bool { get }
    func isInstalled(label: String) -> Bool
    func requiresApproval(label: String) -> Bool
    func bless(label: String) -> HelperInstallOutcome
    func migrateLegacyHelper(legacyLabel: String, newLabel: String) -> HelperInstallOutcome?
    func unregister(label: String) async -> HelperInstallOutcome?
    func openApprovalSettings()
}

public extension HelperInstallService {
    var requiresPostInstallHealthCheck: Bool { false }
    func requiresApproval(label: String) -> Bool { false }
    func migrateLegacyHelper(legacyLabel: String, newLabel: String) -> HelperInstallOutcome? { nil }
    func unregister(label: String) async -> HelperInstallOutcome? { nil }
    func openApprovalSettings() {}
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

    public var requiresPostInstallHealthCheck: Bool {
        #if NTFSMAC_LEGACY_HELPER
        false
        #else
        true
        #endif
    }

    /// A registration probe is only lifecycle state, not an identity proof. The subsequent XPC
    /// version exchange, helper-side caller validation, and release signatures remain the
    /// authorization boundary in both distributions.
    public func isInstalled(label: String) -> Bool {
        #if NTFSMAC_LEGACY_HELPER
        SMJobCopyDictionary(kSMDomainSystemLaunchd, label as CFString) != nil
        #else
        modernService.status == .enabled
        #endif
    }

    public func requiresApproval(label: String) -> Bool {
        #if NTFSMAC_LEGACY_HELPER
        false
        #else
        modernService.status == .requiresApproval
        #endif
    }

    public func bless(label: String) -> HelperInstallOutcome {
        #if NTFSMAC_LEGACY_HELPER
        let authorization = authorization(for: [kSMRightBlessPrivilegedHelper])
        guard let authRef = authorization.reference else { return authorization.failure! }
        defer { AuthorizationFree(authRef, [.destroyRights]) }
        return bless(label: label, authorization: authRef)
        #else
        do {
            try modernService.register()
        } catch {
            let registrationError = error as NSError
            helperInstallerLog.error(
                "SMAppService register failed: domain=\(registrationError.domain, privacy: .public) code=\(registrationError.code, privacy: .public)"
            )
            switch modernService.status {
            case .enabled:
                return .installed
            case .requiresApproval:
                return .requiresApproval(Self.modernApprovalMessage)
            case .notRegistered, .notFound:
                if ModernRegistrationErrorPolicy.requiresLoginItemsRecovery(registrationError) {
                    return .requiresApproval(Self.modernApprovalResetMessage)
                }
                return .failed("Could not register ntfsmac Helper: \(error.localizedDescription)")
            @unknown default:
                return .failed("Could not determine the ntfsmac Helper approval state.")
            }
        }
        return outcomeForModernStatus()
        #endif
    }

    /// Removes the pre-v3 job and blesses the new v3 helper under one explicit administrator
    /// transaction. The old daemon correctly rejects the new app's identity, so it cannot be
    /// asked to uninstall itself over its former XPC service.
    public func migrateLegacyHelper(
        legacyLabel: String,
        newLabel: String
    ) -> HelperInstallOutcome? {
        #if NTFSMAC_LEGACY_HELPER
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
        #else
        // The standard build keeps the compatibility helper intact until the newly registered
        // daemon has answered the current XPC version check. That daemon then removes every
        // retired standalone job from its privileged cleanup surface. This ordering is
        // transactional: denied approval or an unhealthy modern daemon never destroys the
        // user's last working helper.
        return nil
        #endif
    }

    public func unregister(label: String) async -> HelperInstallOutcome? {
        #if NTFSMAC_LEGACY_HELPER
        return nil
        #else
        switch modernService.status {
        case .notRegistered, .notFound:
            return .installed
        case .enabled, .requiresApproval:
            let service = modernService
            let gate = HelperTimeoutGate<HelperInstallOutcome>()
            let outcome = await withCheckedContinuation { continuation in
                gate.install(continuation)
                // The synchronous API returns before launchd has reaped a running daemon. Apple's
                // completion-handler contract is the point at which re-registration is safe; an
                // immediate register otherwise fails with SMAppServiceErrorDomain/EPERM and sends
                // the user into an unnecessary Login Items recovery flow.
                service.unregister { error in
                    if let error {
                        gate.resolve(
                            .failed(
                                "Could not unregister ntfsmac Helper: \(error.localizedDescription)"
                            )
                        )
                    } else {
                        gate.resolve(.installed)
                    }
                }
                Task.detached {
                    try? await Task.sleep(for: .seconds(10))
                    gate.resolve(
                        .failed("Timed out while waiting for ntfsmac Helper to stop safely.")
                    )
                }
            }
            if outcome == .installed {
                // macOS 26.6.2 can finish the documented asynchronous unregister callback while
                // its Background Task Management record is still settling. A register in the
                // same run-loop slice then returns EPERM even though the user never denied it;
                // the same call succeeds moments later. Keep this one-time upgrade/repair path
                // bounded and give the system record a short grace period.
                try? await Task.sleep(for: .seconds(1))
            }
            return outcome
        @unknown default:
            return .failed("Could not determine the ntfsmac Helper registration state.")
        }
        #endif
    }

    public func openApprovalSettings() {
        #if !NTFSMAC_LEGACY_HELPER
        SMAppService.openSystemSettingsLoginItems()
        #endif
    }

    #if !NTFSMAC_LEGACY_HELPER
    private var modernService: SMAppService {
        SMAppService.daemon(plistName: modernHelperLaunchDaemonPlistName)
    }

    private static let modernApprovalMessage =
        "Allow ntfsmac in System Settings > General > Login Items, then return and refresh."

    private static let modernApprovalResetMessage =
        "In System Settings > General > Login Items, turn ntfsmac off and back on. Then reopen ntfsmac from Applications and choose Refresh."

    private func outcomeForModernStatus() -> HelperInstallOutcome {
        switch modernService.status {
        case .enabled:
            return .installed
        case .requiresApproval:
            return .requiresApproval(Self.modernApprovalMessage)
        case .notRegistered:
            return .failed("ntfsmac Helper was not registered.")
        case .notFound:
            return .failed("The bundled ntfsmac Helper service could not be found.")
        @unknown default:
            return .failed("Could not determine the ntfsmac Helper approval state.")
        }
    }
    #endif

    #if NTFSMAC_LEGACY_HELPER
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
    #endif
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
    func cleanupRetiredHelpers() async throws -> CommandResult
    nonisolated func invalidateConnection()
}

extension HelperClient: StaleHelperDetecting {}

public extension StaleHelperDetecting {
    func cleanupRetiredHelpers() async throws -> CommandResult {
        CommandResult(output: "No retired helper cleanup required.", exitCode: 0)
    }

    nonisolated func invalidateConnection() {}
}

/// A task group waits for all children before leaving scope, including an XPC continuation that
/// ignores cancellation. This single-resume gate lets the installer return at the deadline while
/// the timed-out connection is invalidated separately.
private final class HelperTimeoutGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value?, Never>?
    private var resolved = false

    func install(_ continuation: CheckedContinuation<Value?, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    @discardableResult
    func resolve(_ value: Value?) -> Bool {
        let pending: CheckedContinuation<Value?, Never>? = lock.withLock {
            guard !resolved else { return nil }
            resolved = true
            defer { continuation = nil }
            return continuation
        }
        guard let pending else { return false }
        pending.resume(returning: value)
        return true
    }
}

public enum HelperInstallState: Equatable, Sendable {
    case notChecked
    case checking
    case readyToInstall
    case requiresApproval(String)
    case installed
    case installing
    case denied(String)
    case failed(String)

    /// Drives the menu-bar icon red (`ui/prototype.html`'s "Error — Helper Missing" state,
    /// `NtfsmacApp.swift`) — the only two states where the user actually needs to act.
    public var isDeniedOrFailed: Bool {
        switch self {
        case .requiresApproval, .denied, .failed: true
        case .notChecked, .checking, .readyToInstall, .installed, .installing: false
        }
    }
}

/// Drives the privileged-helper install flow (GUI-PLAN.md v1 feature 8). It detects an existing
/// current helper, distinguishes modern approval from denial/failure, and reuses one install path
/// for first run and Settings repair.
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
    private let postRegistrationHealthCheckAttempts: Int
    private let postRegistrationHealthCheckDelayNanoseconds: UInt64

    public init(
        service: any HelperInstallService = RealHelperInstallService(),
        staleDetector: any StaleHelperDetecting = HelperClient(),
        quarantineStripper: any QuarantineStripping = RealQuarantineStripper(),
        label: String = helperMachServiceName,
        legacyLabel: String = legacyHelperMachServiceName,
        expectedVersion: String = helperBuildIdentity(cliTreeHash: GeneratedCLIManifest.expectedTreeHashHex),
        staleCheckTimeoutNanoseconds: UInt64 = 5_000_000_000,
        postRegistrationHealthCheckAttempts: Int = 12,
        postRegistrationHealthCheckDelayNanoseconds: UInt64 = 250_000_000
    ) {
        self.service = service
        self.staleDetector = staleDetector
        self.quarantineStripper = quarantineStripper
        self.label = label
        self.legacyLabel = legacyLabel
        self.expectedVersion = expectedVersion
        self.staleCheckTimeoutNanoseconds = staleCheckTimeoutNanoseconds
        self.postRegistrationHealthCheckAttempts = max(1, postRegistrationHealthCheckAttempts)
        self.postRegistrationHealthCheckDelayNanoseconds =
            postRegistrationHealthCheckDelayNanoseconds
    }

    /// First-launch inspection is read-only and cannot display an authorization prompt or create
    /// a Login Items approval request. Only `installAfterConsent()` may register a helper.
    public func checkWithoutInstalling() async {
        switch state {
        case .checking, .installing, .denied, .failed:
            return
        case .notChecked, .readyToInstall, .requiresApproval, .installed:
            break
        }
        state = .checking
        let approvalRequired = await runOffCooperativePool { [service, label] in
            service.requiresApproval(label: label)
        }
        if approvalRequired {
            state = .requiresApproval(Self.modernApprovalMessage)
            return
        }
        let alreadyInstalled = await runOffCooperativePool { [service, label] in
            service.isInstalled(label: label)
        }
        guard alreadyInstalled else {
            state = .readyToInstall
            return
        }
        state = await isRegisteredHelperCurrent() ? .installed : .readyToInstall
    }

    /// Explicit first-run action. Rechecks registration after the user chooses Install, clears a
    /// stale helper if necessary, and then uses the same lifecycle path as Settings repair.
    public func installAfterConsent() async {
        guard state != .installing else { return }
        state = .checking
        let approvalRequired = await runOffCooperativePool { [service, label] in
            service.requiresApproval(label: label)
        }
        if approvalRequired {
            state = .requiresApproval(Self.modernApprovalMessage)
            return
        }
        let alreadyInstalled = await runOffCooperativePool { [service, label] in
            service.isInstalled(label: label)
        }
        if alreadyInstalled {
            if await isRegisteredHelperCurrent() {
                state = .installed
                return
            }
            guard await prepareStaleHelperForReplacement() else { return }
        }
        await install()
    }

    /// Explicit Settings repair. Unlike first-run consent, this deliberately replaces an already
    /// current helper: Legacy re-blesses its standalone tool, while the standard build unregisters
    /// and re-registers its bundled daemon. Pending System Settings approval remains non-destructive.
    public func reinstallAfterConsent() async {
        guard state != .installing else { return }
        state = .checking
        let approvalRequired = await runOffCooperativePool { [service, label] in
            service.requiresApproval(label: label)
        }
        if approvalRequired {
            state = .requiresApproval(Self.modernApprovalMessage)
            return
        }
        let alreadyInstalled = await runOffCooperativePool { [service, label] in
            service.isInstalled(label: label)
        }
        if alreadyInstalled {
            guard await prepareStaleHelperForReplacement() else { return }
        }
        await install()
    }

    /// Compatibility entry point retained for existing callers: detect already-installed and skip
    /// — never re-prompts
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
    /// registered helper only counts as installed if it reports the same build identity this GUI
    /// was built with. Standard then replaces it through `SMAppService.unregister()`; Legacy uses
    /// its bounded XPC self-uninstall before a fresh bless. Both converge on the same explicit
    /// install path used on first run.
    public func installIfNeeded() async {
        switch state {
        case .checking, .readyToInstall, .requiresApproval, .installing, .denied, .failed:
            return
        case .notChecked, .installed:
            break
        }
        state = .checking
        let approvalRequired = await runOffCooperativePool { [service, label] in
            service.requiresApproval(label: label)
        }
        if approvalRequired {
            state = .requiresApproval(Self.modernApprovalMessage)
            return
        }
        let alreadyInstalled = await runOffCooperativePool { [service, label] in service.isInstalled(label: label) }
        guard alreadyInstalled else {
            await install()
            return
        }
        if await isRegisteredHelperCurrent() {
            state = .installed
            return
        }
        // The lifecycle-specific replacement is bounded where it uses XPC: an old Legacy helper
        // that predates `uninstallHelper` (or is simply wedged) cannot hang this indefinitely.
        // Standard does not call the stale generation at all and lets SMAppService replace it.
        // Silent-failure-hunter finding (2026-07-13, MEDIUM): this result was fully discarded
        // with no logging — a real failure clearing the stale daemon (e.g. a permission error
        // deleting its plist, not just a timeout) then surfaced only as a generic `bless()`
        // failure next, with no trail pointing back at the actual root cause. Best-effort
        // discard-and-continue is still correct because registration/re-blessing performs the
        // actual replacement, but it should leave a diagnostic trail.
        guard await prepareStaleHelperForReplacement() else { return }
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

    /// Standard/P2 replacement is owned entirely by `SMAppService.unregister()`: calling an old
    /// embedded generation's XPC uninstall selector first is both unnecessary and unsafe because
    /// a pre-fix generation may remove the still-working Legacy helper before P2 proves healthy.
    /// Legacy has no SMAppService registration, so its `nil` outcome deliberately falls back to
    /// the bounded XPC self-uninstall path before re-blessing.
    private func prepareStaleHelperForReplacement() async -> Bool {
        let outcome = await service.unregister(label: label)
        guard let outcome else {
            await uninstallStaleHelper()
            return true
        }
        switch outcome {
        case .installed:
            return true
        case .requiresApproval(let message):
            state = .requiresApproval(message)
        case .denied(let message):
            state = .denied(message)
        case .failed(let message):
            state = .failed(message)
        }
        return false
    }

    public func reset() {
        state = .notChecked
    }

    public func openApprovalSettings() {
        service.openApprovalSettings()
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
        let gate = HelperTimeoutGate<T>()
        return await withCheckedContinuation { continuation in
            gate.install(continuation)
            let operation = Task {
                gate.resolve(try? await work())
            }
            Task { [staleDetector] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard gate.resolve(nil) else { return }
                staleDetector.invalidateConnection()
                operation.cancel()
            }
        }
    }

    /// Unconditional install/reinstall — the one path shared by first run and Settings. Guards
    /// against double-taps starting two concurrent registration/authorization transactions.
    public func install() async {
        guard state != .installing else { return }
        state = .installing
        let outcome = await registrationAttempt(allowLegacyMigration: true)
        await finishInstall(outcome, allowAutomaticHealthRepair: true)
    }

    private func registrationAttempt(allowLegacyMigration: Bool) async -> HelperInstallOutcome {
        await runOffCooperativePool { [service, label, legacyLabel, quarantineStripper] in
            quarantineStripper.stripQuarantine()
            if allowLegacyMigration, let migration = service.migrateLegacyHelper(
                legacyLabel: legacyLabel,
                newLabel: label
            ) {
                return migration
            }
            return service.bless(label: label)
        }
    }

    /// A freshly re-registered SMAppService daemon can transiently remain submitted but
    /// uninitialized after a complete uninstall (observed live on macOS 26.6.2: `runs = 0`, valid
    /// LWCR, no XPC endpoint). The same explicit Repair action already fixes that state by
    /// unregistering and registering once more. Perform that exact recovery automatically inside
    /// the user's original Install action, bounded to one retry; approval/denial outcomes still
    /// surface immediately and Legacy cleanup still waits for a healthy current XPC handshake.
    private func finishInstall(
        _ outcome: HelperInstallOutcome,
        allowAutomaticHealthRepair: Bool
    ) async {
        switch outcome {
        case .installed:
            guard service.requiresPostInstallHealthCheck else {
                state = .installed
                return
            }
            guard await waitForRegisteredHelperCurrent() else {
                if allowAutomaticHealthRepair {
                    helperInstallerLog.notice(
                        "registered modern helper did not become healthy; attempting one bounded registration reset"
                    )
                    guard await prepareStaleHelperForReplacement() else { return }
                    state = .installing
                    let retryOutcome = await registrationAttempt(allowLegacyMigration: false)
                    await finishInstall(retryOutcome, allowAutomaticHealthRepair: false)
                    return
                }
                state = .failed(
                    "macOS registered ntfsmac Helper, but it still could not start after an automatic repair. In Login Items, turn ntfsmac off and back on, reopen the app, then choose Refresh."
                )
                return
            }
            guard let cleanup = await withStaleCheckTimeout({ [staleDetector] in
                try await staleDetector.cleanupRetiredHelpers()
            }), cleanup.exitCode == 0 else {
                state = .failed(
                    "ntfsmac Helper is ready, but the previous helper could not be removed completely. Retry from Settings."
                )
                return
            }
            helperInstallerLog.notice(
                "retired compatibility helper cleanup completed after modern XPC health verification"
            )
            state = .installed
        case .requiresApproval(let message):
            state = .requiresApproval(message)
        case .denied(let message):
            state = .denied(message)
        case .failed(let message):
            state = .failed(message)
        }
    }

    /// Registration status becomes enabled before launchd necessarily exposes the new daemon's
    /// XPC endpoint. A single immediate version call therefore creates a false "broken helper"
    /// result and needlessly unregisters a healthy approval. Retry only this post-registration
    /// health check; passive startup inspection remains a single bounded read.
    private func waitForRegisteredHelperCurrent() async -> Bool {
        for attempt in 0..<postRegistrationHealthCheckAttempts {
            if await isRegisteredHelperCurrent() {
                return true
            }
            staleDetector.invalidateConnection()
            guard attempt + 1 < postRegistrationHealthCheckAttempts else { break }
            try? await Task.sleep(nanoseconds: postRegistrationHealthCheckDelayNanoseconds)
        }
        return false
    }

    private static let modernApprovalMessage =
        "Allow ntfsmac in System Settings > General > Login Items, then return and refresh."

    /// ServiceManagement work is dispatched to a dedicated GCD queue. This is essential for the
    /// Legacy password dialog and also keeps status/registration calls off Swift Concurrency's
    /// small shared cooperative thread pool.
    private nonisolated func runOffCooperativePool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}
