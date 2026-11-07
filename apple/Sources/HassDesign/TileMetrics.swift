import SwiftUI

/// The height arithmetic of a tile that reserves title lines, apart from the drawing so it is unit tested.
public enum TileMetrics {
    /// A title-style line (subheadline semibold) at the default text size, scaled with Dynamic Type by the face.
    public static let titleLineHeight: CGFloat = 20
    /// The glyph's line (title3) at the default text size.
    public static let glyphHeight: CGFloat = 24
    /// The least space between the glyph and the text of a stacked tile.
    public static let glyphGap: CGFloat = HassTokens.Spacing.s

    /// The content height a tile keeps before its padding.
    /// - Parameters:
    ///   - layout: The arrangement drawn.
    ///   - titleLines: Lines of title to reserve; 0 reserves none.
    ///   - glyphHeight: The glyph's height at the current text size.
    ///   - titleLineHeight: One title line at the current text size.
    /// - Returns: The layout's own minimum, raised to fit the glyph, the gap and the reserved lines in a stacked
    ///   arrangement, or the lines alone beside the glyph in a row.
    public static func minContentHeight(layout: TileLayout, titleLines: Int, glyphHeight: CGFloat = glyphHeight,
                                        titleLineHeight: CGFloat = titleLineHeight) -> CGFloat {
        guard titleLines > 0 else { return layout.minHeight }
        let lines = CGFloat(titleLines) * titleLineHeight
        switch layout {
        case .row: return max(layout.minHeight, lines)
        case .anchoredBottom, .centeredStack, .stackedTop: return max(layout.minHeight, glyphHeight + glyphGap + lines)
        }
    }
}
