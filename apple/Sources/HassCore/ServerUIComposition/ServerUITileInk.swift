import Foundation

// MARK: - Tile ink and cell fit (`sh.tile-ink@1`)

/// What a state tile says about its own ink and its place in a taller cell (`sh.tile-ink@1`): the colour of its icon, the colour of its
/// button icons, and whether it stretches to its cell.
///
/// Every field is optional and the defaults draw what a tile drew before: a grey icon, white button icons, a tile that fills its cell.
/// The ink of the state line on a fill is not here: it is a field of a state style's rule (``StateFillInk``).
public struct ServerUITileInk: Equatable, Sendable {
    /// One exact colour for each appearance. A single `solid-rgb` has the same colour in both.
    public struct Tint: Equatable, Sendable {
        public var light: ServerUIRGB
        public var dark: ServerUIRGB

        public init(light: ServerUIRGB, dark: ServerUIRGB) {
            self.light = light
            self.dark = dark
        }

        /// The colour for an appearance.
        public func rgb(isDark: Bool) -> ServerUIRGB { isDark ? dark : light }

        /// `0xRRGGBB` for an appearance.
        public func packed(isDark: Bool) -> UInt32 {
            let color = rgb(isDark: isDark)
            return UInt32(color.red) << 16 | UInt32(color.green) << 8 | UInt32(color.blue)
        }
    }

    /// How the tile sits in a cell taller than itself (a grid with `equalRowHeights`).
    public enum CellFit: String, Equatable, Sendable, CaseIterable {
        /// The tile stretches to its cell. The default, and what a tile always did.
        case fill
        /// The tile keeps its own height at the top of the cell; the row is still as tall as its tallest cell.
        case natural
    }

    /// The icon's colour on a face that is neither filled nor an error; nil keeps the grey.
    public var glyphTint: Tint?
    /// The button icons' colour on a face that is not filled; nil keeps white.
    public var discGlyphTint: Tint?
    /// The tile's fit in its cell.
    public var cellFit: CellFit = .fill
    /// Whether the document wrote any of the three fields (even `cellFit: "fill"`), which makes it need `sh.tile-ink@1`.
    public var isDeclared = false

    public init() {}

    /// Whether the tile asks for its own height in a taller cell.
    public var keepsNaturalHeight: Bool { cellFit == .natural }
}
