#if os(iOS)
import UIKit

/// Dynamic Type fonts the way SwiftUI's `.font(.body.weight(.semibold))` makes them: the text style's preferred font at the
/// user's size, with a weight, tracking `UIContentSizeCategory` changes when set on a label with `adjustsFontForContentSizeCategory`.
enum UKShellFont {
    /// `UIFont.preferredFont(forTextStyle:)` at `weight` (and optionally monospaced digits, italic or rounded design).
    static func preferred(_ style: UIFont.TextStyle, weight: UIFont.Weight? = nil, design: UIFontDescriptor.SystemDesign? = nil,
                          traits: UITraitCollection? = nil) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
        var descriptor = base.fontDescriptor
        if let weight {
            descriptor = descriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]])
        }
        if let design, let designed = descriptor.withDesign(design) { descriptor = designed }
        return UIFont(descriptor: descriptor, size: 0)
    }

    /// A metric that follows the text size of `style` (`@ScaledMetric(relativeTo:)`).
    static func scaled(_ value: CGFloat, relativeTo style: UIFont.TextStyle, traits: UITraitCollection? = nil) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: value, compatibleWith: traits)
    }
}

extension UIView {
    /// The view controller this view is in, found through the responder chain.
    var ukOwningViewController: UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}
#endif
