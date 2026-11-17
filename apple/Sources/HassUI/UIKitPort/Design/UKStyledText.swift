#if os(iOS)
import HassCore
import UIKit

// MARK: - Styled text (`sh.text-style@1`)

/// The UIKit side of a text's look: the font a weight, digits and scaled size make, the colour of an ink, and the alignment of a line.
///
/// A scaled size follows the Dynamic Type curve of the style it is relative to and never passes its cap (`UIFontMetrics`), so the numeral of a
/// header grows with the person's text size up to the point the author chose. An empty look gives the style's own font, colour and alignment.
@MainActor
enum UKStyledText {
    /// The UIKit text style of a document text size.
    static func textStyle(_ size: ServerUITextSize) -> UIFont.TextStyle {
        switch size {
        case .largeTitle: .largeTitle
        case .title1: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption1: .caption1
        case .caption2: .caption2
        }
    }

    /// The UIKit weight of a document weight.
    static func weight(_ value: ServerUITextLook.Weight) -> UIFont.Weight {
        switch value {
        case .ultraLight: .ultraLight
        case .thin: .thin
        case .light: .light
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }

    /// The size a fixed size takes at the text size `traits` name: scaled as `size.relativeTo` is, up to `maxPoints`.
    static func scaledPoints(_ scale: ServerUITextLook.Scale, traits: UITraitCollection) -> CGFloat {
        let scaled = UIFontMetrics(forTextStyle: textStyle(scale.relativeTo)).scaledValue(for: CGFloat(scale.points), compatibleWith: traits)
        return scale.maxPoints.map { min(scaled, CGFloat($0)) } ?? scaled
    }

    /// `font` with digits of one width.
    static func monospacingDigits(_ font: UIFont) -> UIFont {
        UIFont(descriptor: font.fontDescriptor.addingAttributes([.featureSettings: [[
            UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
            UIFontDescriptor.FeatureKey.selector: kMonospacedNumbersSelector,
        ]]]), size: font.pointSize)
    }

    /// The weight the system gives `style` at `traits` (a headline is semibold, a body regular).
    static func styleWeight(_ style: UIFont.TextStyle, traits: UITraitCollection) -> UIFont.Weight {
        let font = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        let attributes = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        return (attributes?[.weight] as? CGFloat).map { UIFont.Weight($0) } ?? .regular
    }

    /// The font of a text in `style` with `look`, or `nil` when the look changes none of weight, digits and size.
    /// - Parameter baseWeight: The weight the text has with no `weight` of its own, when it is not the style's (a section title is bold).
    static func font(style: UIFont.TextStyle, look: ServerUITextLook, traits: UITraitCollection, baseWeight: UIFont.Weight? = nil) -> UIFont? {
        guard look.weight != nil || look.digits != nil || look.scale != nil else { return nil }
        let monospaced = look.digits == .monospaced
        let weight = look.weight.map(weight) ?? baseWeight
        if let scale = look.scale {
            let font = UIFont.systemFont(ofSize: scaledPoints(scale, traits: traits), weight: weight ?? styleWeight(style, traits: traits))
            return monospaced ? monospacingDigits(font) : font
        }
        return UKFont.preferred(style, weight: weight, monospacedDigit: monospaced, traits: traits)
    }

    /// The colour of an ink: it follows the appearance of the view it lands on, and keeps its opacity.
    static func color(_ ink: ServerUIInk) -> UIColor {
        UIColor { traits in
            let color = ink.color(isDark: traits.userInterfaceStyle == .dark)
            return UIColor(red: CGFloat(color.rgb.red) / 255, green: CGFloat(color.rgb.green) / 255, blue: CGFloat(color.rgb.blue) / 255,
                           alpha: CGFloat(color.alpha))
        }
    }

    /// The alignment of a line: `start` and `end` are the logical edges, so they swap in a right-to-left language.
    static func alignment(_ align: ServerUITextLook.Align?, rightToLeft: Bool) -> NSTextAlignment {
        switch align {
        case nil, .start?: rightToLeft ? .right : .left
        case .center?: .center
        case .end?: rightToLeft ? .left : .right
        }
    }
}
#endif
