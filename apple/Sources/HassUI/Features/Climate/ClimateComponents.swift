import HassCore
import HassDesign
import SwiftUI

// MARK: - Style

/// Colours local to the Climate page and sheet.
enum ClimateStyle {
    /// Heating: the heating family's glyph (the dial's heat `#CD5401`, lifted for a glyph on dark).
    static let heat = ColorFamily.heating.glyph
    /// ``heat`` as raw sRGB.
    static let heatToken = ColorFamily.heating.glyphToken
    /// Cooling: the cooling family's glyph (the dial's cool `#2C8E98`, lifted).
    static let cool = ColorFamily.cooling.glyph
    /// ``cool`` as raw sRGB.
    static let coolToken = ColorFamily.cooling.glyphToken

    /// The tint for an `hvac_action`: heat, cool, or `nil` when idle (web `thermostatActionColor`).
    static func tint(action: String) -> Color? {
        switch ThermostatThermalStatus(action: action) {
        case .heat: heat
        case .cool: cool
        default: nil
        }
    }

    /// The SF Symbol for an MDI icon name.
    static func symbol(_ mdi: String) -> String { SymbolMap.symbol(for: mdi) }
}
