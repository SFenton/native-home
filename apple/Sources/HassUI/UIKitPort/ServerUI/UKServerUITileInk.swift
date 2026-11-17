#if os(iOS)
import HassCore
import HassDesign
import UIKit

// MARK: - Tile ink and cell fit (`sh.tile-ink@1`)

extension AppearanceFill {
    /// The pair a document wrote for a state tile's tint: its light and dark members as `0xRRGGBB`, exact, with no clamp.
    init(_ tint: ServerUITileInk.Tint) {
        self.init(light: tint.packed(isDark: false), dark: tint.packed(isDark: true))
    }
}

/// Puts what a state tile's document says about its own ink onto the tile's model.
///
/// The fields are only read here; where they apply is decided in `HassDesign` (``AuthoredTileInk``) and drawn by the face and its discs, so
/// a tile that wrote none of them is untouched: every property stays at the value the model starts with.
@MainActor
enum UKServerUITileInk {
    /// Sets the icon colour, the button icon colour, the cell fit and, from the state's resolution, the ink of the state line on a fill.
    /// - Parameters:
    ///   - ink: The tile's fields (`glyphTint`, `discGlyphTint`, `cellFit`).
    ///   - fillInk: The ink of the state line on the state's style fill; `nil` for a tile that has no style (the default white).
    ///   - model: The model the state style produced.
    static func apply(_ ink: ServerUITileInk, fillInk: StateFillInk?, to model: inout UKGlassTileModel) {
        model.glyphTint = ink.glyphTint.map(AppearanceFill.init)
        model.discGlyphTint = ink.discGlyphTint.map(AppearanceFill.init)
        model.keepsNaturalHeight = ink.keepsNaturalHeight
        model.softFillInk = fillInk == .soft
    }
}
#endif
