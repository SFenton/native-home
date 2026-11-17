import Foundation

/// Which ink a dark tile face draws for an icon with no colour of its own and for its state line (`sh.tile-ink-default@1`, owner pick A,
/// `.agents/patterns/tile-swipe.md`, "Tile ink").
///
/// A document that declares the capability draws the primary ink: white on a page and in a dark sheet, black in a light sheet (the title's ink,
/// ``TileFaceInk/primaryToken(style:appearance:)``). Any other draws the muted grey it always drew. Only the dark faces (`off`, `tinted`) change;
/// filled and lit faces keep their ink, an error keeps its red, a warning its amber, and an unavailable tile stays grey at 50%.
public enum TileInkDefault: Sendable, Equatable {
    /// Today's grey icons and secondary state line.
    case muted
    /// The primary ink for an icon with no colour of its own and for the state line.
    case primary
}
