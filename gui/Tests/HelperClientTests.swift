import Foundation
import Testing
import HelperShared
@testable import NtfsmacGUI

private final class ConnectionFactoryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCallCount = 0

    var callCount: Int {
        lock.withLock { storedCallCount }
    }

    func makeConnection(machServiceName: String) -> NSXPCConnection {
        lock.withLock { storedCallCount += 1 }
        return NSXPCConnection(machServiceName: machServiceName, options: .privileged)
    }
}

@MainActor
@Test func filesystemProbeRejectsInvalidDeviceBeforeOpeningXPC() async {
    let probe = ConnectionFactoryProbe()
    let client = HelperClient(machServiceName: "com.binarybears.ntfsmac.tests.no-probe",
                              connectionFactory: probe.makeConnection(machServiceName:))
    do {
        _ = try await client.probeFilesystem(device: "/dev/disk4s2")
        Issue.record("raw paths must be rejected")
    } catch HelperClientError.invalidDevice { } catch { Issue.record("unexpected error: \(error)") }
    #expect(probe.callCount == 0)
}

@MainActor
@Test func helperClientDoesNotConnectBeforeTheFirstPrivilegedRequest() {
    let probe = ConnectionFactoryProbe()
    let client = HelperClient(
        machServiceName: "com.binarybears.ntfsmac.tests.lazy-helper",
        connectionFactory: probe.makeConnection(machServiceName:)
    )

    #expect(probe.callCount == 0, "constructing the app before first-run install must not bootstrap XPC")
    withExtendedLifetime(client) {}
    #expect(probe.callCount == 0)
}
