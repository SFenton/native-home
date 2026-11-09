#if os(iOS)
import UIKit

/// SwiftUI's text styles as UIKit fonts: `Font.body.weight(.semibold)` is `UKFont.preferred(.body, weight: .semibold)`.
/// Every font keeps its text style, so a label with `adjustsFontForContentSizeCategory = true` follows Dynamic Type to AX5.
public enum UKFont {
    /// The preferred font of a text style with a weight, optionally with monospaced digits (`.monospacedDigit()`).
    /// SwiftUI's `.bold()` (and `.weight(.bold)`) is the bold trait of the text style's font, so `.bold` uses it.
    /// - Parameter traits: The trait collection whose content size category scales the font; nil uses the current one.
    public static func preferred(_ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, monospacedDigit: Bool = false,
                                 bold: Bool = false, traits: UITraitCollection? = nil) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        var descriptor = base.fontDescriptor
        if weight == .bold || (weight == nil && bold), let boldDescriptor = descriptor.withSymbolicTraits(.traitBold) {
            descriptor = boldDescriptor
        } else if let weight {
            descriptor = descriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        }
        if monospacedDigit {
            descriptor = descriptor.addingAttributes([
                .featureSettings: [[
                    UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                    UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
                ]],
            ])
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    /// A fixed design size that still scales with Dynamic Type relative to `style` (`@ScaledMetric(relativeTo:)` text).
    public static func scaled(size: CGFloat, weight: UIFont.Weight, relativeTo style: UIFont.TextStyle, monospacedDigit: Bool = false) -> UIFont {
        let font = monospacedDigit
            ? UIFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : UIFont.systemFont(ofSize: size, weight: weight)
        return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }
}

extension UITraitCollection {
    /// `typeSize.isAccessibilitySize`.
    var isAccessibilitySize: Bool { preferredContentSizeCategory.isAccessibilityCategory }
}
#endif
