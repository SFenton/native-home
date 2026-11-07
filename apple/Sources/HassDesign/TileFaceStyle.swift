import SwiftUI

/// Which of direction G's tile faces a tile draws (`.agents/design/direction-g.md`, Controls: Tiles; pattern:
/// `.agents/patterns/entity-tile.md`).
///
/// Pure, so the choice is unit-tested apart from the drawing in ``GlassTileFace``.
public enum TileFaceStyle: Equatable, Sendable {
    /// Dark ground, glyph in the family colour mixed toward grey (or secondary without a family).
    case off
    /// A light that is on: the warm lit tile with dark ink.
    case lit
    /// A device that is on: filled with its family colour, with the family's ink.
    case filled(ColorFamily)
    /// A tile whose caller has not picked a family yet: dark ground with the caller's tint on the glyph and rim.
    case tinted
    /// Something is wrong (no response, a fault): dark dense ground, red glyph and red state.
    case error
    /// A navigation tile with its own solid fill (`0xRRGGBB`, ``RoomPalette``): white ink and a filled white glyph
    /// whether or not the thing it opens is "on".
    case colored(UInt32)

    /// The face for a tile's state.
    /// - Parameters:
    ///   - family: The device's colour family, or nil when the caller passes only a tint.
    ///   - isActive: Whether the device is on.
    ///   - isError: Whether the tile reports a fault.
    ///   - isUnavailable: Whether the entity is unavailable (drawn off and dimmed).
    ///   - solidFill: A fill the caller owns (a room's colour); it wins over the family unless the tile is in error or
    ///     unavailable.
    public static func resolve(family: ColorFamily?, isActive: Bool, isError: Bool, isUnavailable: Bool, solidFill: UInt32? = nil) -> Self {
        if isError { return .error }
        if let solidFill, !isUnavailable { return .colored(solidFill) }
        if isUnavailable || !isActive { return .off }
        guard let family else { return .tinted }
        if family == .lights { return .lit }
        return family.spec.fill == nil ? .tinted : .filled(family)
    }

    /// Black over the part of a white-ink filled face that progress has not reached, so the done part reads as
    /// the lighter band.
    public static let progressShade = 0.18
    /// White over the done part of a dark-ink filled face (power).
    public static let progressLighten = 0.25

    /// Whether this is a caller-coloured navigation tile.
    public var isColored: Bool {
        if case .colored = self { return true }
        return false
    }

    /// Whether text on this face is dark (the lit tile and power's yellow).
    public var hasDarkInk: Bool {
        switch self {
        case .lit: true
        case let .filled(family): family.spec.darkInk
        default: false
        }
    }
}

// MARK: - Light glyphs

public extension TileFaceStyle {
    /// A caller's tint made legible as a glyph on a light cell: unchanged when it already reaches 3:1 (WCAG 1.4.11) on
    /// the sheet ground, else mixed toward black until it does, keeping its hue.
    /// - Parameter rgb: The tint's sRGB channels, 0 to 1.
    /// - Returns: The tint's channels, darkened as needed.
    static func lightGlyph(forTint rgb: (red: Double, green: Double, blue: Double)) -> (red: Double, green: Double, blue: Double) {
        func luminance(_ c: (red: Double, green: Double, blue: Double)) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
        }
        let ground = Double((HassTokens.Palette.sheetGroundLight >> 16) & 0xFF) / 255
        let groundLuminance = luminance((ground, ground, ground))
        func ratio(_ c: (red: Double, green: Double, blue: Double)) -> Double {
            let l = luminance(c)
            return (max(l, groundLuminance) + 0.05) / (min(l, groundLuminance) + 0.05)
        }
        var keep = 1.0
        var shaded = rgb
        while ratio(shaded) < 3.3, keep > 0 {
            keep -= 0.02
            shaded = (rgb.red * keep, rgb.green * keep, rgb.blue * keep)
        }
        return shaded
    }
}
