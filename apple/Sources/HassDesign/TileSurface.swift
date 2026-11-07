import SwiftUI

/// Where a tile sits, which sets the ground of its dark faces.
public enum TileSurface: Sendable {
    /// On the wallpaper: the thin module material.
    case page
    /// Inside a sheet: the sheet's cell colour, `#2C2C2E`.
    case sheet

    /// Secondary text and neutral glyphs on a module: the module's fixed light ink on the wallpaper, the sheet's adaptive
    /// ink in a sheet (a light sheet's cell is white, where the module's ink would vanish).
    public var secondaryInk: Color { Color(secondaryInkToken) }

    /// ``secondaryInk`` as raw sRGB.
    public var secondaryInkToken: HassRGB {
        self == .sheet ? HassTokens.RGB.Surface.secondaryInSheet : HassTokens.RGB.Surface.secondaryOnModule
    }
}

public extension EnvironmentValues {
    /// Where tiles inside are drawn (``TileSurface``). `modalChrome()` sets `.sheet`.
    @Entry var tileSurface: TileSurface = .page
}
