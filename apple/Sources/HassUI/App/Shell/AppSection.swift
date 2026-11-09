import HassCore
import HassDesign
import SwiftUI

// MARK: - Sections

/// The app's root sections, from the web's `PRIMARY_NAV_ROUTES`
/// (`ha-sfenton-react-dash:src/constants/routes.ts`): Home, Security, Climate, Chores, Settings. Settings is the last
/// tab, its own page like the web's (owner, 2026-10-16, reversing the 2026-10-14 decision that put it in the Account
/// sheet; `.agents/design/direction-g.md`, Navigation).
enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home, security, climate, chores, settings

    var id: String { rawValue }

    /// Visible name (web `shell.json` `navigation.items.*`).
    var title: String {
        switch self {
        case .home: "Home"
        case .security: "Security"
        case .climate: "Climate"
        case .chores: "Chores"
        case .settings: "Settings"
        }
    }

    /// SF Symbol mapped from the web's MDI icon.
    var symbol: String { SymbolMap.symbol(for: mdiIcon) }

    /// The web's icon name.
    var mdiIcon: String {
        switch self {
        case .home: "mdi:home"
        case .security: "mdi:shield"
        case .climate: "mdi:thermostat"
        case .chores: "mdi:clipboard-list"
        case .settings: "mdi:cog"
        }
    }

    /// Accessibility identifier for this section's navigation item (tab and flyout row alike).
    var navigationIdentifier: String { "nav.\(rawValue)" }

    /// The section a notification opens.
    init(_ section: PushSection) {
        switch section {
        case .home: self = .home
        case .security: self = .security
        case .climate: self = .climate
        case .chores: self = .chores
        case .settings: self = .settings
        }
    }
}

// MARK: - Menu

/// The flyout's rows (direction G, Navigation: the overlay glass flyout lists the same five as the tab bar).
enum NavigationMenu {
    /// The section rows, in order.
    static let primary: [AppSection] = AppSection.allCases

    /// VoiceOver label for a navigation item. Only Chores carries a badge (web `BADGED_NAV_PATH`), and
    /// the count is spoken after the name like the web's `tabs.overdue` label.
    /// - Parameters:
    ///   - section: The item's section.
    ///   - overdue: Overdue chore count; nil or zero adds nothing.
    static func accessibilityLabel(for section: AppSection, overdue: Int?) -> String {
        guard section == .chores, let overdue, overdue > 0 else { return section.title }
        return "\(section.title), \(overdue) overdue"
    }

    /// The badge count of an item, if any.
    static func badge(for section: AppSection, overdue: Int?) -> Int? {
        guard section == .chores, let overdue, overdue > 0 else { return nil }
        return overdue
    }

    /// The badge as drawn on the tab bar and in the flyout: the one cap, `ProfileSummary/badgeText(_:)` ("9+"), the same
    /// as the header's Profile badge and the modal tab bars.
    static func badgeText(for section: AppSection, overdue: Int?) -> String? {
        badge(for: section, overdue: overdue).flatMap(ProfileSummary.badgeText)
    }
}

// MARK: - Shell style

/// How the app presents its root navigation (owner rules, 2026-10-10; `.agents/design/apple/ipados.md`).
///
/// | Window | Navigation |
/// |---|---|
/// | Compact width (iPhone, Duo folded) | Bottom tab bar (web `bottom` layout) |
/// | Regular width with a hinge (Duo unfolded) | The tab bar stays (owner, 2026-10-26) |
/// | Regular width, no hinge (iPad) | Overlay flyout opened from the toolbar or a leading-edge swipe |
///
/// The style follows the horizontal size class and whether the window has a hinge (both geometric, never a device
/// check), so rotating an iPad or a Duo never swaps the navigation model. Splits are a separate, per-page decision
/// (``SplitPolicy``).
enum ShellNavigationStyle: Equatable, Sendable {
    case tabBar
    case flyout

    /// Picks the style for a window.
    /// - Parameters:
    ///   - isRegularWidth: Horizontal size class is regular.
    ///   - hasHinge: The window has a hinge (``SwiftUI/EnvironmentValues/windowHinge`` is set): the unfolded Duo, which
    ///     keeps the tab bar (owner, 2026-10-26).
    static func resolve(isRegularWidth: Bool, hasHinge: Bool = false) -> ShellNavigationStyle {
        isRegularWidth && !hasHinge ? .flyout : .tabBar
    }
}

// MARK: - Chrome

/// Where the shell puts navigation chrome for a window (pure, so it can be unit tested).
///
/// Profile and Quick Links are header buttons on every page in every window (owner, 2026-10-16), so only the
/// leading menu button and where the title sits vary with the window.
struct ShellChrome: Equatable, Sendable {
    /// Show the leading menu button that opens ``NavigationFlyout``.
    var showsMenuButton: Bool
    /// The page title sits in the header row beside the trailing buttons (``HeaderTitleStyle``): where nothing but
    /// the trailing buttons shares the row, which is every window without the menu button.
    var titleInHeader: Bool
    /// The leading edge swipe opens the flyout, wherever the menu button shows. The menu button only shows on section
    /// roots, where no Back swipe owns the edge (``ShellNavigator/edgeSwipeEnded(startX:translation:)`` checks the root).
    var edgeSwipe: Bool

    init(showsMenuButton: Bool, titleInHeader: Bool, edgeSwipe: Bool? = nil) {
        self.showsMenuButton = showsMenuButton
        self.titleInHeader = titleInHeader
        self.edgeSwipe = edgeSwipe ?? showsMenuButton
    }

    /// Resolves the chrome.
    /// - Parameter style: The root navigation style.
    ///   - Owner, 2026-10-20: the menu button returns wherever the tab bar shows (tab-bar accessories may follow), but not
    ///     on the iPhone Duo's vertical rail. Decided 2026-10-24 (duo-ipad-fold-layout): it follows the window's size class,
    ///     not the device idiom, so a compact iPad window (Split View, Stage Manager) gets it too.
    ///   - inVerticalBar: The system has moved bar items into the Duo's vertical bar.
    static func resolve(style: ShellNavigationStyle, inVerticalBar: Bool = false) -> ShellChrome {
        switch style {
        case .flyout: return ShellChrome(showsMenuButton: true, titleInHeader: false, edgeSwipe: true)
        case .tabBar:
            // With the menu button leading (iPhone), the title is the standard large title below the bar: `.inlineLarge`
            // would put it in the leading slot and push the menu button to the trailing side (owner, 2026-10-20).
            let menu = !inVerticalBar
            return ShellChrome(showsMenuButton: menu, titleInHeader: !menu, edgeSwipe: menu)
        }
    }
}
