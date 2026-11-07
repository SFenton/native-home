import SwiftUI

/// Measurements of the inset grouped look, matched to the system's `List` on iPhone, iPad and iPhone Duo (compared on the
/// simulators by `build/compare/settings`).
public enum InsetGroupedMetrics {
    /// Space between the screen edge and a section's card in a compact-width window (iPhone, folded Duo).
    public static let margin: CGFloat = 16
    /// The same in a regular-width window (iPad, unfolded Duo), where the system's inset grouped `List` measured 20 pt: the card's edge
    /// sat 40 px in on the iPad's 1668 px (2x) and 60 px in on the Duo (3x), against 48 px (3x) on the iPhone, in the Settings
    /// comparison screenshots (`build/compare/settings`, 2026-10-27).
    public static let regularMargin: CGFloat = 20

    /// The card's side margin for a window's width class.
    public static func margin(regularWidth: Bool) -> CGFloat { regularWidth ? regularMargin : margin }
    /// Vertical padding around a button or link row's content (the system's cell adds the same around the row's 44 pt minimum).
    public static let rowPadding: CGFloat = 15
    /// Vertical padding around a control row's content (a toggle, a slider).
    public static let controlPadding: CGFloat = 10.5
    /// Width of the glyph column of a ``SettingsLinkRow``-style row, where its hairline's text inset starts after.
    public static let glyphColumn: CGFloat = 34
    /// Where a hairline stops short of the card's trailing edge (the system's separator ends inside the card too).
    public static let separatorTrailing: CGFloat = 16
    /// Space between a card's leading edge and its rows' content.
    public static let leadingInset: CGFloat = 15
    /// Space between a card's trailing edge and its rows' content.
    public static let trailingInset: CGFloat = 17.5
    /// Space above a section's header (or its card when it has none).
    public static let sectionTop: CGFloat = 28.5
    /// What a footer gives back of ``sectionTop``: the system's gap after a footer is shorter than after a card.
    public static let footerOverlap: CGFloat = 12.5
    /// Extra space above a section without a header, unless a footer sits above it (the page's first section has no section above).
    public static let headerlessExtra: CGFloat = 7
    /// Space between a header and its card.
    public static let headerGap: CGFloat = 10
    /// Space between a card and its footer.
    public static let footerGap: CGFloat = 8
    /// How far a header or footer is inset from the card's edge.
    public static let captionInset: CGFloat = 16
}
