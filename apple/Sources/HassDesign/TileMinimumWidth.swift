import SwiftUI

public extension TileMinimumWidth {
    /// The least width the text column of a tile is given, so a short title ("Lock") does not make a tile narrower than one disc
    /// and a glyph need (architecture: 96 pt of text, so a carried-glyph tile with one disc is 172 pt and two discs 228 pt).
    static let textFloor: CGFloat = 96

    /// The minimum width of a tile that shows its text on one line beside its controls.
    ///
    /// Declared from content, never measured by laying the tile out: the widest line of text, the leading glyph column when the
    /// tile draws one, the chevron's reserve on a navigation tile, the trailing strip and its gap to the text when the discs trail,
    /// and the padding on both sides. The text is the *widest possible* one (the title and the longest state a provider can
    /// show), so a live state change never changes the minimum and never re-spans the grid.
    /// - Parameters:
    ///   - text: The widest single line of text, in points.
    ///   - glyphColumn: The leading glyph and its gap to the text, or 0 when none is drawn (a carried-glyph action tile, a stacked layout).
    ///   - chevron: The chevron's reserve, or 0.
    ///   - strip: The trailing strip and its gap to the text, or 0 when the discs sit below.
    static func width(text: CGFloat, glyphColumn: CGFloat, chevron: CGFloat, strip: CGFloat) -> CGFloat {
        2 * HassTokens.Spacing.m + glyphColumn + max(text, textFloor) + chevron + strip
    }

    /// Whether a tile resolved to `resolved` wide cannot show its text on one line: its minimum is wider (the grid capped it).
    static func isCapped(resolved: CGFloat, minimum: CGFloat) -> Bool { minimum - 0.5 > resolved }
}

public extension TileMinimumWidth {
    /// The minimum width for a tile's text, measured at `typeSize` and fed to ``width(text:glyphColumn:chevron:strip:)``.
    ///
    /// The state line is the widest of `states` (every state a provider can show). When there are `states`, `shown` is ignored, so a
    /// live text longer than every candidate cannot change the minimum and re-span the grid: it truncates or tickers instead. With
    /// no `states` the tile's subtitle is static configuration, and `shown` is measured.
    @MainActor
    static func width(title: String, shown: String?, states: [String], typeSize: DynamicTypeSize, glyphColumn: CGFloat,
                      chevron: CGFloat, strip: CGFloat) -> CGFloat {
        let titleWidth = TileTextMeasure.width(title, style: .title, typeSize: typeSize)
        let stateWidth = TileTextMeasure.widest(states.isEmpty ? [shown].compactMap { $0 } : states, style: .state, typeSize: typeSize)
        return width(text: max(titleWidth, stateWidth), glyphColumn: glyphColumn, chevron: chevron, strip: strip)
    }
}
