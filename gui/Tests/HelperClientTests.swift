import Foundation
import Testing
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
@Test func helperClientDoesNotConnectBeforeTheFirstPrivilegedRequest() {
    let probe = ConnectionFactoryProbe()
    let client = HelperClient(
        machServiceName: "com.khr898.ntfsmac.tests.lazy-helper",
        connectionFactory: probe.makeConnection(machServiceName:)
    )

    #expect(probe.callCount == 0, "constructing the app before first-run install must not bootstrap XPC")
    withExtendedLifetime(client) {}
    #expect(probe.callCount == 0)
}
