import SwiftUI

/// Measurements shared by ``ModuleRow`` and the hairlines of ``ModuleList``. Public so a feature row that can't be a
/// ``ModuleRow`` (a tinted title, a toggle glyph) lines up with the hairlines without repeating the numbers.
public enum ModuleRowMetrics {
    /// A row's minimum height; text growth makes it taller.
    public static let height: CGFloat = 52
    /// A row with a subtitle: its minimum height.
    public static let heightWithSubtitle: CGFloat = 60
    /// Width of the leading glyph column.
    public static let glyphWidth: CGFloat = 24
    /// Space between the glyph, the text and the accessory.
    public static let gap: CGFloat = 14
    /// Leading edge of the text, where hairlines start: padding, glyph and gap.
    public static let textInset: CGFloat = HassTokens.Spacing.l + glyphWidth + gap
}
