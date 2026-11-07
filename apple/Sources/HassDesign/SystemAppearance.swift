import HassTelemetry
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The split between pages and sheets (`.agents/design/direction-g.md`, Layers; plan decision 6): pages sit on the
/// dimmed house photo, so the signed-in shell forces dark (`preferredColorScheme(.dark)`), and sheets follow the
/// system appearance. The shell cannot read the system appearance from its own trait collection, because the
/// override answers first, so each sheet reads the display (`UKSystemAppearance`) and applies the result to itself.
public enum SystemAppearance {
    /// The launch environment key that pins the sheets' appearance (`light` or `dark`), so journeys render sheets in
    /// light without changing the simulator's setting. `XCUIDevice.shared.appearance` drives the real path.
    public static let overrideKey = "FENTON_APPEARANCE"

    /// The scheme sheets draw in.
    /// - Parameters:
    ///   - override: ``overrideKey``'s value, if any.
    ///   - system: The display's own scheme, or nil when it cannot be read yet.
    /// - Returns: The override when it is `light` or `dark`, else the system scheme, else dark (the shell's own).
    public static func resolve(override: String?, system: ColorScheme?) -> ColorScheme {
        switch override?.lowercased() {
        case "light": .light
        case "dark": .dark
        default: system ?? .dark
        }
    }

    /// ``resolve(override:system:)`` for this process, read now: the launch override and the display's style.
    ///
    /// The display (`UIScreen`) is the source because the window, its scene's views and the shell's environment all carry
    /// the dark override, and because a read costs nothing, so a sheet can ask when it is presented instead of trusting
    /// a value that a missed trait-change callback left stale.
    /// - Parameter fallback: The scheme to use when the display cannot be read.
    @MainActor
    public static func current(fallback: ColorScheme = .dark) -> ColorScheme {
        resolve(override: overrideValue, system: liveSystemScheme() ?? fallback)
    }

    /// The display's own scheme, or nil without a window scene (previews, `swift test`).
    @MainActor
    static func liveSystemScheme() -> ColorScheme? {
        #if os(iOS)
        return ActiveWindowScene.currentOrFirst().map { scheme(of: $0.screen.traitCollection) }
        #else
        return nil
        #endif
    }

    /// The debug override: `FENTON_GALLERY_APPEARANCE` (a gallery setting, so a journey's app reset can switch it in place) first,
    /// then ``overrideKey``.
    public static var debugOverride: String? {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        return environment["FENTON_GALLERY_APPEARANCE"] ?? environment[overrideKey]
        #else
        return nil
        #endif
    }

    fileprivate static var overrideValue: String? { debugOverride }

    #if os(iOS)
    fileprivate static func scheme(of traits: UITraitCollection) -> ColorScheme {
        traits.userInterfaceStyle == .light ? .light : .dark
    }
    #endif
}
