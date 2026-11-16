import SwiftUI

/// A solid colour that may differ by appearance: one `0xRRGGBB` for light and one for dark (`sh.solid-appearance@1`).
///
/// It is the value form of an authored light and dark pair, so a UIKit view and a SwiftUI one resolve it the same way. ``token`` is the
/// ``HassRGB`` both draw (``UIKit/UIColor`` through `UIColor(_:)`, `Color` through ``color``), so the colour follows the trait collection
/// or the colour scheme with no reload. No clamp is applied: a fixed pair is the author's value.
public struct AppearanceFill: Equatable, Sendable {
    /// The colour while the interface is light.
    public var light: UInt32
    /// The colour while the interface is dark.
    public var dark: UInt32

    /// A pair: `light` in the light appearance, `dark` in the dark one.
    public init(light: UInt32, dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    /// One colour for both appearances.
    public init(_ rgb: UInt32) { self.init(light: rgb, dark: rgb) }

    /// Whether the colour is the same in both appearances.
    public var isFixed: Bool { light == dark }

    /// The colour for an appearance.
    public func rgb(isDark: Bool) -> UInt32 { isDark ? dark : light }

    /// The colour as the raw adaptive token both UIKit and SwiftUI draw.
    public var token: HassRGB { isFixed ? HassRGB(rgb: light) : .adaptive(light: light, dark: dark) }

    /// The SwiftUI colour: it follows the environment's colour scheme.
    public var color: Color { Color(token) }
}
