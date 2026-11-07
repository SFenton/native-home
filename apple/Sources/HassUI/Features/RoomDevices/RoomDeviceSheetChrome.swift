import HassCore
import HassDesign

/// Colors the device sheets share. Tiles, chips and buttons take their colours from the direction G colour
/// families (`ColorFamily`); these are the dial tints the families do not cover.
enum RoomDeviceStyle {
    /// Humidifier dial and accents: the mockup's water arc (`#30B4DC`; direction G, Colour families: Water).
    static let humidifierTint = DialTint(red: 48, green: 180, blue: 220)
    /// Humidity comfort band, 40–50% (web trail rgba(67, 160, 71)).
    static let comfortTrail = DialTint(red: 67, green: 160, blue: 71, opacity: 0.92)
    /// Condensation risk band, 60–80% (web trail rgba(251, 140, 0)).
    static let highTrail = DialTint(red: 251, green: 140, blue: 0, opacity: 0.9)
}
