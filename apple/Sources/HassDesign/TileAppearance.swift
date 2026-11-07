import SwiftUI

/// Whether a tile's neutral parts (off ground, title and state ink, glyph) are drawn for the dark or the light
/// appearance. Only a tile in a sheet under the light scheme is light: pages are always dark, and a lit or filled face
/// keeps its fixed fill and ink either way.
public enum TileAppearance: Equatable, Sendable {
    case dark
    case light

    /// The appearance for a tile on `surface` under `scheme`.
    public static func resolve(surface: TileSurface, scheme: ColorScheme) -> Self {
        surface == .sheet && scheme == .light ? .light : .dark
    }

    /// The scheme the appearance's colours are drawn for.
    public var scheme: ColorScheme { self == .light ? .light : .dark }

    /// The glyph and state colour of an error face: `#FF6961` on dark, a dark red on a light cell.
    public var errorRGB: UInt32 {
        self == .light ? HassTokens.Palette.redLight : HassTokens.Palette.red
    }

    /// How strongly a state wash tints the ground: 60% over a dark module, 22% over a white cell so the ink on it keeps
    /// 4.5:1.
    public var washOpacity: Double { self == .light ? 0.22 : 0.6 }
}
