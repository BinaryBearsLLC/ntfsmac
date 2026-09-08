import AppKit
import Foundation

public enum MacOSValidationPolicy {
    public static let issueURL = URL(string: "https://github.com/BinaryBearsLLC/ntfsmac/issues/new/choose")!
    public static let acknowledgementKey = "ntfsmac.unvalidated-macos.noticeAcknowledged"

    public static func shouldPresent(isValidated: Bool, defaults: UserDefaults) -> Bool {
        !isValidated && !defaults.bool(forKey: acknowledgementKey)
    }

    public static func isValidated(release: String, build: String, architecture: String,
                                   os: String, manifest: String) -> Bool {
        let fields = [release, build, architecture, os]
        guard fields.allSatisfy({ !$0.isEmpty && $0 != "unknown" && $0 != "Unknown"
            && $0.rangeOfCharacter(from: .whitespacesAndNewlines) == nil }) else { return false }
        return manifest.split(separator: "\n").contains {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return !line.hasPrefix("#") && line.split(whereSeparator: { $0.isWhitespace }).map(String.init) == fields
        }
    }

}

@MainActor
public enum MacOSValidationNotice {
    public static func presentIfNeeded(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        let product = ProductVersion.current(bundle: bundle)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let os = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let manifestURL = bundle.resourceURL?.appendingPathComponent("cli-src/cli/lib/macos-validated-builds.txt")
        let manifest = manifestURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "unknown"
        #endif
        let validated = MacOSValidationPolicy.isValidated(release: product.release, build: product.build,
            architecture: architecture, os: os, manifest: manifest)
        let key = MacOSValidationPolicy.acknowledgementKey
        guard MacOSValidationPolicy.shouldPresent(isValidated: validated, defaults: defaults) else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "This macOS version has not been fully validated"
        alert.informativeText = "ntfsmac \(product.release) (\(product.build)) has not completed testing on macOS \(os). This does not mean it is incompatible.\n\nIf you encounter a problem, open an issue at github.com/BinaryBearsLLC/ntfsmac/issues. Describe what happened and attach a diagnostic JSON: hold Command (⌘) while clicking Diagnose to save it. Nothing is uploaded automatically.\n\nThis notice is shown only once."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Open GitHub Issues")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        defaults.set(true, forKey: key)
        if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(MacOSValidationPolicy.issueURL)
        }
    }
}
