import SwiftUI

/// A status chip's computed look: its fill and glyph as `0xRRGGBB`, kept raw so tests can check contrast
/// (`.agents/patterns/status-rail.md`, "Chip colours").
///
/// Most chips take their colours from a ``ColorFamily`` (``init(family:)``). Climate and Air Quality take theirs from the
/// colour Home Assistant computes, and Contact Sensors from what is open and what the house is doing, so those build a
/// tint instead. White text always sits on ``fill``, so every tint is darkened until white passes 4.5:1 on it, including
/// under the chip's top highlight (``liftedFill``), and its glyph is lightened until it keeps 3:1 (WCAG 1.4.11).
public struct ChipTint: Equatable, Sendable {
    /// The chip's capsule colour.
    public var fill: UInt32
    /// The glyph colour.
    public var glyph: UInt32

    /// Creates a tint from raw values; callers that compute colours go through ``fromWeb(_:)``.
    public init(fill: UInt32, glyph: UInt32) {
        self.fill = fill
        self.glyph = glyph
    }

    /// The tint a family's active chip draws, or nil when the family has no chip fill.
    public init?(family: ColorFamily) {
        guard let fill = family.chipFillRGB else { return nil }
        self.init(fill: fill, glyph: family.chipGlyphRGB)
    }

    /// ``fill`` as a colour.
    public var fillColor: Color { Color(rgb: fill) }

    /// ``glyph`` as a colour.
    public var glyphColor: Color { Color(rgb: glyph) }

    /// The ground under the chip's text near the top, where `StatusChipStyle` lays a 12% white highlight.
    public var liftedFill: UInt32 { ColorFamily.mix(0xFFFFFF, fill, Self.highlight) }

    // MARK: - Contact states

    /// Everything shut: the contact family's soft green (`#3B523E`) with its green glyph.
    public static let contactClosed = ChipTint(fill: 0x3B523E, glyph: 0x7ED787)
    /// Open while someone is home and the system is off: a darkened `#FFB340` warning amber.
    public static let contactOpenHome = ChipTint(fill: 0x8A5200, glyph: 0xFFC25C)
    /// Open while the household is away: the web's window-open coral.
    public static let contactOpenAway = ChipTint(fill: 0xB23A26, glyph: 0xFFD2C8)
    /// Open while the system is armed: the triggered red.
    public static let contactOpenArmed = ChipTint(fill: 0xD70015, glyph: 0xFFFFFF)

    // MARK: - Computed from a web colour

    /// The share of a web colour kept in the fill. The web draws card colours at 60% over a dark ground; 0.73 maps its
    /// air teal `rgb(0, 150, 136)` onto `#006E63`, within a step of the Air family's `#006E62`.
    static let fillScale = 0.73
    /// The chip's top highlight opacity (`StatusChipStyle`).
    public static let highlight = 0.12
    /// Body text contrast (WCAG 1.4.3).
    public static let textContrast = 4.5
    /// Non-text contrast for the glyph (WCAG 1.4.11).
    public static let glyphContrast = 3.0

    /// A chip tint for a colour Home Assistant supplies: the colour scaled toward black to a fill that white text reads on
    /// (4.5:1, also under the highlight), and the colour itself lightened toward white until the glyph keeps 3:1 on it.
    /// Deterministic, so the same temperature or AQI colour always gives the same chip.
    /// - Parameters:
    ///   - rgb: The web colour as `0xRRGGBB`.
    ///   - preferredGlyph: A glyph colour to keep when it already reads (the Climate chip's yellow thermometer).
    public static func fromWeb(_ rgb: UInt32, preferredGlyph: UInt32? = nil) -> ChipTint {
        var fill = ColorFamily.mix(rgb, 0x000000, fillScale)
        var tint = ChipTint(fill: fill, glyph: rgb)
        while contrast(0xFFFFFF, tint.liftedFill) < textContrast, fill != 0 {
            fill = ColorFamily.mix(fill, 0x000000, 0.95)
            tint.fill = fill
        }
        tint.glyph = tint.legibleGlyph(rgb, preferred: preferredGlyph)
        return tint
    }

    /// The glyph for `color` on this fill: `preferred` if it reads, else `color` lightened toward white until it does.
    private func legibleGlyph(_ color: UInt32, preferred: UInt32?) -> UInt32 {
        func reads(_ glyph: UInt32) -> Bool {
            Self.contrast(glyph, fill) >= Self.glyphContrast && Self.contrast(glyph, liftedFill) >= Self.glyphContrast
        }
        if let preferred, reads(preferred) { return preferred }
        var amount = 0.0
        var glyph = color
        while !reads(glyph), amount < 1 {
            amount += 0.05
            glyph = ColorFamily.mix(0xFFFFFF, color, amount)
        }
        return glyph
    }

    // MARK: - Contrast

    /// Whether two `0xRRGGBB` colours are within `tolerance` on every channel.
    public static func isClose(_ a: UInt32, _ b: UInt32, tolerance: Int = 2) -> Bool {
        [16, 8, 0].allSatisfy { abs(Int((a >> $0) & 0xFF) - Int((b >> $0) & 0xFF)) <= tolerance }
    }

    /// WCAG relative luminance of `0xRRGGBB`.
    public static func luminance(_ rgb: UInt32) -> Double {
        func linear(_ shift: UInt32) -> Double {
            let c = Double((rgb >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(16) + 0.7152 * linear(8) + 0.0722 * linear(0)
    }

    /// WCAG contrast ratio between two `0xRRGGBB` colours.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
