import HassCore
import Observation
import SwiftUI

/// Root navigation state shared by the tab bar, the flyout and every section stack.
///
/// The root owns selection and each section's path, so the flyout and toolbar only emit intents
/// (FestivalNativeApps `DrawerIntent` model).
@MainActor
@Observable
final class ShellNavigator {
    /// The selected root section.
    var selection: AppSection
    /// Each section's push path; a section at its root has an empty path.
    var paths: [AppSection: NavigationPath] = [:]
    /// The section whose stack is presenting the Quick Links sheet (header button, flyout row), or nil. The sheet
    /// opens over the selected section so a page it links pushes on that section's stack.
    var quickLinksSection: AppSection?
    /// The section whose stack is presenting the Account sheet (the header's Profile button), or nil.
    var accountSection: AppSection?
    /// A sheet a link asked a room page to open (a Live Activity tap on a vacuum): the page and the card's `sheet`.
    /// The room page takes it with ``takeSheet(forPage:)`` once it is on screen.
    private(set) var pendingSheet: PendingSheet?
    /// The flyout is showing.
    private(set) var isFlyoutOpen = false
    /// The signed-in user's display name for the profile button, kept between launches so the button never
    /// changes after the first frame (``ProfileButton``).
    var profileName: String? = UserDefaults.standard.string(forKey: ShellNavigator.profileNameKey) {
        didSet { UserDefaults.standard.set(profileName, forKey: Self.profileNameKey) }
    }
    /// Defaults key for ``profileName``.
    nonisolated static let profileNameKey = RememberedAccountStore.nameKey
    /// Overdue chore count for the Chores badge (web `useDailyReportContext().overdueCount`);
    /// nil until the Chores feature provides it.
    var overdueChores: Int?
    /// Per section, a counter bumped when a second tap on the selected tab (at its root) asks the page to scroll to its top
    /// (``scrollsToTop(whenRequested:)``).
    private(set) var scrollToTopRequests: [AppSection: Int] = [:]
    /// Bumped when the flyout closes without choosing a destination, so the Open Navigation button
    /// takes VoiceOver focus back (HIG VoiceOver: "Inform VoiceOver of visible content or layout changes").
    private(set) var focusReturnToken = 0

    init(selection: AppSection = .home) {
        self.selection = selection
        #if DEBUG
        // `FENTON_OPEN_FLYOUT=1`: the flyout starts open, so side-by-side screenshots of both apps can show it.
        if ProcessInfo.processInfo.environment["FENTON_OPEN_FLYOUT"] == "1" { isFlyoutOpen = true }
        #endif
    }

    /// The pages this navigator pushed on each section's stack, bottom first, beside ``paths`` (which cannot be read). A page
    /// pushed any other way (a `NavigationLink` value) is a `nil` slot; read it through ``routes(in:)``.
    private var knownRoutes: [AppSection: [ShellRoute?]] = [:]

    /// A binding to one section's path. A shorter path written back is the person popping a page (the back button or the
    /// edge swipe), so the list of known routes follows it.
    func path(for section: AppSection) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[section] ?? NavigationPath() },
            set: {
                self.paths[section] = $0
                if let known = self.knownRoutes[section], known.count > $0.count { self.knownRoutes[section] = Array(known.prefix($0.count)) }
            }
        )
    }

    /// The sheet this navigator is presenting over `section`'s stack, as one presentation item for `sheet(item:)`; setting it
    /// to nil (the person dismissing) clears whichever of ``quickLinksSection`` or ``accountSection`` is open on that section.
    func sheet(in section: AppSection) -> Binding<ShellSheet?> {
        Binding(
            get: {
                if self.accountSection == section { return .account }
                return self.quickLinksSection == section ? .quickLinks : nil
            },
            set: {
                guard $0 == nil else { return }
                if self.accountSection == section { self.accountSection = nil }
                if self.quickLinksSection == section { self.quickLinksSection = nil }
            }
        )
    }

    /// Drops pages off `section`'s path until `depth` remain, through the path binding (so the known routes follow). A no-op when
    /// the path is not deeper than `depth`; lets UIKit report a back swipe without naming ``NavigationPath``.
    /// - Returns: Whether the path was trimmed.
    @discardableResult
    func trimPath(in section: AppSection, toDepth depth: Int) -> Bool {
        var path = paths[section] ?? NavigationPath()
        guard path.count > depth else { return false }
        path.removeLast(path.count - depth)
        self.path(for: section).wrappedValue = path
        return true
    }

    /// One slot per page on `section`'s stack, bottom first: the route this navigator pushed, or nil for a page it did not.
    func routes(in section: AppSection) -> [ShellRoute?] {
        let count = paths[section]?.count ?? 0
        let known = knownRoutes[section] ?? []
        return Array(known.prefix(count)) + Array(repeating: nil, count: max(0, count - known.count))
    }

    /// Each section's stack as a list of routes, for the sections whose every page is known: what a cold launch can put back
    /// (``RouteRestore``).
    var restorableRoutes: [AppSection: [ShellRoute]] {
        var result: [AppSection: [ShellRoute]] = [:]
        for (section, path) in paths where !path.isEmpty {
            let slots = routes(in: section)
            if slots.allSatisfy({ $0 != nil }) { result[section] = slots.compactMap { $0 } }
        }
        return result
    }

    /// Puts back the stacks a previous launch left, onto sections that are still at their root.
    func restore(_ routes: [AppSection: [ShellRoute]]) {
        for (section, list) in routes where isAtRoot(section) && !list.isEmpty {
            var path = NavigationPath()
            for route in list { route.append(to: &path) }
            paths[section] = path
            knownRoutes[section] = list
        }
    }

    /// Pushes `route` onto `section`'s stack and remembers it.
    func append(_ route: ShellRoute, in section: AppSection) {
        var slots = routes(in: section)
        slots.append(route)
        var path = paths[section] ?? NavigationPath()
        route.append(to: &path)
        paths[section] = path
        knownRoutes[section] = slots
    }

    /// Presents the Quick Links sheet over the selected section, closing the flyout.
    func openQuickLinks() {
        isFlyoutOpen = false
        quickLinksSection = selection
    }

    /// Presents the Account sheet over the selected section, closing the flyout.
    func openAccount() {
        isFlyoutOpen = false
        accountSection = selection
    }

    /// Whether a section is the one on screen.
    func isShowing(_ section: AppSection) -> Bool { selection == section }

    /// Whether a section is showing its root page.
    func isAtRoot(_ section: AppSection) -> Bool {
        paths[section]?.isEmpty ?? true
    }

    // MARK: - Intents

    /// Shows the flyout.
    func openFlyout() { isFlyoutOpen = true }

    /// Opens the flyout for a finished leading-edge drag, only while the selected section is at its root
    /// (deeper, the system's back swipe owns that edge).
    /// - Parameters:
    ///   - startX: Where the drag began, from the leading edge.
    ///   - translation: Total movement.
    func edgeSwipeEnded(startX: CGFloat, translation: CGSize) {
        guard isAtRoot(selection), !isFlyoutOpen,
              NavigationFlyoutMetrics.edgeSwipeOpens(startX: startX, translation: translation)
        else { return }
        openFlyout()
    }

    /// Hides the flyout without choosing a destination; focus returns to Open Navigation.
    func dismissFlyout() {
        guard isFlyoutOpen else { return }
        isFlyoutOpen = false
        focusReturnToken &+= 1
    }

    /// Opens the page a notification points at, on its section's root (web `primaryNavPathForRoute`). A Home page
    /// is pushed on Home's root; a route the app has no page for opens Home.
    func open(_ destination: PushDestination, anchor: String? = nil) {
        isFlyoutOpen = false
        pendingSheet = nil
        // A link must land where the person can see it: close the Quick Links and Account sheets too, or the page
        // opens on the stack behind them (HIG Navigation).
        quickLinksSection = nil
        accountSection = nil
        switch destination {
        case let .section(section):
            let target = AppSection(section)
            paths[target] = NavigationPath()
            knownRoutes[target] = []
            select(target)
        case let .homePage(path):
            var stack = NavigationPath()
            knownRoutes[.home] = []
            if let route = HomeRoute(pushPath: path) {
                stack.append(route)
                knownRoutes[.home] = [.home(route)]
            }
            if let anchor, case .room? = HomeRoute(pushPath: path) { pendingSheet = PendingSheet(page: path, anchor: anchor) }
            paths[.home] = stack
            selection = .home
        }
    }

    /// The Home page on top of each section's stack, kept by the destination as it appears and disappears. A
    /// ``NavigationPath`` cannot be read, so this is how ``push(_:in:)`` knows what is already showing.
    private(set) var shownRoutes: [AppSection: HomeRoute] = [:]

    /// Records that `route` is now the page showing on `section`'s stack.
    func routeAppeared(_ route: HomeRoute, in section: AppSection) { shownRoutes[section] = route }

    /// Records that `route` left the screen (popped, or covered by a deeper page).
    func routeDisappeared(_ route: HomeRoute, in section: AppSection) {
        if shownRoutes[section] == route { shownRoutes[section] = nil }
    }

    /// Opens a page Quick Links chose on `section`'s stack. Quick Links is lateral navigation, so a page that is already
    /// open is not stacked again: if it is on top the stack stays put, and if it is deeper down the stack pops back to it
    /// (owner decision 2026-10-24, navigation-flows 1 B; HIG Navigation: keep a hierarchy so Back makes sense). Otherwise
    /// the page is pushed.
    /// - Returns: Whether the page was pushed.
    @discardableResult
    func push(_ route: HomeRoute, in section: AppSection) -> Bool {
        guard shownRoutes[section] != route else { return false }
        let slots = routes(in: section)
        if let index = slots.lastIndex(of: .home(route)) {
            let drop = slots.count - (index + 1)
            if drop > 0 {
                paths[section]?.removeLast(drop)
                knownRoutes[section] = Array(slots.prefix(index + 1))
            }
            return false
        }
        append(.home(route), in: section)
        return true
    }

    /// The sheet a link asked `page` to open, once; nil for another page or none.
    func takeSheet(forPage page: String) -> String? {
        guard let pending = pendingSheet, pending.page == page else { return nil }
        pendingSheet = nil
        return pending.anchor
    }

    /// What choosing the selected section did.
    enum ReselectOutcome: Equatable {
        /// The stack was deeper than its root and popped to it.
        case poppedToRoot
        /// The stack was at its root: the page was asked to scroll to its top.
        case scrolledToTop
    }

    /// Chooses a section from the flyout. Choosing the current section is the standard second tap: it pops the stack to its
    /// root, and once it is at the root it scrolls the page to the top (``reselect(_:)``).
    func select(_ section: AppSection) {
        tabTapped(section)
        isFlyoutOpen = false
    }

    /// A tap on the tab bar: another section is a cut (no animation on the content); the selected one is ``reselect(_:)``.
    func tabTapped(_ section: AppSection) {
        if section == selection {
            reselect(section)
        } else {
            selection = section
        }
    }

    /// The standard second tap on the selected tab: the first tap pops to the root; at the root the next scrolls to the top.
    @discardableResult
    func reselect(_ section: AppSection) -> ReselectOutcome {
        guard isAtRoot(section) else {
            paths[section] = NavigationPath()
            knownRoutes[section] = []
            return .poppedToRoot
        }
        scrollToTopRequests[section, default: 0] += 1
        return .scrolledToTop
    }
}

/// A sheet the shell presents over a section's stack: one presentation state per stack (HIG Sheets: one sheet at a time).
enum ShellSheet: String, Identifiable {
    case quickLinks, account
    var id: String { rawValue }
}
