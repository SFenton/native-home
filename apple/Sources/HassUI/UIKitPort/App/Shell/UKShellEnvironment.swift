#if os(iOS)
import HassCore
import HassDesign
import Observation
import UIKit

/// Whether the running system draws the iOS 26 glass bar. The app ships to iOS 17 and later, so the earlier bar's fallbacks (the material
/// ring behind Profile, the drawn badge, the custom Quick Links circle, the header fade mask) are real code; a hosted test sets
/// ``override`` to run them on a newer system. Nil (always, outside tests) means "ask the system".
enum UKGlassEra {
    nonisolated(unsafe) static var override: Bool?
    /// The same for iOS 18 (the tab bar's `isTabBarHidden`, the header fade tracking the scroll).
    nonisolated(unsafe) static var iOS18Override: Bool?
    static var hasIOS18: Bool {
        if let iOS18Override { return iOS18Override }
        if #available(iOS 18.0, *) { return true }
        return false
    }
    static var hasGlass: Bool {
        if let override { return override }
        if #available(iOS 26.0, *) { return true }
        return false
    }
}

/// What `MainTabView` and `RootView` put into the SwiftUI environment for every page (`shellNavigationStyle`, `shellChrome`,
/// `shellInVerticalBar`, `headerEdgeCap`, `windowHinge`, `backdropCanvas`, `homeArrival`), published once by the shell and
/// read by pages through ``UKContext/shell``. Observable: a page reads a property inside a ``UKObservation`` and is updated
/// when the shell changes it (a rotation to regular width, a fold).
@MainActor
@Observable
final class UKShellEnvironment {
    /// Tab bar (compact width) or flyout (regular width).
    var style: ShellNavigationStyle = .tabBar
    /// Where the menu button and the title go (``ShellChrome``).
    var chrome: ShellChrome = .resolve(style: .tabBar)
    /// The system moves bar items into a vertical bar (the iPhone Duo).
    var inVerticalBar = false
    /// Where the inline navigation bar ends (``HeaderEdgeFade/edgeCap(statusTop:barHeight:barIsRail:)``); nil outside the shell.
    var headerEdgeCap: CGFloat?
    /// The hinge in window coordinates, nil on a device without one.
    var windowHinge: CGRect?
    /// The hinge in either pose (``WindowFold``); ``windowHinge`` is the band content keeps clear of.
    var windowFold: WindowFold = .none
    /// The window's full size, which the wallpaper is rendered for and fills on every page.
    var canvas: CGSize = .zero
    /// Home's arrival after a sign-in; nil outside the signed-in shell.
    var arrival: HomeArrival?
    /// Overdue chores plus expired food, badged on the Profile button (``ShellAttention``).
    var attentionCount = 0
    /// No network path at all: the Profile button's offline badge.
    var isOffline = false
    /// The Reduce Motion setting, mirrored so a page reads it inside a ``UKObservation``.
    var reduceMotion = UIAccessibility.isReduceMotionEnabled
    /// Reduce Transparency, mirrored for the same reason.
    var reduceTransparency = UIAccessibility.isReduceTransparencyEnabled

    init() {}

    /// A shell environment for a gallery: phone chrome (large title, menu button) or the flyout-less header.
    static func gallery(phone: Bool, cap: CGFloat? = nil) -> UKShellEnvironment {
        let environment = UKShellEnvironment()
        environment.chrome = phone
            ? ShellChrome(showsMenuButton: true, titleInHeader: false) : ShellChrome(showsMenuButton: false, titleInHeader: true)
        environment.headerEdgeCap = cap
        return environment
    }

    /// Keeps ``reduceMotion`` and ``reduceTransparency`` current; call once for the environment's lifetime.
    func observeAccessibilitySettings() -> [NSObjectProtocol] {
        let center = NotificationCenter.default
        return [
            center.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reduceMotion = UIAccessibility.isReduceMotionEnabled }
            },
            center.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reduceTransparency = UIAccessibility.isReduceTransparencyEnabled }
            },
        ]
    }
}
#endif
