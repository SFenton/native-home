import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Color {
    /// A colour from `0xRRGGBB` sRGB (public so feature code can use ``HassTokens/Palette`` values).
    init(rgb: UInt32) {
        let (red, green, blue) = Self.components(rgb)
        self.init(.sRGB, red: red, green: green, blue: blue)
    }

    /// A colour with a light and a dark `0xRRGGBB` variant, resolved from the view's colour scheme at draw time.
    ///
    /// Pages are always dark and sheets follow the system (``SwiftUICore/View/followsSystemAppearance()``), so a
    /// token built this way draws the dark value on a page and the user's appearance in a sheet with no per-view
    /// branching. watchOS is always dark.
    /// - Parameters:
    ///   - light: The light appearance's value.
    ///   - lightAlpha: Its opacity.
    ///   - dark: The dark appearance's value.
    ///   - darkAlpha: Its opacity.
    static func adaptive(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) -> Color {
        let (lr, lg, lb) = components(light)
        let (dr, dg, db) = components(dark)
        #if os(iOS)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: dr, green: dg, blue: db, alpha: darkAlpha)
                : UIColor(red: lr, green: lg, blue: lb, alpha: lightAlpha)
        })
        #elseif os(macOS)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: dr, green: dg, blue: db, alpha: darkAlpha)
                : NSColor(red: lr, green: lg, blue: lb, alpha: lightAlpha)
        })
        #else
        return Color(.sRGB, red: dr, green: dg, blue: db, opacity: darkAlpha)
        #endif
    }

    /// The red, green and blue channels of `0xRRGGBB`, from 0 to 1.
    internal static func components(_ rgb: UInt32) -> (Double, Double, Double) {
        (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
    }
}
