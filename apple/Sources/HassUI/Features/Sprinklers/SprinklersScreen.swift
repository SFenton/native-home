import HassCore
import HassDesign
import SwiftUI

// MARK: - Shared pieces

enum SprinklerStyle {
    static let symbol = "sprinkler.and.droplets"
    /// The water family's glyph colour (direction G): active zones, chosen days and the controller row.
    static let water = Color(waterToken)
    /// ``water`` as raw sRGB.
    static let waterToken = ColorFamily.water.glyphToken
}
