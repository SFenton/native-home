import SwiftUI

public extension HassTokens.Surface {
    /// The chosen segment of a custom segmented row (the bathroom fan's timer lengths): the label colour's opposite,
    /// white on a dark sheet and near-black (`#1C1C1E`) on a light one, so the choice holds 3:1 or better against the
    /// cell in both appearances.
    static let selectedSegment = Color(HassTokens.RGB.Surface.selectedSegment)

    /// Text on ``selectedSegment``: black on white, white on near-black.
    static let selectedSegmentInk = Color(HassTokens.RGB.Surface.selectedSegmentInk)
}

public extension HassTokens.RGB.Surface {
    /// ``HassTokens/Surface/selectedSegment`` as sRGB.
    static let selectedSegment = HassRGB.adaptive(light: 0x1C1C1E, dark: 0xFFFFFF)
    /// ``HassTokens/Surface/selectedSegmentInk`` as sRGB.
    static let selectedSegmentInk = HassRGB.adaptive(light: 0xFFFFFF, dark: 0x000000)
}
