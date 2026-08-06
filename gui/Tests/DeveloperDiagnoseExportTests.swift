import Foundation
import Testing
@testable import NtfsmacGUI

private let developerJSON = """
{"diagnostic_schema":5,"healthy":false,"ntfsmac_version":"1.0","build_version":"1","macos_version":"26.5","architecture":"arm64","helper_installed":true,"missing_binaries":1,"missing_components":["vmproxy"],"quarantined_binaries":0,"quarantined_components":[],"kernel_pin":"match","anylinuxfs_version":"0.18.0","anylinuxfs_expected_version":"0.18.0","anylinuxfs_version_status":"match","anylinuxfs_source_commit":"8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3","vmproxy_source_version":"0.18.0","libkrun_version":"1.19.3","libkrunfw_version":"v6.12.62-rev1","gvproxy_version":"v0.8.9","gvproxy_expected_version":"v0.8.9","gvproxy_version_status":"match","gvproxy_source_commit":"9cfc86f66679ef0feed0f20ba1df558fe2bef5c6","vmnet_helper_version":"v0.12.0","vmnet_helper_expected_version":"v0.12.0","vmnet_helper_version_status":"match","vmnet_helper_source_commit":"0caef043005c7d9f03422a9914bc9d3d4637dc84","alpine_runtime_tag":"3.23.5","alpine_runtime_digest":"sha256:d858bb5442632a31bd4bca6c5e601dbe6b536fd7942092ea6a08a0a95805693c","alpine_runtime_state":"migration_available","alpine_installed_cache":"legacy","alpine_installed_version":"3.24.1","ntfs_3g_version":"2026.2.25-r0","nfs_utils_version":"2.6.4-r6","bridge":"down","network_helper":"gvproxy","nfs_transport_contract":"loopback_proxy","vpn_default_route":true,"nfs_mount_count":2}
"""

@Test func commandModifierSelectsDeveloperExportWithoutChangingNormalClick() {
    #expect(DiagnoseActionMode.resolve(commandPressed: false) == .summary)
    #expect(DiagnoseActionMode.resolve(commandPressed: true) == .developerJSONExport)
}

@Test func developerDocumentValidatesFormatsAndPreservesEveryCLIField() throws {
    let document = try DeveloperDiagnoseDocument(rawJSON: developerJSON)
    #expect(document.data.last == 0x0A)

    let object = try JSONSerialization.jsonObject(with: document.data) as? [String: Any]
    #expect(object?["diagnostic_schema"] as? Int == 5)
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
    #expect(object?["anylinuxfs_source_commit"] as? String == "8aa9ccd6504e64ca26ce769c1623ed1741c6b7d3")
    #expect(object?["alpine_installed_version"] as? String == "3.24.1")
    #expect(object?["ntfs_3g_version"] as? String == "2026.2.25-r0")
    #expect(object?["nfs_utils_version"] as? String == "2.6.4-r6")
    #expect(object?["bridge"] as? String == "down")
    #expect(object?["network_helper"] as? String == "gvproxy")
    #expect(object?["nfs_transport_contract"] as? String == "loopback_proxy")
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
