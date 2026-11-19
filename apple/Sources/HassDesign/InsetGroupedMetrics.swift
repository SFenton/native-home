import SwiftUI

/// Measurements of a settings row inside an inset grouped list, matched to the system's `List` on iPhone, iPad and iPhone Duo
/// (compared on the simulators against the system Settings screens). The group's own side margin, its gaps and its headers come from
/// the publication's spacing tokens, never from here.
public enum InsetGroupedMetrics {
    /// Vertical padding around a button or link row's content (the system's cell adds the same around the row's 44 pt minimum).
    public static let rowPadding: CGFloat = 15
    /// Vertical padding around a control row's content (a toggle, a slider).
    public static let controlPadding: CGFloat = 10.5
    /// Width of the glyph column of a settings link row, where its hairline's text inset starts after.
    public static let glyphColumn: CGFloat = 34
    /// Where a hairline stops short of the card's trailing edge (the system's separator ends inside the card too).
    public static let separatorTrailing: CGFloat = 16
    /// Space between a card's leading edge and its rows' content.
    public static let leadingInset: CGFloat = 15
    /// Space between a card's trailing edge and its rows' content.
    public static let trailingInset: CGFloat = 17.5
}
