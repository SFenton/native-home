import HassCore
import HassDesign
import SwiftUI

// MARK: - Shell style

/// How the app presents its root navigation (owner rules, 2026-10-10; pick 3 of global chrome, 2026-11-18;
/// `.agents/design/apple/ipados.md`).
///
/// The system tab bar is the navigator in every window and is never hidden for style; the style only says where the system
/// draws it and whether the shell adds a menu button.
///
/// | Window | Navigation |
/// |---|---|
/// | Compact width (iPhone, Duo folded, a compact iPad window) | Tab bar at the bottom (the Duo's folded rail is vertical); a menu button opens the flyout |
/// | Regular width with a hinge (Duo unfolded) | The tab bar stays (owner, 2026-10-26), with the menu button |
/// | Regular width, no hinge (iPad) | The system tab bar at the top, in the navigation bar's row: no menu button, no flyout |
///
/// The style follows the horizontal size class and whether the window has a hinge (both geometric, never a device
/// check), so rotating an iPad or a Duo never swaps the navigation model. Splits are a separate, per-page decision
/// (``SplitPolicy``).
enum ShellNavigationStyle: Equatable, Sendable {
    /// The tab bar where the system draws it for a compact window or a Duo, with the menu button and its flyout.
    case tabBar
    /// The system tab bar at the top of a regular-width window, sharing the navigation bar's row; no menu button.
    case topTabBar

    /// Picks the style for a window.
    /// - Parameters:
    ///   - isRegularWidth: Horizontal size class is regular.
    ///   - hasHinge: The window has a hinge (``SwiftUI/EnvironmentValues/windowHinge`` is set): the unfolded Duo, which
    ///     keeps its tab bar and menu button (owner, 2026-10-26).
    static func resolve(isRegularWidth: Bool, hasHinge: Bool = false) -> ShellNavigationStyle {
        isRegularWidth && !hasHinge ? .topTabBar : .tabBar
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
    /// the trailing buttons shares the row, which is the folded Duo's vertical bar.
    var titleInHeader: Bool
    /// The leading edge swipe opens the flyout, wherever the menu button shows. The menu button only shows on section
    /// roots, where no Back swipe owns the edge (``ShellNavigator/edgeSwipeEnded(startX:translation:)`` checks the root).
    var edgeSwipe: Bool
    /// The collapsed title leads the row (`UINavigationItem.Style.browser`): beside the menu button, or alone at the leading
    /// side where the top tab bar holds the centre (global chrome pick 3).
    var titleLeads: Bool

    init(showsMenuButton: Bool, titleInHeader: Bool, edgeSwipe: Bool? = nil, titleLeads: Bool? = nil) {
        self.showsMenuButton = showsMenuButton
        self.titleInHeader = titleInHeader
        self.edgeSwipe = edgeSwipe ?? showsMenuButton
        self.titleLeads = titleLeads ?? showsMenuButton
    }

    /// Resolves the chrome.
    /// - Parameter style: The root navigation style.
    ///   - Owner, 2026-10-20: the menu button returns wherever the tab bar shows, but not on the iPhone Duo's vertical rail.
    ///     Decided 2026-10-24 (duo-ipad-fold-layout): it follows the window's size class, not the device idiom, so a compact
    ///     iPad window (Split View, Stage Manager) gets it too. Narrowed by pick 3 (2026-11-18): not where the system draws the
    ///     tabs at the top of a regular iPad window, where a second navigator in the row would repeat the first.
    ///   - inVerticalBar: The system has moved bar items into the Duo's vertical bar.
    static func resolve(style: ShellNavigationStyle, inVerticalBar: Bool = false) -> ShellChrome {
        switch style {
        case .topTabBar:
            // The large title stays below the bar; the collapsed title leads, because the tabs hold the centre.
            return ShellChrome(showsMenuButton: false, titleInHeader: false, edgeSwipe: false, titleLeads: true)
        case .tabBar:
            // With the menu button leading (iPhone), the title is the standard large title below the bar: `.inlineLarge`
            // would put it in the leading slot and push the menu button to the trailing side (owner, 2026-10-20).
            let menu = !inVerticalBar
            return ShellChrome(showsMenuButton: menu, titleInHeader: !menu, edgeSwipe: menu)
        }
    }
}
