import Testing
@testable import NtfsmacGUI

private let enforcedSecurityStatus = """
schema=1
active_sessions=1
private_link=enforced
private_reason=PRIVATE_VMNET_SOFT
vpn_route=notRequired
vpn_route_reason=ROUTE_ALREADY_PRIVATE
pf_policy=enforced
pf_reason=PF_EVALUATED
overall=enforced
overall_reason=SECURITY_ENFORCED
"""

@Test func securityStatusParserPreservesStatesAndPrivacySafeReasons() {
    let snapshot = SecurityStatusFileParser.parse(enforcedSecurityStatus)

    #expect(snapshot?.activeSessions == 1)
    #expect(snapshot?.privateLink == .init(status: .enforced, reason: "PRIVATE_VMNET_SOFT"))
    #expect(snapshot?.vpnRoute == .init(status: .notRequired, reason: "ROUTE_ALREADY_PRIVATE"))
    #expect(snapshot?.pfPolicy == .init(status: .enforced, reason: "PF_EVALUATED"))
}

@Test func securityStatusParserRejectsUnknownIdentityAndFreeFormFields() {
    #expect(SecurityStatusFileParser.parse(enforcedSecurityStatus + "device=disk2s1\n") == nil)
    #expect(SecurityStatusFileParser.parse(enforcedSecurityStatus.replacingOccurrences(of: "PF_EVALUATED", with: "PF evaluated on bridge100")) == nil)
    #expect(SecurityStatusFileParser.parse(enforcedSecurityStatus.replacingOccurrences(of: "active_sessions=1", with: "active_sessions=-1")) == nil)
}

@MainActor
@Test func securityStatusReaderFailsClosedAndRecoversOnRefresh() {
    var contents: String?
    let reader = SecurityStatusReader(path: "/fixture/status", load: { _ in contents })

    reader.refresh()
    #expect(reader.snapshot == .unknown)

    contents = enforcedSecurityStatus
    reader.refresh()
    #expect(reader.snapshot.overall.status == .enforced)

    contents = "malformed"
    reader.refresh()
    #expect(reader.snapshot == .unknown)
}
