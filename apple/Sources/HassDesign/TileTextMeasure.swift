import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// The natural single-line width of a tile's text, used to declare the tile's minimum width from content
/// (``TileMinimumWidth``). Measured with the platform font for the tile's text style at the current Dynamic Type size, not by
/// laying a view out, so a grid never asks a tile to size itself per pass (`.agents/patterns/dynamic-grid.md`). Results are cached
/// by text, style and size.
@MainActor
enum TileTextMeasure {
    /// The two lines a tile draws.
    enum Style: Hashable {
        /// The title: subheadline, bold (``HassTokens/Typography/tileTitle``).
        case title
        /// The state line: footnote.
        case state
    }

    private struct Key: Hashable {
        var text: String
        var style: Style
        var size: DynamicTypeSize
    }

    private static var cache: [Key: CGFloat] = [:]

    /// The width of `text` on one line, rounded up to a whole point.
    static func width(_ text: String, style: Style, typeSize: DynamicTypeSize) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let key = Key(text: text, style: style, size: typeSize)
        if let width = cache[key] { return width }
        if cache.count > 4_000 { cache.removeAll(keepingCapacity: true) }
        let width = measure(text, style: style, typeSize: typeSize).rounded(.up)
        cache[key] = width
        return width
    }

    /// The widest of `texts`.
    static func widest(_ texts: [String], style: Style, typeSize: DynamicTypeSize) -> CGFloat {
        texts.map { width($0, style: style, typeSize: typeSize) }.max() ?? 0
    }

    #if os(iOS)
    private static func measure(_ text: String, style: Style, typeSize: DynamicTypeSize) -> CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: typeSize.contentSizeCategory)
        var font = UIFont.preferredFont(forTextStyle: style == .title ? .subheadline : .footnote, compatibleWith: traits)
        if style == .title, let bold = font.fontDescriptor.withSymbolicTraits(.traitBold) { font = UIFont(descriptor: bold, size: 0) }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }
    #elseif os(macOS)
    /// The Mac host (unit and hosted tests) has no Dynamic Type: a step table stands in so tests see text grow.
    private static func measure(_ text: String, style: Style, typeSize: DynamicTypeSize) -> CGFloat {
        var font = NSFont.preferredFont(forTextStyle: style == .title ? .subheadline : .footnote)
        if style == .title { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        return (text as NSString).size(withAttributes: [.font: font]).width * typeSize.hostScale
    }
    #else
    private static func measure(_ text: String, style: Style, typeSize: DynamicTypeSize) -> CGFloat {
        CGFloat(text.count) * (style == .title ? 7.5 : 6.5)
    }
    #endif
}

#if os(iOS)
extension DynamicTypeSize {
    /// The UIKit category for this size.
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
#elseif os(macOS)
extension DynamicTypeSize {
    /// Roughly the iOS text-size scale relative to Large, for the Mac test host.
    var hostScale: CGFloat {
        switch self {
        case .xSmall: 0.82
        case .small: 0.88
        case .medium: 0.94
        case .large: 1
        case .xLarge: 1.12
        case .xxLarge: 1.24
        case .xxxLarge: 1.36
        case .accessibility1: 1.6
        case .accessibility2: 1.9
        case .accessibility3: 2.3
        case .accessibility4: 2.75
        case .accessibility5: 3.2
        @unknown default: 1
        }
    }
}
#endif
