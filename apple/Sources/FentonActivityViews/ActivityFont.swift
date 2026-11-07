import SwiftUI

/// A system font at an exact design size that still follows Dynamic Type: the spec's sizes (17 pt title, 32 pt value, 24 pt
/// big line) scale from their text style, so the Lock Screen grows with the person's setting while the island, which caps
/// its text size, keeps its regions' measure.
struct ActivityFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    /// The view's text at `size` points (at the default setting), scaling like `style`.
    func activityFont(_ size: CGFloat, weight: Font.Weight = .semibold, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ActivityFontModifier(size: size, weight: weight, relativeTo: style))
    }
}
