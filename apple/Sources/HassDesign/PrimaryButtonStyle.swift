import SwiftUI

/// The look of the primary button: height and colours (`UKPrimaryButton` draws it).
public enum PrimaryButtonStyle {
    /// The button's height, and twice its corner radius.
    public static let height: CGFloat = 50

    /// The fill and label colours: the tint with white, or a family's glyph colour with dark text. Both are fixed, in
    /// light and dark sheets alike (the family's dark-appearance glyph, not its light-sheet variant).
    public static func colors(_ family: ColorFamily?) -> (fill: Color, label: Color) {
        guard let family else { return (HassTokens.Ink.actionFill, .white) }
        return (Color(rgb: family.spec.glyph), HassTokens.Ink.onFamilyFill)
    }
}
