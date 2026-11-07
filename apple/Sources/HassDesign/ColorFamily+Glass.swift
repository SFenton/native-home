import SwiftUI

/// The off glyph under the tinted glass finish.
extension ColorFamily {
    /// The glyph an off tile draws under `finish`: the family colour mixed toward grey (``offGlyphRGB(_:keep:)``), which
    /// tinted glass lifts toward white where that is what keeps it at 3:1 (WCAG 1.4.11) on the lightest ground the finish
    /// draws a glyph on. The muted Food families need it: on the wallpaper's lightest region the top highlight left them at
    /// 2.85:1.
    public func offGlyphRGB(_ scheme: ColorScheme, under finish: TileFinish) -> UInt32 {
        guard finish != .solid else { return offGlyphRGB(scheme) }
        let mixed = offGlyphRGB(scheme, keep: finish.offGlyphKeep)
        return scheme == .light ? mixed : Self.liftedGlyphs[self] ?? mixed
    }

    /// The lightest ground tinted glass draws behind a glyph on a page: the thin module over the wallpaper's lightest region
    /// (sRGB grey 0.46, the lightest under which white text still reads 4.5:1), plus the sheen's highlight where an
    /// anchored-bottom tile's glyph sits (15% of the height).
    static let lightestGlyphGround: UInt32 = {
        let tokens = TileFinish.Tokens.tintedGlass(on: .page)
        let highlight = tokens.sheenTop * (1 - 0.15 / TileFinish.Tokens.sheenClearStop)
        let (r, g, b, a) = FinishColor.premultiplied([(0x757575, 1), (HassTokens.Palette.moduleThin, tokens.underlay), (0xFFFFFF, highlight)])
        func channel(_ value: Double) -> UInt32 { UInt32((value / a * 255).rounded()) }
        return channel(r) << 16 | channel(g) << 8 | channel(b)
    }()

    /// Each family's dark off glyph, mixed with white in steps of 4% until it reads 3:1 (3.05 for rounding) on
    /// ``lightestGlyphGround``.
    private static let liftedGlyphs: [ColorFamily: UInt32] = Dictionary(uniqueKeysWithValues: allCases.map { family in
        let base = family.offGlyphRGB(.dark, keep: TileFinish.tintedGlass.offGlyphKeep)
        var amount = 0.0, glyph = base
        while ChipTint.contrast(glyph, lightestGlyphGround) < 3.05, amount < 1 {
            amount += 0.04
            glyph = mix(0xFFFFFF, base, amount)
        }
        return (family, glyph)
    })
}
