import Foundation

/// A colour as raw sRGB: the single source of truth for a design token, so SwiftUI (`Color(_:)`) and UIKit (`UIColor(_:)`) draw
/// the same pixels without either converting through the other.
///
/// A token resolves to one of four ``Components`` by appearance: light or dark, with or without Increase Contrast. A fixed colour
/// has the same value in all four; an adaptive one differs. ``opacity(_:)``, ``mixed(with:amount:)`` and the other arithmetic map
/// over all four, so a computed token (a label at 72%, a family glyph lifted toward white) is the same expression on raw values
/// that the SwiftUI code writes on `Color`.
public struct HassRGB: Sendable, Equatable {
    /// Red, green, blue (0...1) and alpha.
    public struct Components: Sendable, Equatable {
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
            (self.red, self.green, self.blue, self.alpha) = (red, green, blue, alpha)
        }

        /// From `0xRRGGBB`.
        public init(rgb: UInt32, alpha: Double = 1) {
            self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                      blue: Double(rgb & 0xFF) / 255, alpha: alpha)
        }
    }

    public var light: Components
    public var dark: Components
    public var lightIncreased: Components
    public var darkIncreased: Components

    /// One value in every appearance.
    public init(_ components: Components) {
        light = components; dark = components; lightIncreased = components; darkIncreased = components
    }

    /// Light and dark values; Increase Contrast keeps them unless given.
    public init(light: Components, dark: Components, lightIncreased: Components? = nil, darkIncreased: Components? = nil) {
        self.light = light; self.dark = dark
        self.lightIncreased = lightIncreased ?? light
        self.darkIncreased = darkIncreased ?? dark
    }

    /// `0xRRGGBB` sRGB, with an opacity.
    public init(rgb: UInt32, alpha: Double = 1) { self.init(Components(rgb: rgb, alpha: alpha)) }

    /// sRGB channels (0...1).
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.init(Components(red: red, green: green, blue: blue, alpha: alpha))
    }

    /// Light and dark `0xRRGGBB` with opacities, as ``SwiftUI/Color/adaptive(light:lightAlpha:dark:darkAlpha:)``.
    public static func adaptive(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) -> HassRGB {
        HassRGB(light: Components(rgb: light, alpha: lightAlpha), dark: Components(rgb: dark, alpha: darkAlpha))
    }

    public static let white = HassRGB(rgb: 0xFFFFFF)
    public static let black = HassRGB(rgb: 0x000000)
    public static let clear = HassRGB(red: 0, green: 0, blue: 0, alpha: 0)
    /// UIKit's `UIColor.label`: black in light, white in dark.
    public static let label = HassRGB(light: Components(rgb: 0x000000), dark: Components(rgb: 0xFFFFFF))

    /// Whether the colour is the same in every appearance.
    public var isFixed: Bool { light == dark && light == lightIncreased && light == darkIncreased }

    /// The value for an appearance.
    public func components(isDark: Bool, increasedContrast: Bool) -> Components {
        switch (isDark, increasedContrast) {
        case (false, false): light
        case (true, false): dark
        case (false, true): lightIncreased
        case (true, true): darkIncreased
        }
    }

    // MARK: Arithmetic

    /// Applies `transform` to each of the four values.
    public func map(_ transform: (Components) -> Components) -> HassRGB {
        HassRGB(light: transform(light), dark: transform(dark),
                lightIncreased: transform(lightIncreased), darkIncreased: transform(darkIncreased))
    }

    /// Combines two colours appearance by appearance.
    public func zip(_ other: HassRGB, _ transform: (Components, Components) -> Components) -> HassRGB {
        HassRGB(light: transform(light, other.light), dark: transform(dark, other.dark),
                lightIncreased: transform(lightIncreased, other.lightIncreased), darkIncreased: transform(darkIncreased, other.darkIncreased))
    }

    /// The colour at `opacity` of its own alpha (SwiftUI's `Color.opacity(_:)`).
    public func opacity(_ opacity: Double) -> HassRGB {
        map { Components(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha * opacity) }
    }

    /// The colour with its alpha replaced (`UIColor.withAlphaComponent(_:)`).
    public func withAlpha(_ alpha: Double) -> HassRGB {
        map { Components(red: $0.red, green: $0.green, blue: $0.blue, alpha: alpha) }
    }

    /// Each channel moved `amount` of the way toward `other`'s.
    public func mixed(with other: HassRGB, amount: Double) -> HassRGB {
        zip(other) { a, b in
            Components(red: a.red + (b.red - a.red) * amount, green: a.green + (b.green - a.green) * amount,
                       blue: a.blue + (b.blue - a.blue) * amount, alpha: a.alpha + (b.alpha - a.alpha) * amount)
        }
    }
}
