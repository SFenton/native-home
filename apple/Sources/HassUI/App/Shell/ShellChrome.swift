import HassCore
import HassDesign
import SwiftUI

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
