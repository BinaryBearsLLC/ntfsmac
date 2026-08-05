import Foundation

/// Navigation local to the menu-bar popover. Keeping this state in the popover's view graph lets
/// every entry point (normal content, first run, and CLI repair) open the same Settings page while
/// retaining the app-owned Settings/helper objects that are already in flight.
@MainActor
public final class PopoverNavigation: ObservableObject {
    public enum Page: Equatable, Sendable {
        case main
        case settings
    }

    @Published public private(set) var page: Page = .main

    public init() {}

    public func showSettings() {
        page = .settings
    }

    public func showMain() {
        page = .main
    }
}
