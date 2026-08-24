import Foundation
import Security
import Darwin
import CryptoKit

/// Reconstructs the invoking console user's identity for CLI children launched by the root XPC
/// helper. A launchd service otherwise inherits root's sparse environment, while the runtime
/// cache and OCI tooling require the caller's HOME, USER and LOGNAME to agree. Kept as a pure
/// helper so the contract is testable without manufacturing an NSXPCConnection.
func applyInvokerIdentityEnvironment(
    _ environment: inout [String: String],
    uid: uid_t,
    gid: gid_t,
    username: String?,
    homeDirectory: String?
) {
    environment["SUDO_UID"] = String(uid)
    environment["SUDO_GID"] = String(gid)
    if let username, !username.isEmpty {
        environment["USER"] = username
        environment["LOGNAME"] = username
    }
    if let homeDirectory, !homeDirectory.isEmpty {
        environment["HOME"] = homeDirectory
    }
}

// Shared between the privileged helper (`ntfsmac-helper`) and the GUI client
// (`gui/Helper/HelperClient.swift`). PLAN.md §3: the XPC interface is the trust boundary —
// everything in this file is untrusted input until `validateDevice` / `isValidUnmountTarget`
// says otherwise, and the helper re-validates independently of whatever the GUI already checked.

/// PLAN.md L6 — device names are validated against this pattern before touching any shell
/// invocation, in both the CLI (`cli/lib/validate-device.sh`) and here, independently.
public let deviceNamePattern = "^disk[0-9]+s[0-9]+$"

/// Bump whenever the XPC selector surface or required helper behavior changes. The CLI tree hash
/// alone cannot distinguish a newly packaged GUI from an older helper when only Swift/helper
/// code changed.
public let helperProtocolRevision = 4

public func helperBuildIdentity(cliTreeHash: String) -> String {
    "xpc\(helperProtocolRevision):\(cliTreeHash)"
}

public func validateDevice(_ device: String) -> Bool {
    device.range(of: deviceNamePattern, options: .regularExpression) != nil
}

/// Shared `/Volumes/`-rooted path shape check: non-traversal, and — security review finding
/// (2026-07-13, CRITICAL, originally scoped to `mount`'s `mountPoint` only) — no shell
/// metacharacters, since the vendored `anylinuxfs::cmd_mount::mount()` splices this unescaped
/// into a `sh -c` string (`mount -t nfs ... "<mount_point>"` / the mirror unmount path) and a
/// value containing `"` can break out of that quoted argument. Security review finding
/// (2026-07-13, HIGH): `unmount`'s target got only the traversal check, not this blocklist,
/// despite feeding the same vendored mount/unmount code — nothing proved the unmount path
/// doesn't have the same unescaped-splice shape as mount's. Shared here so the two validators
/// can't drift apart again.
private func isValidVolumesPath(_ path: String) -> Bool {
    guard path.hasPrefix("/Volumes/"), !path.contains("..") else { return false }
    let forbidden = CharacterSet(charactersIn: "\"'`$\\;\n\r&|<>(){}*?~")
    return path.rangeOfCharacter(from: forbidden) == nil
}

/// `anylinuxfs unmount` (and our `cli/commands/unmount.sh` wrapper) accepts either a bare
/// `diskNsM` device or an already-resolved mount point — mirrors `unmount.sh`'s own comment.
/// A bare device still runs the full L6 regex; a path goes through `isValidVolumesPath`.
public func isValidUnmountTarget(_ target: String) -> Bool {
    if validateDevice(target) { return true }
    return isValidVolumesPath(target)
}

/// `mount`'s optional `mountPoint` — see `isValidVolumesPath`.
public func isValidMountPoint(_ path: String) -> Bool {
    isValidVolumesPath(path)
}

/// `stageCLI`'s input check — same discipline as `validateDevice`/`isValidUnmountTarget`
/// (never trust the caller). `build/package-app.sh` only ever produces one relative layout;
/// this string match is what pins the helper to running *that* script and nothing an
/// unprivileged caller could point elsewhere. `..` is rejected outright — a literal absolute
/// path suffix match already can't be satisfied by a traversal, but reject defense-in-depth
/// rather than rely solely on the suffix check.
public func isValidStageCLIPath(_ path: String) -> Bool {
    path.hasPrefix("/") && !path.contains("..") && path.hasSuffix("/Contents/Resources/cli-src/install.sh")
}

/// Deterministic content hash over every regular file under `directory` — sorted relative
/// paths, each file's SHA-256 digest folded in that order into one combined digest. Security
/// review finding (2026-07-12, CRITICAL): `isValidStageCLIPath`'s shape check alone doesn't
/// prove the caller-supplied `install.sh` is the genuine, untampered one this app shipped —
/// ad-hoc signing (L4) means `codesign -v` on the individual copied binaries only proves
/// internal self-consistency, not authenticity, and `verifyClientIdentity`'s pid-based check can
/// be spoofed by any locally ad-hoc-signed process claiming the same identifier string. This
/// hash is what actually closes that gap: the *expected* value is compiled into this helper
/// binary at build time (`GeneratedCLIManifest.expectedTreeHashHex`, written by
/// `build/package-app.sh` before the shipped build, verified reproducible via a throwaway first
/// build pass using this exact function) — something only the trusted build pipeline can set,
/// not a caller of the XPC API, not even one that fully spoofs `verifyClientIdentity`.
/// `stageCLI` recomputes this over the caller-supplied path's containing directory and refuses
/// to execute anything that doesn't match bit-for-bit.
public func computeTreeHash(at directory: URL) -> String? {
    guard let enumerator = FileManager.default.enumerator(
        at: directory.standardizedFileURL,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
    ) else { return nil }

    let prefix = directory.standardizedFileURL.path
    var relativePaths: [String] = []
    for case let fileURL as URL in enumerator {
        guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return nil
        }
        // Security review finding (2026-07-13, CRITICAL): the previous `isRegularFile`-only
        // filter silently excluded symlinks from the hash — their presence/target contributed
        // nothing to `actualHash`, so a symlink planted anywhere under `directory` (dereferenced
        // by `install.sh` or anything it sources) bypassed the tamper check entirely. Fail
        // closed instead: a build-generated `cli-src/` tree should never legitimately contain a
        // symlink, so any symlink here — file or directory — rejects the whole hash rather than
        // being silently skipped.
        if values.isSymbolicLink == true { return nil }
        guard values.isRegularFile == true else { continue }
        let path = fileURL.standardizedFileURL.path
        guard path.hasPrefix(prefix + "/") else { continue }
        relativePaths.append(String(path.dropFirst(prefix.count + 1)))
    }
    guard !relativePaths.isEmpty else { return nil }
    relativePaths.sort()

    var combined = SHA256()
    for relativePath in relativePaths {
        guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(relativePath).path) else { return nil }
        combined.update(data: Data(relativePath.utf8))
        combined.update(data: Data(SHA256.hash(data: data)))
    }
    return combined.finalize().map { String(format: "%02x", $0) }.joined()
}

/// Fixed resolution path for vendored binaries the helper shells out to. `install.sh`'s CLI
/// path writes here directly; the GUI's first-run installer (`3-first-run-install`) stages its
/// own bundled copies to the same prefix so the privileged helper — which runs standalone under
/// launchd after SMJobBless, no `Bundle.main` back to the .app — always resolves one fixed path
/// regardless of which install path produced it.
public let installPrefix = "/usr/local/ntfsmac"

/// Second candidate: Homebrew's own version-independent `opt/<formula>` symlink (always
/// present once `brew install ntfsmac` links it, Apple Silicon default prefix — this project
/// is arm64-only per CLAUDE.md, so no Intel `/usr/local` brew prefix to also check). The
/// Formula deliberately keeps normal `bin.install`/`libexec.install` (Homebrew forbids `sudo`
/// during `brew install`, so it can never write the fixed `installPrefix` above) — this second
/// candidate is what lets the privileged helper find a brew-tap-only install without either
/// side needing to know about the other's install mechanism.
public let homebrewOptPrefix = "/opt/homebrew/opt/ntfsmac"

public let ntfsmacCandidatePrefixes = [installPrefix, homebrewOptPrefix]

/// Picks whichever candidate actually has a real `bin/ntfsmac` on disk, first-listed wins.
/// Falls back to `installPrefix` (the documented default) when neither is present — same
/// behavior every caller already hardcoded before this existed, so injecting this as a
/// default parameter value never changes what a from-clean unit test observes.
public func resolveNtfsmacPrefix(fileManager: FileManager = .default) -> String {
    for candidate in ntfsmacCandidatePrefixes where fileManager.isExecutableFile(atPath: "\(candidate)/bin/ntfsmac") {
        return candidate
    }
    return installPrefix
}

public let ntfsmacAppBundleIdentifier = "com.binarybears.ntfsmac"

/// The release builder compiles two deliberately separate helper distributions from the same
/// reviewed XPC implementation. The standard build uses Apple's macOS 13+ `SMAppService`
/// LaunchDaemon lifecycle; the compatibility build retains `SMJobBless` for older deployments.
/// Only the compatibility artifact is labelled for users — the standard product remains simply
/// "ntfsmac" and never exposes the internal P2 project name.
public enum HelperDistributionVariant: String, Sendable {
    case modern
    case legacy

    public static let current: Self = {
        #if NTFSMAC_LEGACY_HELPER
        .legacy
        #else
        .modern
        #endif
    }()

    public var settingsLabel: String {
        switch self {
        case .modern: "Modern helper"
        case .legacy: "Legacy compatibility helper"
        }
    }
}

/// The published v3 compatibility helper keeps its historical label so existing installations
/// remain repairable. The modern helper must use a different identity: this prevents launchd from
/// confusing an embedded SMAppService daemon with the standalone SMJobBless tool it replaces.
public let compatibilityHelperMachServiceName = "com.binarybears.ntfsmac.helper"
public let modernHelperMachServiceName = "com.binarybears.ntfsmac.helper.daemon"
public let modernHelperLaunchDaemonPlistName = "\(modernHelperMachServiceName).plist"
public let helperMachServiceName = HelperDistributionVariant.current == .legacy
    ? compatibilityHelperMachServiceName
    : modernHelperMachServiceName

/// Pre-v3 helper identity. It remains only as an explicit one-way migration source and must never
/// be used for a new install, XPC connection, diagnostic default, or packaged production identity.
public let legacyHelperMachServiceName = "com.khr898.ntfsmac.helper"

/// Helper identities this distribution may retire after its own root service is available. The
/// standard build removes both the v3 compatibility helper and the pre-v3 helper; the Legacy
/// build removes only the pre-v3 helper and must never remove itself.
public let retiredHelperMachServiceNames: [String] = {
    switch HelperDistributionVariant.current {
    case .modern:
        [compatibilityHelperMachServiceName, legacyHelperMachServiceName]
    case .legacy:
        [legacyHelperMachServiceName]
    }
}()

/// Detects the pre-v3 helper artifacts even when launchd no longer has a registered job for
/// their label. `SMJobCopyDictionary` cannot see that orphaned state, but leaving the root-owned
/// files behind would make both migration and the GUI's complete uninstall incomplete.
public func legacyHelperArtifactsPresent(fileManager: FileManager = .default) -> Bool {
    fileManager.fileExists(
        atPath: "/Library/LaunchDaemons/\(legacyHelperMachServiceName).plist"
    ) || fileManager.fileExists(
        atPath: "/Library/PrivilegedHelperTools/\(legacyHelperMachServiceName)"
    )
}

public func retiredHelperArtifactsPresent(fileManager: FileManager = .default) -> Bool {
    retiredHelperMachServiceNames.contains { label in
        fileManager.fileExists(atPath: "/Library/LaunchDaemons/\(label).plist")
            || fileManager.fileExists(atPath: "/Library/PrivilegedHelperTools/\(label)")
    }
}

public enum FsDriver: String, Codable, Sendable {
    // Raw value matches `cli/commands/mount.sh`'s literal `--fs-driver` values (L1: ntfs-3g is
    // the implicit default, ntfs3 is opt-in only via this flag, never an `-o` token).
    case ntfs3g = "ntfs-3g"
    case ntfs3 = "ntfs3"
    // ext2/3/4: the kernel auto-detects, so this is NOT a --fs-driver value. It's the GUI's
    // signal to the helper to skip --fs-driver (ntfs-3g can't mount ext4) and pass
    // --ignore-permissions instead, so the NFS export gets all_squash,anonuid=0,anongid=0
    // (vendor vmproxy/main.rs:1327) and the macOS user can write past ext's Unix ownership.
    // Reuses the existing `driver` XPC channel — no protocol signature change. NTFS keeps
    // .ntfs3g/.ntfs3 and never gets all_squash ("do not change the NTFS part").
    case ext = "ext"
}

/// Generic passthrough result for wrapper scripts that only ever print human-readable text —
/// none of `mount.sh`/`unmount.sh`/`pf-anchor.sh`/`pf-teardown.sh` emit structured JSON, so this
/// carries the real (stdout+stderr, exit code) shape rather than inventing fields none of them
/// produce.
public struct CommandResult: Codable, Sendable {
    public var output: String
    public var exitCode: Int32

    public init(output: String, exitCode: Int32) {
        self.output = output
        self.exitCode = exitCode
    }
}

/// Mutating XPC surface. Mount/unmount call the CLI's per-session security transaction inside the
/// already-root helper; there is deliberately no raw "load these PF rules" method anymore. That
/// older split API could load an unevaluated anchor with no lifecycle ownership or measured state.
/// `listDrives`/`status`/`diagnose` are deliberately absent:
/// each is read-only and explicitly Don't-listed as privileged in their own units
/// (`3-drive-detect`, `3-status-speed`, `3-diagnose-ui` all call the CLI directly, unprivileged).
@objc public protocol HelperXPCProtocol {
    /// Performs a non-mutating Full Disk Access preflight against the exact external partition
    /// the GUI detected. The helper reads one 512-byte block from the raw device into
    /// `/dev/null`; success proves the helper can open the disk before any mount is attempted.
    func checkDeviceAccess(device: String, reply: @escaping (Data?, String?) -> Void)

    /// `device` is re-validated against `deviceNamePattern` inside the helper before any shell
    /// call — never trusts the caller (§3). `driver`'s raw value must match `FsDriver`.
    /// `readOnly`: appends `ro` to the NFS client mount options (`cli/lib/nfs-mount.sh`'s
    /// `--read-only` flag) — the only real lever for a requested read-only mount, since
    /// anylinuxfs/ntfs-3g have no mode-request flag of their own (confirmed: no `force`/mode
    /// field on `MountCmd` in the vendored `cli.rs`; ntfs-3g's own dirty-journal check is the
    /// only thing that can *also* force read-only, independent of this flag).
    func mount(device: String, driver: String, mountPoint: String?, readOnly: Bool, reply: @escaping (Data?, String?) -> Void)

    /// `target` is re-validated against `isValidUnmountTarget` inside the helper.
    func unmount(target: String, reply: @escaping (Data?, String?) -> Void)

    /// Removes one recorded session, or reconciles stale sessions when nil. Never flushes a
    /// global/shared anchor, so one mount cannot invalidate another mount's protection.
    func teardown(sessionID: String?, reply: @escaping (Data?, String?) -> Void)

    /// Removes `installPrefix` (CLI + vendored dependencies, same tree `cli/commands/
    /// uninstall.sh` targets) plus the real invoking user's `~/.anylinuxfs` (rootfs cache +
    /// config.toml) and `~/Library/Logs/anylinuxfs*.log` — never the helper itself (see
    /// `uninstallHelper`). Rejects while any NFS mount is active, same safety check
    /// `uninstall.sh` makes.
    func removeDependencies(reply: @escaping (Data?, String?) -> Void)

    /// Un-blesses this helper: deletes its own `/Library/LaunchDaemons` plist and
    /// `/Library/PrivilegedHelperTools` binary, replies to the client, then `launchctl bootout`s
    /// its own launchd job last. The last XPC call any client should make — the mach service is
    /// gone once this returns. Combined with `removeDependencies`, this is what lets "drag the
    /// app to Trash" leave zero leftovers.
    func uninstallHelper(reply: @escaping (Data?, String?) -> Void)

    /// Removes helper identities retired by the current distribution without unregistering the
    /// current helper. The standard SMAppService daemon uses this only after its own XPC version
    /// handshake succeeds, making Legacy-to-standard migration transactional: a denied or broken
    /// standard registration can never destroy the still-working compatibility helper.
    func cleanupRetiredHelpers(reply: @escaping (Data?, String?) -> Void)

    /// Runs the bundled `install.sh` (staged read-only inside the calling app's own
    /// `Contents/Resources/cli-src/`, `build/package-app.sh`) as this already-root helper
    /// process, with `--no-path-link` so a GUI-only install never puts `ntfsmac` on the user's
    /// Terminal PATH. `installScriptPath` is re-validated inside the helper (§3: never trust
    /// the caller) before any shell call — must resolve to a real file whose path literally
    /// ends `/Contents/Resources/cli-src/install.sh`, the one fixed layout this script ever
    /// produces; nothing else is accepted regardless of what the GUI sends.
    func stageCLI(installScriptPath: String, reply: @escaping (Data?, String?) -> Void)

    /// Reports the XPC protocol revision plus the CLI tree hash this specific running helper was
    /// built with. Has nothing to do with staging —
    /// it exists so `HelperInstaller` can tell "a helper is registered" (`SMJobCopyDictionary`,
    /// which only proves *some* job exists under the label — see its own doc comment) apart from
    /// "the registered helper is *this build's* helper." A daemon left running from a previous
    /// build reports its own old hash (or, for a helper old enough to predate this method
    /// entirely, doesn't answer at all) — both read as stale to the caller.
    func version(reply: @escaping (String?) -> Void)

    /// Self-termination path for GUI Quit. The GUI's Quit flow first calls `unmount`/`teardown`
    /// for cleanup, then this so the privileged launchd on-demand helper doesn't linger as root
    /// after the app closes (Activity Monitor can't kill it without sudo — it must exit itself
    /// via XPC). Replies before `exit(0)`, same reason `uninstallHelper` does: a reply queued
    /// after self-termination never reaches the client, and the GUI's `await` would hang.
    /// Distinct from `uninstallHelper` (which un-blesses + bootouts the launchd job for removal);
    /// this leaves registration intact so the next app launch re-uses the same blessed helper.
    func exitHelper(reply: @escaping (Data?, String?) -> Void)
}

/// Seam for `HelperService` so unit tests can assert on the exact argv built for a request
/// without ever spawning a real (privileged) process. `RealCommandRunner` is the only
/// production implementation.
public protocol PrivilegedCommandRunning {
    func run(_ executablePath: String, _ arguments: [String]) -> CommandResult
    func runPipingStdin(_ input: String, to executablePath: String, _ arguments: [String]) -> CommandResult
}

/// Lock-protected single-value holder — lets `captureOutput`'s two background readers each
/// write their own result without Swift 6 strict concurrency flagging a shared captured `var`
/// as a data race (the two boxes below are never touched by more than one thread at a time in
/// practice, but the type system can't see that through a plain closure capture).
private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

public struct RealCommandRunner: PrivilegedCommandRunning {
    public static let timeoutExitCode: Int32 = 124

    public init() {}

    /// Drains both pipes concurrently on background queues, started *before* `waitUntilExit()`
    /// — reading them sequentially afterward (the previous shape of this code) deadlocks the
    /// instant combined stdout+stderr exceeds the ~64KB pipe buffer: the child blocks writing to
    /// a full pipe nobody is draining yet, while this thread blocks in `waitUntilExit()` waiting
    /// for a child that itself is blocked. Apple's own `Process`/`Pipe` docs call this out
    /// explicitly. Every command run through here so far produced small enough output to never
    /// hit it — `HelperService.stageCLI`'s `install.sh` (several file copies + `codesign`/`xattr`
    /// calls per binary) was the first real trigger.
    private func captureOutput(_ process: Process, _ outPipe: Pipe, _ errPipe: Pipe) -> String {
        let outBox = DataBox()
        let errBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            outBox.set(outPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.set(errPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return (String(data: outBox.get(), encoding: .utf8) ?? "") + (String(data: errBox.get(), encoding: .utf8) ?? "")
    }

    private func configureEnvironment(for process: Process) {
        var env = ProcessInfo.processInfo.environment
        if let connection = NSXPCConnection.current() {
            let uid = connection.effectiveUserIdentifier
            let gid = connection.effectiveGroupIdentifier
            let passwordEntry = getpwuid(uid)
            let username = passwordEntry.map { String(cString: $0.pointee.pw_name) }
            let homeDirectory = passwordEntry.map { String(cString: $0.pointee.pw_dir) }
            applyInvokerIdentityEnvironment(
                &env,
                uid: uid,
                gid: gid,
                username: username,
                homeDirectory: homeDirectory
            )
        }
        process.environment = env
    }

    public func run(_ executablePath: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        configureEnvironment(for: process)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CommandResult(output: "helper: failed to launch \(executablePath): \(error)", exitCode: -1)
        }
        let combined = captureOutput(process, outPipe, errPipe)
        return CommandResult(output: combined, exitCode: process.terminationStatus)
    }

    /// Runs an unprivileged or otherwise bounded command. The protocol requirement above stays
    /// unbounded because helper mount/install operations have their own lifecycle contracts; the
    /// GUI drive scanner opts into this overload so a wedged raw-device probe cannot live forever.
    /// A temporary file avoids pipe-buffer and inherited-pipe EOF traps if the child spawns its
    /// own short-lived probe subprocess before the timeout fires.
    public func run(
        _ executablePath: String,
        _ arguments: [String],
        timeout: TimeInterval
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        configureEnvironment(for: process)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntfsmac-command-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL)
        else {
            return CommandResult(output: "helper: failed to create command output file", exitCode: -1)
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }
        process.standardOutput = outputHandle
        process.standardError = outputHandle

        do {
            try process.run()
        } catch {
            return CommandResult(output: "helper: failed to launch \(executablePath): \(error)", exitCode: -1)
        }

        // Do not put `waitUntilExit()` on a background queue here. Live BB-F01 replay exposed a
        // Foundation failure mode where the child had already disappeared from the process table
        // but `waitUntilExit()` never returned. The timeout path then blocked forever in its final
        // unbounded group wait, leaving the GUI permanently on "Mounting..." after a successful
        // mount. A termination handler is the native asynchronous completion signal and lets every
        // post-timeout wait remain bounded even if Foundation fails to publish process completion.
        let processFinished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in processFinished.signal() }

        var timedOut = false
        let timeoutMilliseconds = max(1, Int(timeout * 1_000))
        if processFinished.wait(timeout: .now() + .milliseconds(timeoutMilliseconds)) == .timedOut {
            timedOut = true
            process.terminate()
            // A process stuck in a kernel-backed device operation may ignore SIGTERM. Keep the
            // caller bounded and escalate only that exact child after a short grace period. The
            // final wait is also bounded: an uninterruptible child must never wedge the caller.
            if processFinished.wait(timeout: .now() + .milliseconds(250)) == .timedOut {
                if process.isRunning {
                    _ = Darwin.kill(process.processIdentifier, SIGKILL)
                }
                _ = processFinished.wait(timeout: .now() + .milliseconds(250))
            }
        }

        try? outputHandle.synchronize()
        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        if timedOut {
            let suffix = output.isEmpty ? "" : "\n\(output)"
            return CommandResult(output: "command timed out\(suffix)", exitCode: Self.timeoutExitCode)
        }
        return CommandResult(output: output, exitCode: process.terminationStatus)
    }

    public func runPipingStdin(_ input: String, to executablePath: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        configureEnvironment(for: process)

        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return CommandResult(output: "helper: failed to launch \(executablePath): \(error)", exitCode: -1)
        }
        inPipe.fileHandleForWriting.write(input.data(using: .utf8) ?? Data())
        inPipe.fileHandleForWriting.closeFile()
        let combined = captureOutput(process, outPipe, errPipe)
        return CommandResult(output: combined, exitCode: process.terminationStatus)
    }
}

/// Implements the minimal privileged XPC surface (§3, `3-xpc-helper`'s Do clause). Every method
/// re-validates its own input before `runner` ever sees it — the helper
/// treats every caller as hostile regardless of what the GUI/CLI already checked.
public final class HelperService: NSObject, HelperXPCProtocol {
    /// One lock across every connection-owned HelperService instance. Mutating calls must not
    /// interleave a mount with teardown/staging/removal: that could erase a freshly created
    /// session anchor or delete the CLI while a privileged operation is starting.
    private static let mutationLock = NSLock()
    private let runner: PrivilegedCommandRunning
    private let resolvePrefix: @Sendable () -> String
    private let expectedCLITreeHash: String
    private let exitSink: @Sendable () -> Void
    private let retiredArtifactsPresent: @Sendable () -> Bool

    /// `ntfsmacPrefix`, when passed (tests only), pins the CLI location instead of resolving it
    /// live. Production always passes `nil` so every privileged call below re-runs
    /// `resolveNtfsmacPrefix()` fresh rather than freezing a snapshot at `HelperService.init`.
    /// That distinction matters because `main.swift` creates one `HelperService` per XPC
    /// connection, and the GUI opens several independent connections at launch
    /// (`MountController`, `RemountController`, `CLIAutoStager`, `HelperInstaller`,
    /// `HelperUninstaller` each default-construct their own `HelperClient()`) — often before
    /// first-run CLI staging (`stageCLI`) has finished writing the binary, or before a later
    /// brew relink/reinstall changes which candidate prefix is live. A snapshot taken at that
    /// early moment stayed wrong for the connection's entire lifetime with no way to recover
    /// short of relaunching the GUI. Re-resolving is two cheap `isExecutableFile` stats — worth
    /// paying on every call to never go stale. `expectedCLITreeHash` defaults to the
    /// build-time-generated manifest so production always checks against what actually shipped
    /// with this binary; tests inject their own known-good hash instead of depending on a real
    /// build having run.
    public init(
        runner: PrivilegedCommandRunning,
        ntfsmacPrefix: String? = nil,
        expectedCLITreeHash: String = GeneratedCLIManifest.expectedTreeHashHex,
        legacyArtifactsPresent: @Sendable @escaping () -> Bool = { retiredHelperArtifactsPresent() },
        exitSink: @Sendable @escaping () -> Void = { exit(0) }
    ) {
        self.runner = runner
        if let ntfsmacPrefix {
            self.resolvePrefix = { ntfsmacPrefix }
        } else {
            self.resolvePrefix = { resolveNtfsmacPrefix() }
        }
        self.expectedCLITreeHash = expectedCLITreeHash
        self.retiredArtifactsPresent = legacyArtifactsPresent
        self.exitSink = exitSink
    }

    private func encode(_ result: CommandResult, reply: (Data?, String?) -> Void) {
        guard let data = try? JSONEncoder().encode(result) else {
            reply(nil, "helper: failed to encode result")
            return
        }
        reply(data, nil)
    }

    public func checkDeviceAccess(device: String, reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard validateDevice(device) else {
            reply(nil, "rejected: device \"\(device)\" does not match \(deviceNamePattern)")
            return
        }
        let result = runner.run(
            "/bin/dd",
            ["if=/dev/r\(device)", "of=/dev/null", "bs=512", "count=1"]
        )
        encode(result, reply: reply)
    }

    public func mount(device: String, driver: String, mountPoint: String?, readOnly: Bool, reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard validateDevice(device) else {
            reply(nil, "rejected: device \"\(device)\" does not match \(deviceNamePattern)")
            return
        }
        guard let fsDriver = FsDriver(rawValue: driver) else {
            reply(nil, "rejected: unknown driver \"\(driver)\"")
            return
        }
        if let mountPoint, !isValidMountPoint(mountPoint) {
            reply(nil, "rejected: mountPoint \"\(mountPoint)\" is not a valid /Volumes/ path")
            return
        }
        var args = [device]
        if let mountPoint { args.append(mountPoint) }
        if fsDriver == .ext {
            // ext: no --fs-driver (kernel auto-detects; ntfs-3g can't mount ext4) + all_squash
            // so the macOS user can write past ext's Unix ownership. NTFS keeps --fs-driver.
            args.append("--ignore-permissions")
        } else {
            args.append(contentsOf: ["--fs-driver", fsDriver.rawValue])
        }
        if readOnly { args.append("--read-only") }
        let result = runner.run("\(resolvePrefix())/bin/ntfsmac", ["mount"] + args)
        encode(result, reply: reply)
    }

    public func unmount(target: String, reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard isValidUnmountTarget(target) else {
            reply(nil, "rejected: unmount target \"\(target)\" is neither a valid device nor a /Volumes/ path")
            return
        }
        let result = runner.run("\(resolvePrefix())/bin/ntfsmac", ["unmount", target])
        encode(result, reply: reply)
    }

    public func teardown(sessionID: String?, reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        if let sessionID, !validateDevice(sessionID) {
            reply(nil, "rejected: sessionID \"\(sessionID)\" does not match \(deviceNamePattern)")
            return
        }
        var args: [String] = []
        if let sessionID { args.append(sessionID) }
        let result = runner.run("\(resolvePrefix())/libexec/ntfsmac/lib/pf-teardown.sh", args)
        encode(result, reply: reply)
    }

    public func removeDependencies(reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard noActiveNfsMount() else {
            reply(nil, "rejected: an NFS mount is currently active — unmount it first")
            return
        }

        // Resolved once and reused for the rest of this call — every path below must agree on
        // the same prefix within one invocation (reporting one path in `removedPaths` while
        // deleting another would be its own bug), unlike `mount`/`unmount` which only ever touch
        // the prefix once each.
        let prefix = resolvePrefix()
        // Reconcile rather than flushing every record. If another non-XPC CLI mount appears,
        // active state is preserved and the second mount-table check below aborts removal.
        let cleanup = runner.run("\(prefix)/libexec/ntfsmac/lib/pf-teardown.sh", [])
        guard cleanup.exitCode == 0,
              !cleanup.output.contains("=unknown"),
              !cleanup.output.contains("=notEnforced")
        else {
            reply(nil, "rejected: session security cleanup could not be proven")
            return
        }

        // Re-check immediately before the destructive delete, not just once at the top — a
        // concurrent `mount(...)` XPC call could land in the gap between the first check and
        // here (a fresh `HelperService` per connection, no shared lock). Narrows, doesn't
        // eliminate, the TOCTOU window; this project's own priority ordering ("security and
        // connection stability outrank speed") calls for the extra check over skipping it.
        guard noActiveNfsMount() else {
            reply(nil, "rejected: an NFS mount became active — aborting before removing files")
            return
        }

        var removedPaths = [prefix]
        _ = runner.run("/bin/rm", ["-rf", prefix])

        // install.sh's own PATH convenience (`/usr/local/bin/ntfsmac` -> `installPrefix`/bin/
        // ntfsmac) is never created by the brew tap — brew manages its own `opt/homebrew/bin`
        // symlink and removes it itself on `brew uninstall`. Only clean up the one *we* might
        // have created, and only if it still points where we'd have pointed it — never blow
        // away an unrelated file a user happens to have at that path. Checked against the
        // fixed `installPrefix` constant (not `ntfsmacPrefix`): that symlink only ever targets
        // the install.sh layout, regardless of which prefix this helper resolved as active.
        let pathSymlink = "/usr/local/bin/ntfsmac"
        let linkTarget = runner.run("/bin/readlink", [pathSymlink])
        if linkTarget.exitCode == 0,
           linkTarget.output.trimmingCharacters(in: .whitespacesAndNewlines) == "\(installPrefix)/bin/ntfsmac" {
            removedPaths.append(pathSymlink)
            _ = runner.run("/bin/rm", ["-f", pathSymlink])
        }

        if let home = Self.invokingUserHomeDirectory() {
            let cachePath = home.appendingPathComponent(".anylinuxfs").path
            removedPaths.append(cachePath)
            _ = runner.run("/bin/rm", ["-rf", cachePath])

            let logsDir = home.appendingPathComponent("Library/Logs")
            let logFiles = (try? FileManager.default.contentsOfDirectory(atPath: logsDir.path)) ?? []
            let matchingLogs = logFiles
                .filter { $0.hasPrefix("anylinuxfs") && $0.hasSuffix(".log") }
                .map { logsDir.appendingPathComponent($0).path }
            if !matchingLogs.isEmpty {
                removedPaths.append(contentsOf: matchingLogs)
                _ = runner.run("/bin/rm", ["-f"] + matchingLogs)
            }
        }

        encode(CommandResult(output: removedPaths.joined(separator: "\n"), exitCode: 0), reply: reply)
    }

    private func noActiveNfsMount() -> Bool {
        runner.run("/sbin/mount", ["-t", "nfs"]).output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func stageCLI(installScriptPath: String, reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        guard isValidStageCLIPath(installScriptPath) else {
            reply(nil, "rejected: installScriptPath \"\(installScriptPath)\" is not a bundled install.sh")
            return
        }
        // Resolve symlinks before either check below — a component could be swapped between an
        // earlier look and this one otherwise (the same TOCTOU class `removeDependencies`'
        // immediate-recheck-before-delete already guards against elsewhere in this file).
        let resolvedScriptPath = URL(fileURLWithPath: installScriptPath).resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: resolvedScriptPath.path) else {
            reply(nil, "rejected: \(installScriptPath) does not exist or isn't executable")
            return
        }
        let cliSrcDir = resolvedScriptPath.deletingLastPathComponent()
        guard let actualHash = computeTreeHash(at: cliSrcDir), actualHash == expectedCLITreeHash else {
            reply(nil, "rejected: cli-src content does not match the hash pinned into this helper at build time — refusing (possible tampering)")
            return
        }
        // A pre-v3 job normally goes through `SMJobRemove` before this helper is blessed. If
        // launchd has already forgotten that job but its root-owned files remain, the
        // unprivileged installer cannot see it through `SMJobCopyDictionary` and cannot delete
        // it directly. This newly blessed root helper is the first safe place to finish that
        // one-way migration. Run only after the bundled CLI tree has passed its integrity pin.
        let cleanup = removeRetiredHelperArtifacts()
        guard cleanup.exitCode == 0 else {
            encode(cleanup, reply: reply)
            return
        }
        // Idempotency: if the installed CLI tree already matches this helper's pinned hash, skip
        // the reinstall. Without this, a new app build re-blesses the helper but `CLIAutoStager`
        // never re-stages (it skips on "any ntfsmac installed"), so the installed `ntfsmac` stays
        // stale and rejects flags the new helper sends (e.g. --ignore-permissions). The marker is
        // written by this helper after a successful install, so a mismatch/missing marker means
        // "stale or first run" → run install.sh, then refresh the marker.
        let markerPath = "\(installPrefix)/libexec/ntfsmac/cli-tree.sha256"
        if let marker = try? String(contentsOfFile: markerPath, encoding: .utf8),
           marker.trimmingCharacters(in: .whitespacesAndNewlines) == expectedCLITreeHash {
            encode(CommandResult(output: "cli already current", exitCode: 0), reply: reply)
            return
        }
        let result = runner.run(resolvedScriptPath.path, ["--no-path-link"])
        if result.exitCode == 0 {
            try? expectedCLITreeHash.write(toFile: markerPath, atomically: true, encoding: .utf8)
        }
        encode(result, reply: reply)
    }

    public func version(reply: @escaping (String?) -> Void) {
        reply(helperBuildIdentity(cliTreeHash: expectedCLITreeHash))
    }

    public func uninstallHelper(reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }

        #if NTFSMAC_LEGACY_HELPER
        // A Legacy complete uninstall owns both its current standalone helper and any pre-v3
        // orphan. Unlike the standard replacement path below, there is no separate embedded
        // generation whose health must be proved before this cleanup.
        let cleanup = removeRetiredHelperArtifacts()
        guard cleanup.exitCode == 0 else {
            encode(cleanup, reply: reply)
            return
        }
        let label = helperMachServiceName
        _ = runner.run("/bin/rm", ["-f", "/Library/LaunchDaemons/\(label).plist"])
        // Deleting our own running binary is safe on Unix — the inode stays valid until this
        // process exits.
        let removeBinary = runner.run("/bin/rm", ["-f", "/Library/PrivilegedHelperTools/\(label)"])
        _ = runner.run("/usr/bin/tccutil", ["reset", "SystemPolicyAllFiles", label])
        _ = runner.run("/usr/bin/tccutil", ["reset", "All", label])
        encode(removeBinary, reply: reply)
        // `bootout` sends this very process a kill signal and (per its documented semantics)
        // can finish tearing the process down before a reply queued *after* it would ever reach
        // the client — confirmed live as the actual cause of "can't communicate with helper" on
        // every uninstall attempt on a real second Mac (this bug reproduces independent of the
        // app's install path or quarantine state; it's a self-inflicted race, not either of
        // those). Replying first, then self-terminating last, is the fix: nothing after this
        // point should assume the helper is still reachable.
        _ = runner.run("/bin/launchctl", ["bootout", "system/\(label)"])
        #else
        // The modern daemon lives inside the signed app bundle. It must never delete itself or a
        // system plist. It also deliberately leaves Legacy untouched here: HelperInstaller uses
        // this selector while replacing a stale modern generation, before the replacement has
        // proved healthy. The explicit post-health cleanup selector and the GUI's complete
        // uninstall adapter own retired-helper removal at their safe transaction boundaries.
        // The unprivileged app calls SMAppService.unregister() immediately after this preparation
        // reply, and macOS terminates the embedded service atomically.
        encode(CommandResult(output: "modern helper ready to unregister", exitCode: 0), reply: reply)
        #endif
    }

    public func cleanupRetiredHelpers(reply: @escaping (Data?, String?) -> Void) {
        Self.mutationLock.lock()
        defer { Self.mutationLock.unlock() }
        encode(removeRetiredHelperArtifacts(), reply: reply)
    }

    /// Best-effort removal is followed by explicit postcondition checks. `rm -f` alone is not
    /// evidence that launchd released a job or that a previously running standalone helper died.
    /// The labels and paths below are compile-time constants, never caller-controlled input.
    private func removeRetiredHelperArtifacts() -> CommandResult {
        guard retiredArtifactsPresent() else {
            return CommandResult(output: "No previous ntfsmac Helper found.", exitCode: 0)
        }
        var failures: [String] = []
        for label in retiredHelperMachServiceNames {
            let plistPath = "/Library/LaunchDaemons/\(label).plist"
            let executablePath = "/Library/PrivilegedHelperTools/\(label)"

            // `bootout` is intentionally best-effort: an orphaned-file migration has no job.
            _ = runner.run("/bin/launchctl", ["bootout", "system/\(label)"])
            let removePlist = runner.run("/bin/rm", ["-f", plistPath])
            let removeExecutable = runner.run("/bin/rm", ["-f", executablePath])
            _ = runner.run("/usr/bin/tccutil", ["reset", "SystemPolicyAllFiles", label])
            _ = runner.run("/usr/bin/tccutil", ["reset", "All", label])

            let registeredJob = runner.run("/bin/launchctl", ["print", "system/\(label)"])
            let runningProcess = runner.run("/usr/bin/pgrep", ["-f", "-x", executablePath])
            if removePlist.exitCode != 0 || removeExecutable.exitCode != 0
                || registeredJob.exitCode == 0 || runningProcess.exitCode == 0 {
                failures.append(label)
            }
        }
        guard failures.isEmpty else {
            return CommandResult(
                output: "The previous ntfsmac Helper could not be removed completely. Retry from Settings.",
                exitCode: 1
            )
        }
        return CommandResult(output: "Previous ntfsmac Helper removed.", exitCode: 0)
    }

    public func exitHelper(reply: @escaping (Data?, String?) -> Void) {
        // Reply with the same decodable CommandResult envelope as every other Data-returning XPC
        // method, then self-terminate. An empty Data payload made HelperClient correctly throw a
        // decode error even though the helper had acknowledged the call, preventing a strict Quit
        // postcondition from distinguishing success from a dropped connection.
        encode(CommandResult(output: "ntfsmac Helper stopped.", exitCode: 0), reply: reply)
        exitSink()
    }

    /// The GUI runs unprivileged as the real logged-in user; this helper runs as root under
    /// launchd, so `NSHomeDirectory()`/`$HOME` here would resolve to *root's* home, not the
    /// user's. `NSXPCConnection.current()` returns the connection driving the call presently in
    /// flight (Apple's documented pattern for this), and `effectiveUserIdentifier` is a
    /// kernel-verified peer credential — not client-supplied data, so it can't be spoofed by a
    /// malicious message the way a plain parameter could. Mirrors anylinuxfs's own
    /// `home_dir_from_uid` (`vendor/.../anylinuxfs/src/main.rs`) — same problem, same class of
    /// solution.
    private static func invokingUserHomeDirectory() -> URL? {
        guard let uid = NSXPCConnection.current()?.effectiveUserIdentifier,
              let pw = getpwuid(uid), let dir = pw.pointee.pw_dir
        else { return nil }
        return URL(fileURLWithPath: String(cString: dir))
    }
}

/// Best-effort caller-identity check. Ad-hoc signing (L4 — no paid Developer account, no
/// notarization) means there is no trusted certificate chain to pin against: this only confirms
/// the connecting process's own code-signed identifier, which any locally ad-hoc-signed binary
/// can also claim. The load-bearing security control is per-call input validation above
/// (`validateDevice`/`isValidUnmountTarget`), not this check — documented here so it isn't
/// mistaken for a strong boundary later.
public func verifyClientIdentity(pid: pid_t, expectedIdentifier: String) -> Bool {
    var code: SecCode?
    let attributes = [kSecGuestAttributePid: pid] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code else {
        return false
    }
    var requirement: SecRequirement?
    let requirementString = "identifier \"\(expectedIdentifier)\"" as CFString
    guard SecRequirementCreateWithString(requirementString, [], &requirement) == errSecSuccess,
          let requirement else {
        return false
    }
    return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
}
