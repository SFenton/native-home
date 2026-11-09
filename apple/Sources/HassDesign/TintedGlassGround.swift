import SwiftUI

/// The ground of a tile under the tinted glass finish (``TileFinish/tintedGlass``): a translucent family fill over a dark
/// underlay and one sheen gradient, never a live blur. ``GlassTileFace`` uses it instead of its solid ground whenever the
/// effective finish is not ``TileFinish/solid``.
struct TintedGlassGround: View {
    var style: TileFaceStyle
    var surface: TileSurface
    var appearance: TileAppearance
    /// The caller's tint, for a tinted face's progress band.
    var tint: Color
    var wash: Color?
    var level: Double?
    var levelTint: Color?
    /// The read-only face draws no sheen.
    var isFlat = false

    private var tokens: TileFinish.Tokens { .tintedGlass(on: surface) }

    var body: some View {
        let tokens = tokens
        ZStack(alignment: .leading) {
            switch style {
            case .off, .tinted, .error:
                neutral(dense: style == .error, tokens: tokens)
                if let wash { wash.opacity(appearance.washOpacity) }
                band { (levelTint ?? tint).opacity(0.32) }
            case .lit:
                // Dark ink on a light fill: lights and power stay opaque, because a translucent light fill over the dark
                // wallpaper only gets darker.
                LitTile.base
                band(default: 1) {
                    LinearGradient(colors: [LitTile.bandTop, LitTile.bandBottom], startPoint: .top, endPoint: .bottom)
                        .overlay { if let levelTint { levelTint.opacity(LitTile.bulbTint) } }
                }
            case let .colored(rgb):
                tinted(rgb, tokens)
            case let .filled(family):
                if family.spec.darkInk {
                    LinearGradient(colors: [LitTile.powerTop, family.fill ?? .yellow], startPoint: .top, endPoint: .bottom)
                } else {
                    tinted(family.spec.fill ?? 0, tokens)
                }
                if let level, level > 0 {
                    if family.spec.darkInk {
                        band { Color.white.opacity(TileFaceStyle.progressLighten) }
                    } else {
                        GeometryReader { proxy in
                            Color.black.opacity(TileFaceStyle.progressShade)
                                .frame(width: proxy.size.width * (1 - min(1, level)))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            if !isFlat { sheen(tokens) }
        }
    }

    // MARK: Layers

    /// The dark underlay on the page; the sheet's cell in a sheet.
    @ViewBuilder
    private func neutral(dense: Bool, tokens: TileFinish.Tokens) -> some View {
        switch surface {
        case .sheet:
            HassTokens.Surface.sheetCell
        case .page:
            if dense {
                // An error keeps the dense module, so its red state text holds 4.5:1 over the lit windows.
                Color(rgb: HassTokens.Palette.moduleDense).opacity(0.78)
            } else {
                Color(rgb: HassTokens.Palette.moduleThin).opacity(tokens.underlay)
            }
        }
    }

    /// A white-ink fill: the family colour over the dark underlay at the finish's opacity (opaque in a sheet). The two
    /// layers are flattened into one colour, a layer fewer per tile (performance.md).
    @ViewBuilder
    private func tinted(_ fill: UInt32, _ tokens: TileFinish.Tokens) -> some View {
        if surface == .page, tokens.fillOpacity < 1 {
            FinishColor.flatten([(HassTokens.Palette.moduleThin, tokens.fillUnderlay), (fill, tokens.fillOpacity)])
        } else {
            Color(rgb: fill)
        }
    }

    /// The one sheen gradient (``TintedGlassSheen``).
    @ViewBuilder
    private func sheen(_ tokens: TileFinish.Tokens) -> some View {
        // A white cell in a light sheet has nothing for a highlight or a shade to work on: the rim alone finishes it.
        let bareLightCell = surface == .sheet && appearance == .light && !style.isFilledOrLit
        // A room's or Quick Link's fill in a sheet is opaque and already close to the 4.5:1 its white ink needs (the solid
        // finish drew it flat for that reason), so there it gets only the bottom shade, never a highlight.
        if !bareLightCell {
            TintedGlassSheen(tokens: tokens, highlight: !(surface == .sheet && style.isColored))
        }
    }

    @ViewBuilder
    private func band(default fallback: Double? = nil, @ViewBuilder fill: () -> some View) -> some View {
        if let level = level ?? fallback, level > 0 {
            let band = fill()
            GeometryReader { proxy in
                band.frame(width: proxy.size.width * min(1, level))
            }
        }
    }
}
