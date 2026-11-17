import Foundation

// MARK: - Ink (`sh.text-style@1`)

/// The colour of a slot `sh.text-style@1` adds (a text's ink, a stack's fill, line and border, a shape's fill, a symbol's tint): an exact
/// colour with or without opacity, or one for each appearance.
///
/// Slots that existed before the id keep taking `solid-rgb` and `solid-appearance` of `solid-rgb`, with no opacity. An ink always holds
/// both appearances, so a single colour is the same pair twice and drawing never asks which form the document used.
public struct ServerUIInk: Equatable, Sendable {
    /// One exact colour with its opacity, `0` clear to `1` opaque.
    public struct Color: Equatable, Sendable {
        /// The red, green and blue of the colour.
        public var rgb: ServerUIRGB
        /// The opacity, from 0 to 1.
        public var alpha: Double

        /// Creates a colour. `alpha` is clamped to `0...1`.
        public init(rgb: ServerUIRGB, alpha: Double = 1) {
            self.rgb = rgb
            self.alpha = min(1, max(0, alpha))
        }
    }

    /// The colour in a light appearance.
    public var light: Color
    /// The colour in a dark appearance.
    public var dark: Color

    /// Creates an ink from one colour for each appearance.
    public init(light: Color, dark: Color) {
        self.light = light
        self.dark = dark
    }

    /// Creates an ink that is `color` in both appearances.
    public init(_ color: Color) { self.init(light: color, dark: color) }

    /// The colour for an appearance.
    public func color(isDark: Bool) -> Color { isDark ? dark : light }
}
