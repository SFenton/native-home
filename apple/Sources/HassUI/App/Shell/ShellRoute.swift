import Foundation
import SwiftUI

/// A page the shell pushed on a section's stack, in a form that can be written down. The stacks themselves are
/// ``SwiftUI/NavigationPath``s, which cannot be read; ``ShellNavigator`` keeps this list beside each path so Quick Links can
/// pop to a page that is already open and a cold launch can put the stack back (``RouteRestore``).
enum ShellRoute: Hashable, Codable, Sendable {
    /// A Home page (`HomeRoute`): a room, Media, Vacuums and the rest.
    case home(HomeRoute)
    /// A household settings topic.
    case household(HouseholdSettingsPage)
    /// Another Settings page.
    case settings(SettingsRoute)
    /// A Chores page opened from the Chores tab's quick links (`ChoresConfig.Page.id`: Your Chores, Unassigned, Groceries ...). Where the
    /// window splits it is a column beside the Chores list; elsewhere a push (owner, 2026-11-01).
    case chores(String)
    /// A Food space (Fridge, Pantry, Freezer, All Food ...) opened from the Food hub: a column beside the hub where the window splits,
    /// else a push. The associated value is the space's `InventorySpace.rawValue`.
    case foodSpace(String)

    /// Pushes this route's value onto a path.
    func append(to path: inout NavigationPath) {
        switch self {
        case let .home(route): path.append(route)
        case let .household(page): path.append(page)
        case let .settings(route): path.append(route)
        case let .chores(id): path.append(id)
        case let .foodSpace(space): path.append(space)
        }
    }
}

/// Which of a section's trailing routes the top page shows as columns where the window splits (the UIKit port's
/// ``UKColumnsViewController``) instead of as pushed pages.
enum ColumnRouting {
    /// Whether a route belongs to a section root that hosts columns (Settings' pages, Chores' quick-link pages).
    static func isRootHosted(_ route: ShellRoute) -> Bool {
        switch route {
        case .settings, .household, .chores: true
        case .home, .foodSpace: false
        }
    }

    /// How many trailing routes are columns.
    /// - Parameters:
    ///   - routes: The section's routes, bottom first; a nil slot is a page the navigator did not push, which nothing hosts.
    ///   - splitting: Whether the window splits (``SplitPolicy``).
    ///   - rootHostsColumns: Whether the section's root page hosts columns.
    /// - Returns: Every route when the root hosts them and all of them are its own; else the Food spaces that directly follow the Food hub
    ///   (the hub's route is the page before them). Zero in a window that does not split.
    static func hostedCount(in routes: [ShellRoute?], splitting: Bool, rootHostsColumns: Bool) -> Int {
        guard splitting, !routes.isEmpty, routes.allSatisfy({ $0 != nil }) else { return 0 }
        let known = routes.compactMap { $0 }
        if known.allSatisfy(isRootHosted) { return rootHostsColumns ? known.count : 0 }
        var count = 0
        for route in known.reversed() {
            guard case .foodSpace = route else { break }
            count += 1
        }
        guard count > 0, known.count > count, known[known.count - count - 1] == .home(.food) else { return 0 }
        return count
    }
}

/// Which pushed pages a cold launch puts back (design: `.agents/design/mockups/proposals/navigation-flows/`, decided
/// 2026-10-24: restore the pushed route only within 30 minutes; rooms, sheets and scroll offsets are not restored).
enum RouteRestore {
    /// How long after the person last used the app its pushed pages are still put back.
    static let window: TimeInterval = 30 * 60

    /// Whether routes saved at `savedAt` (seconds since 1970; 0 when never saved) are still fresh at `now`.
    static func isFresh(savedAt: TimeInterval, now: Date = Date()) -> Bool {
        let age = now.timeIntervalSince1970 - savedAt
        return savedAt > 0 && age >= 0 && age <= window
    }

    /// The routes as bytes for `SceneStorage`; nil when there is nothing to keep.
    static func encode(_ routes: [AppSection: [ShellRoute]]) -> Data? {
        let kept = routes.filter { !$0.value.isEmpty }
        guard !kept.isEmpty else { return nil }
        return try? JSONEncoder().encode(Dictionary(uniqueKeysWithValues: kept.map { ($0.key.rawValue, $0.value) }))
    }

    /// The routes written by ``encode(_:)``; empty when the bytes are missing or no longer decode (a route renamed by an update).
    static func decode(_ data: Data?) -> [AppSection: [ShellRoute]] {
        guard let data, let raw = try? JSONDecoder().decode([String: [ShellRoute]].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in AppSection(rawValue: key).map { ($0, value) } })
    }
}
