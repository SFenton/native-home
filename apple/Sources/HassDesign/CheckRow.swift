import SwiftUI

// MARK: - Metrics

/// The numbers of a check row, shared by the SwiftUI ``CheckRow`` and the UIKit port's `UKCheckRow` (pattern:
/// `.agents/patterns/check-row.md`; owner, 2026-10-30).
public enum CheckRowMetrics {
    /// A row's minimum height; text growth makes it taller.
    public static let height: CGFloat = ModuleRowMetrics.height
    /// Space above and below the text block.
    public static let verticalPadding: CGFloat = 11
    /// The check column's width at the default text size; it scales with the title.
    public static let glyphWidth: CGFloat = ModuleRowMetrics.glyphWidth
    /// Space between the check column and the text.
    public static let gap: CGFloat = ModuleRowMetrics.gap
    /// The row's leading edge to the check glyph.
    public static let leadingInset: CGFloat = HassTokens.Spacing.l
    /// The trailing margin after a row with no accessory.
    public static let plainTrailingInset: CGFloat = HassTokens.Spacing.l
    /// The trailing margin after an icon accessory (the edit button, whose 44 pt target already carries its own padding).
    public static let iconAccessoryTrailingInset: CGFloat = HassTokens.Spacing.xs
    /// The trailing margin after a text accessory (Undo).
    public static let textAccessoryTrailingInset: CGFloat = HassTokens.Spacing.m
    /// A dimmed glyph: the row cannot change (the title keeps its contrast).
    public static let dimmedGlyphOpacity: Double = 0.5

    /// The glyph for an unchecked and a checked row.
    public static func symbol(checked: Bool) -> String { checked ? "checkmark.circle.fill" : "circle" }

    /// The trailing edit button's glyph (owner, 2026-10-16: not the info circle).
    public static let editSymbol = "square.and.pencil"
}

// MARK: - Accessibility


// MARK: - Row




