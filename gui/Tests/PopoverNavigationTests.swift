import Testing
@testable import NtfsmacGUI

@MainActor
@Test func popoverNavigationStartsOnMainAndSupportsRoundTrip() {
    let navigation = PopoverNavigation()

    #expect(navigation.page == .main)

    navigation.showSettings()
    #expect(navigation.page == .settings)

    navigation.showMain()
    #expect(navigation.page == .main)
}

@MainActor
@Test func repeatedNavigationRequestsAreIdempotent() {
    let navigation = PopoverNavigation()

    navigation.showSettings()
    navigation.showSettings()
    #expect(navigation.page == .settings)

    navigation.showMain()
    navigation.showMain()
    #expect(navigation.page == .main)
}
