import Testing
@testable import NtfsmacGUI

// GUI-PLAN.md v1 feature 5. Acceptance: assert on/off/unknown rendering per indicator — the
// critical safety property is that "off"/"unknown" never render with the "enforced" checkmark.

@Test func enforcedShowsGreenCheckmark() {
    let style = SecurityIndicator.style(for: .enforced, label: "Isolated network")
    #expect(style.symbolName == "checkmark.shield.fill")
    #expect(style.color == .ntfsGreen)
    #expect(style.text == "Isolated network: enforced")
}

@Test func notEnforcedNeverShowsCheckmarkOrGreen() {
    let style = SecurityIndicator.style(for: .notEnforced, label: "Isolated network")
    #expect(style.symbolName != "checkmark.shield.fill")
    #expect(style.color != .ntfsGreen)
    #expect(style.text.contains("not enforced"))
}

@Test func unknownNeverShowsCheckmarkOrGreen() {
    let style = SecurityIndicator.style(for: .unknown, label: "VPN bypass")
    #expect(style.symbolName != "checkmark.shield.fill")
    #expect(style.color != .ntfsGreen)
    #expect(style.text.contains("unknown"))
}

@Test func notRequiredIsDistinctAndNeverPresentedAsEnforced() {
    let style = SecurityIndicator.style(for: .notRequired, label: "VPN-safe route")
    #expect(style.symbolName == "checkmark.shield.fill")
    #expect(style.color == .ntfsBlue)
    #expect(style.text == "VPN-safe route: not required")
}

@Test func allNonEnforcedStatusesAreDistinguishableFromEachOther() {
    let notEnforced = SecurityIndicator.style(for: .notEnforced, label: "X")
    let unknown = SecurityIndicator.style(for: .unknown, label: "X")
    let notRequired = SecurityIndicator.style(for: .notRequired, label: "X")
    #expect(notEnforced.symbolName != unknown.symbolName)
    #expect(notEnforced.color != unknown.color)
    #expect(notRequired.color != notEnforced.color)
    #expect(notRequired.color != unknown.color)
}

@Test func labelIsThreadedThroughForEachIndicatorIndependently() {
    #expect(SecurityIndicator.style(for: .enforced, label: "Isolated network").text == "Isolated network: enforced")
    #expect(SecurityIndicator.style(for: .enforced, label: "VPN bypass").text == "VPN bypass: enforced")
}

@Test func securityHideAndShowChangePresentationOnly() {
    var presentation = SecurityIndicatorsPresentation()
    #expect(presentation.isVisible)
    presentation.hide()
    #expect(!presentation.isVisible)
    presentation.show()
    #expect(presentation.isVisible)
}
