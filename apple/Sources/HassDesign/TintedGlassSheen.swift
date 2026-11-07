import SwiftUI

/// The one sheen gradient of tinted glass: a white highlight at the top fading through clear to a black shade at the bottom
/// (the web's `::after` pair of gradients, merged so a tile draws one layer). Left out in a Debug launch with
/// `FENTON_TILE_FINISH_OMIT=sheen` (performance.md).
struct TintedGlassSheen: View {
    var tokens: TileFinish.Tokens
    /// Whether the white highlight is drawn; false leaves only the bottom shade.
    var highlight = true

    var body: some View {
        if !TileFinish.omitted.contains("sheen") {
            LinearGradient(
                stops: [.init(color: .white.opacity(highlight ? tokens.sheenTop : 0), location: 0),
                        .init(color: .clear, location: TileFinish.Tokens.sheenClearStop),
                        .init(color: .black.opacity(tokens.sheenBottom), location: 1)],
                startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        }
    }
}
