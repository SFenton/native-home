import SwiftUI

/// How a tile arranges its glyph, title and state (`.agents/design/direction-g.md`, Controls: Tiles; pattern
/// `.agents/patterns/entity-tile.md`).
///
/// Owner, 2026-10-16: "it feels too high up / lots of dead space, but I like the tiles themselves". Four arrangements
/// were drawn on the Direction G gallery (`FENTON_GALLERY=direction-g`, Tile Layouts) and measured on iPhone, folded
/// Duo and iPad at the default size and AX5. The shipped default is ``TileLayout/standard``.
public enum TileLayout: String, Sendable, CaseIterable, Identifiable {
    /// The glyph leads and the title and state sit beside it, the whole row centred vertically in the tile, like Apple
    /// Home's accessory tiles.
    case row
    /// The glyph top-leading and the title and state anchored bottom-leading, so text never floats under the glyph in a
    /// tall row.
    case anchoredBottom
    /// The glyph over the title and state, the pair centred vertically and leading aligned.
    case centeredStack
    /// Before 2026-10-16: the glyph, title and state stacked at the top, with any spare height left at the bottom.
    case stackedTop

    public var id: String { rawValue }

    /// The layout every tile uses unless a gallery overrides it (``SwiftUICore/EnvironmentValues/tileLayout``).
    public static let standard: TileLayout = .row

    /// The tile's minimum content height; the 12 pt padding on each side is added, so every layout keeps the 44 pt
    /// target with room to spare (tiles measure 72, 96, 84 and 112 pt).
    public var minHeight: CGFloat {
        switch self {
        case .row: 48
        case .anchoredBottom: 72
        case .centeredStack: 60
        case .stackedTop: 88
        }
    }

    /// The arrangement actually drawn: a row needs width for the text beside the glyph, so accessibility text sizes
    /// anchor the text to the bottom instead (HIG: Typography, "Dynamic Type").
    public func resolved(accessibilitySize: Bool) -> TileLayout {
        self == .row && accessibilitySize ? .anchoredBottom : self
    }
}

public extension EnvironmentValues {
    /// The arrangement of tiles inside (``TileLayout``).
    @Entry var tileLayout: TileLayout = .standard
}

public extension View {
    /// Draws tiles inside with `layout`; the gallery uses it to compare arrangements.
    func tileLayout(_ layout: TileLayout) -> some View { environment(\.tileLayout, layout) }
}

// MARK: - Title reserve

public extension EnvironmentValues {
    /// How many lines of title a tile keeps room for (``TileMetrics/minContentHeight(layout:titleLines:glyphHeight:titleLineHeight:)``);
    /// 0 sizes a tile to its content. The Rooms grid asks for two (owner, 2026-10-16: "room for two lines of text").
    @Entry var tileTitleLines: Int = 0
}

public extension View {
    /// Keeps room in every tile inside for `lines` lines of title at the current Dynamic Type size, so a one-line name
    /// sits on the bottom line of an anchored tile and a two-line name fills both lines, with equal tile heights.
    func tileTitleLines(_ lines: Int) -> some View { environment(\.tileTitleLines, lines) }
}
