import SwiftUI

/// How a tile's surface is finished. **Tinted glass** is the app's finish (owner, 2026-10-17: Direction G, Tile finish,
/// option A); **solid** is the opaque finish it falls back to when Reduce Transparency or Increase Contrast is on.
///
/// Tinted glass is the family fill at 78% over a dark underlay, so the wallpaper tints it a little, with a lit hairline and
/// a soft top highlight (a faint shade at the bottom). Every state keeps the solid finish's meaning; the difference is edge
/// and depth, which answers "subtle, less childish" (owner, 2026-10-16) while the glanceable family-colour fill stays.
///
/// **No live blur.** The finish is built from translucency over the wallpaper (which is blurred once and cached), one
/// gradient and a hairline, never `.blur` or a material per tile, which cost GPU time and crashed the render server
/// (direction-g.md, Layers; performance.md).
///
/// **HIG.** Tiles are content-layer elements, so none uses Liquid Glass (HIG, Materials: "Don't use Liquid Glass in the
/// content layer"); translucency and a hairline stand in for a standard material. With Reduce Transparency or Increase
/// Contrast the finish is ``solid`` (HIG, Accessibility), see ``effective(_:reduceTransparency:increasedContrast:)``.
public enum TileFinish: String, CaseIterable, Identifiable, Sendable {
    /// The shipped finish: the family fill at 78% over a dark underlay, a lit hairline and a soft top highlight.
    case tintedGlass
    /// Opaque: a solid family fill (or the thin module for off) with a faint top highlight. The Reduce Transparency and
    /// Increase Contrast fallback.
    case solid

    public var id: String { rawValue }

    /// The finish every tile uses unless the environment says otherwise. A debug build reads `FENTON_TILE_FINISH`
    /// (`solid`, `tintedGlass`) so the scroll cost probe can measure the finish against the fallback on real pages.
    public static let standard: TileFinish = {
        #if DEBUG
        if let name = ProcessInfo.processInfo.environment["FENTON_TILE_FINISH"], let finish = TileFinish(rawValue: name) {
            return finish
        }
        #endif
        return .tintedGlass
    }()

    /// Layers a Debug launch leaves out (`FENTON_TILE_FINISH_OMIT=sheen,rim`), to measure what each costs the scroll
    /// (performance.md). Always empty in a Release build.
    public static let omitted: Set<String> = {
        #if DEBUG
        return Set((ProcessInfo.processInfo.environment["FENTON_TILE_FINISH_OMIT"] ?? "").split(separator: ",").map(String.init))
        #else
        return []
        #endif
    }()

    /// How much of the family colour an off glyph keeps (``ColorFamily/offGlyphRGB(_:keep:)``): the solid 72%, or more on
    /// the tinted ground, which is a little lighter than the thin module.
    public var offGlyphKeep: Double { self == .solid ? 0.72 : 0.88 }

    /// The finish a tile draws: the preferred one, or ``solid`` when the person turned on Reduce Transparency or Increase
    /// Contrast (HIG, Accessibility), which keeps every ground opaque.
    public static func effective(_ preferred: TileFinish, reduceTransparency: Bool, increasedContrast: Bool) -> TileFinish {
        reduceTransparency || increasedContrast ? .solid : preferred
    }
}

// MARK: - Tokens

public extension TileFinish {
    /// The numbers behind tinted glass, named so direction G can record them as design tokens.
    ///
    /// Opacities are 0 to 1. A *sheen* is one vertical gradient (a white highlight at the top, a black shade at the
    /// bottom) so a tile draws one gradient layer, not two. A *rim* is a 1 pt hairline stroked with a vertical white
    /// gradient, lit at the top.
    struct Tokens: Equatable, Sendable {
        /// The dark underlay beneath the off ground: `#1C1C1E` at this opacity (the thin module's 0.66).
        public var underlay: Double
        /// The underlay beneath a translucent family fill: lower than ``underlay`` because a saturated fill hides more of
        /// the module, so the wallpaper can tint it without costing the white ink its 4.5:1.
        public var fillUnderlay: Double
        /// The opacity of a white-ink family or room fill over the underlay; dark-ink fills (lights, power) stay opaque.
        public var fillOpacity: Double
        /// White at the top of the sheen, and black at the bottom.
        public var sheenTop: Double
        public var sheenBottom: Double
        /// The rim's white at the top edge, and at the bottom edge.
        public var rimTop: Double
        public var rimBottom: Double

        /// Where the sheen's highlight has faded to clear, as a fraction of the tile's height.
        public static let sheenClearStop = 0.46

        /// The tinted glass tokens for a tile on `surface`. A sheet has no wallpaper to show through, so the finish there
        /// is opaque: the same sheen and rim over the cell.
        public static func tintedGlass(on surface: TileSurface) -> Tokens {
            Tokens(underlay: 0.66, fillUnderlay: 0.50, fillOpacity: surface == .page ? 0.78 : 1, sheenTop: 0.14, sheenBottom: 0.08,
                   rimTop: 0.32, rimBottom: 0.06)
        }
    }
}

// MARK: - Environment

public extension EnvironmentValues {
    /// The finish tiles inside are drawn with (``TileFinish``).
    @Entry var tileFinish: TileFinish = .standard
}

public extension View {
    /// Draws tiles inside with `finish`; the gallery uses it to show the solid fallback beside the shipped finish.
    func tileFinish(_ finish: TileFinish) -> some View { environment(\.tileFinish, finish) }
}
