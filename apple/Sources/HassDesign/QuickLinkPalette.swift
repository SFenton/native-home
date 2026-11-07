import SwiftUI

/// One colour per Quick Links tile: a solid fill with a filled white glyph and white text, like the Rooms grid
/// (`.agents/design/direction-g.md`, Colour: Quick Links tiles; owner, 2026-10-16: "Quick Links ... no color there as
/// well").
///
/// Nothing here is a new colour except Rooms. Every page keeps the colour family its own screens already use:
/// Food & Recipes the food green, Vacuums cleaning purple, Media pink, Sprinklers water blue, Custom Lights the amber of
/// the Lights chip (lights have no tile fill of their own, only the lit tile), and Security System the fill of the
/// current alarm mode (the same as the Security page and the status chip). Rooms is a deep navy that none of the sixteen
/// rooms, the families or the alarm modes use, because the tile stands for all of them. White passes 4.5:1 on every fill.
public enum QuickLinkPalette {
    /// The Rooms link: deep navy, at least 0.05 (OKLab) from every room, family and alarm fill.
    public static let rooms: UInt32 = 0x1F3A5F
    /// The Security System link while the alarm mode is unknown or the screen is redacted: the web's unknown-state
    /// slate (`rgb(84, 110, 122)`) darkened for white text.
    public static let securityUnknown: UInt32 = 0x4C6270
    /// Custom Lights: the Lights chip's amber.
    public static let customLights: UInt32 = ColorFamily.lights.chipFillRGB ?? 0x7A4A00

    /// The fill for a Quick Links tile by its id (`QuickLinks.items`), or nil for an id that is not a Quick Link.
    /// - Parameters:
    ///   - id: The link's id (`rooms`, `security-system`, `food`, `vacuums`, `media`, `custom-lights`, `sprinklers`).
    ///   - alarmState: The alarm panel's state, which colours Security System by mode.
    ///   - isRedacted: Whether screenshots are being redacted; Security System then shows no mode.
    public static func fill(forLink id: String, alarmState: String? = nil, isRedacted: Bool = false) -> UInt32? {
        switch id {
        case "rooms": rooms
        case "security-system":
            isRedacted ? securityUnknown : ColorFamily.security(alarmState: alarmState)?.spec.fill ?? securityUnknown
        case "food": ColorFamily.food.spec.fill
        case "vacuums": ColorFamily.cleaning.spec.fill
        case "media": ColorFamily.media.spec.fill
        case "custom-lights": customLights
        case "sprinklers": ColorFamily.water.spec.fill
        default: nil
        }
    }

    /// Every Quick Links id the palette colours, in tile order.
    public static let linkIDs = ["rooms", "security-system", "food", "vacuums", "media", "custom-lights", "sprinklers"]
}
