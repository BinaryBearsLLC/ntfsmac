import Foundation
import Testing
@testable import NtfsmacGUI

private let developerJSON = """
{"diagnostic_schema":2,"healthy":false,"ntfsmac_version":"1.0","build_version":"1","macos_version":"26.5","architecture":"arm64","helper_installed":true,"missing_binaries":1,"missing_components":["vmproxy"],"quarantined_binaries":0,"quarantined_components":[],"kernel_pin":"match","bridge":"down","vpn_default_route":true,"nfs_mount_count":2}
"""

@Test func commandModifierSelectsDeveloperExportWithoutChangingNormalClick() {
    #expect(DiagnoseActionMode.resolve(commandPressed: false) == .summary)
    #expect(DiagnoseActionMode.resolve(commandPressed: true) == .developerJSONExport)
}

@Test func developerDocumentValidatesFormatsAndPreservesEveryCLIField() throws {
    let document = try DeveloperDiagnoseDocument(rawJSON: developerJSON)
    #expect(document.data.last == 0x0A)

    let object = try JSONSerialization.jsonObject(with: document.data) as? [String: Any]
    #expect(object?["diagnostic_schema"] as? Int == 2)
    #expect(object?["healthy"] as? Bool == false)
    #expect(object?["ntfsmac_version"] as? String == "1.0")
    #expect(object?["build_version"] as? String == "1")
    #expect(object?["macos_version"] as? String == "26.5")
    #expect(object?["architecture"] as? String == "arm64")
    #expect(object?["helper_installed"] as? Bool == true)
    #expect(object?["missing_binaries"] as? Int == 1)
    #expect(object?["missing_components"] as? [String] == ["vmproxy"])
    #expect(object?["quarantined_binaries"] as? Int == 0)
    #expect(object?["quarantined_components"] as? [String] == [])
    #expect(object?["kernel_pin"] as? String == "match")
    #expect(object?["bridge"] as? String == "down")
    #expect(object?["vpn_default_route"] as? Bool == true)
    #expect(object?["nfs_mount_count"] as? Int == 2)

    let forbiddenKeys = [
        "username", "serial", "hardware_model", "volume_labels", "device_identifiers",
        "mount_paths", "vpn_provider", "vpn_interface", "ip_addresses", "dns_servers", "routes",
    ]
    #expect(forbiddenKeys.allSatisfy { object?[$0] == nil })
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
