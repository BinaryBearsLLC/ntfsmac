import AppKit
import Foundation
import UniformTypeIdentifiers

/// Diagnose keeps its normal one-click behavior. Holding Command selects the support-oriented
/// path without adding another visible control to the compact menu-bar UI.
public enum DiagnoseActionMode: Equatable, Sendable {
    case summary
    case developerJSONExport

    public static func resolve(commandPressed: Bool) -> Self {
        commandPressed ? .developerJSONExport : .summary
    }
}

public enum DeveloperDiagnoseExportError: LocalizedError, Equatable {
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "The developer diagnostic did not contain valid JSON."
        }
    }
}

/// A user-controlled, local-only copy of the existing `ntfsmac diagnose --json` result.
/// JSONSerialization validates the CLI output and formats it for a useful bug-report attachment;
/// it does not add, remove, or upload diagnostic fields.
public struct DeveloperDiagnoseDocument: Equatable, Sendable {
    public let data: Data

    public init(rawJSON: String) throws {
        guard let rawData = rawJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: rawData),
              JSONSerialization.isValidJSONObject(object),
              var formatted = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              )
        else {
            throw DeveloperDiagnoseExportError.invalidJSON
        }

        // Text attachments are friendlier to command-line tools and GitHub previews when they
        // end in a newline. JSONSerialization does not append one itself.
        formatted.append(0x0A)
        data = formatted
    }

    public func write(to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }

    public static func suggestedFilename(
        at date: Date = Date(),
        timeZone: TimeZone = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "ntfsmac-diagnose-\(formatter.string(from: date)).json"
    }
}

/// The only AppKit-specific part of the feature. The user chooses the destination, cancellation
/// is a no-op, and a write failure is reported locally. No diagnostic is transmitted anywhere.
@MainActor
public enum DeveloperDiagnoseSavePanel {
    public static func present(document: DeveloperDiagnoseDocument) {
        let panel = NSSavePanel()
        panel.title = "Save Developer Diagnostic"
        panel.message = "Save this JSON file, then attach it manually when reporting an ntfsmac issue."
        panel.nameFieldStringValue = DeveloperDiagnoseDocument.suggestedFilename()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            try document.write(to: destination)
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Developer diagnostic could not be saved"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
