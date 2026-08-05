import Foundation
import Testing
@testable import NtfsmacGUI

private let developerJSON = """
{"healthy":false,"macos_version":"26.5","missing_binaries":0,"quarantined_binaries":0,"kernel_pin":"match","bridge":"down"}
"""

@Test func commandModifierSelectsDeveloperExportWithoutChangingNormalClick() {
    #expect(DiagnoseActionMode.resolve(commandPressed: false) == .summary)
    #expect(DiagnoseActionMode.resolve(commandPressed: true) == .developerJSONExport)
}

@Test func developerDocumentValidatesFormatsAndPreservesEveryCLIField() throws {
    let document = try DeveloperDiagnoseDocument(rawJSON: developerJSON)
    #expect(document.data.last == 0x0A)

    let object = try JSONSerialization.jsonObject(with: document.data) as? [String: Any]
    #expect(object?["healthy"] as? Bool == false)
    #expect(object?["macos_version"] as? String == "26.5")
    #expect(object?["missing_binaries"] as? Int == 0)
    #expect(object?["quarantined_binaries"] as? Int == 0)
    #expect(object?["kernel_pin"] as? String == "match")
    #expect(object?["bridge"] as? String == "down")
}

@Test func malformedDeveloperOutputIsRejected() {
    #expect(throws: DeveloperDiagnoseExportError.invalidJSON) {
        try DeveloperDiagnoseDocument(rawJSON: "diagnose failed")
    }
}

@Test func suggestedFilenameIsStableAndJsonSpecific() {
    let utc = TimeZone(secondsFromGMT: 0)!
    #expect(
        DeveloperDiagnoseDocument.suggestedFilename(
            at: Date(timeIntervalSince1970: 0),
            timeZone: utc
        ) == "ntfsmac-diagnose-19700101-000000.json"
    )
}

@Test func documentWritesOnlyToTheExplicitDestination() throws {
    let document = try DeveloperDiagnoseDocument(rawJSON: developerJSON)
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("ntfsmac-developer-export-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: destination) }

    try document.write(to: destination)

    #expect(FileManager.default.fileExists(atPath: destination.path))
    #expect(try Data(contentsOf: destination) == document.data)
}
