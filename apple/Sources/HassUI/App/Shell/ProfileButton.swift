import CoreGraphics
import Foundation
import HassDesign
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The profile button's rules, drawn by `UKProfileButtonView` (owner, 2026-10-13: "profile goes in top right"). It shows the
/// signed-in user's initials on a 44 pt disc that is the whole button, or a person symbol until the name is known, and opens
/// the Account sheet. Owner 2026-10-18, option A: the avatar takes its whole container; Quick Links stays a separate glass
/// circle beside it.
enum ProfileButton {
    /// Up to two initials from a display name ("Alex Morgan" → "AM"); nil when it has no letters.
    static func initials(_ name: String?) -> String? {
        guard let name else { return nil }
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init)
        let value = letters.joined().uppercased()
        return value.isEmpty ? nil : value
    }

    /// "Alex Morgan, 3 items need attention": the person, then what is waiting (web `profile.openWithAttention`).
    static func accessibilityValue(name: String?, attentionCount: Int, isOffline: Bool = false) -> String {
        let attention = attentionCount > 0 ? "\(attentionCount) \(attentionCount == 1 ? "item needs" : "items need") attention" : nil
        return [name, attention, isOffline ? "Offline" : nil].compactMap { $0 }.joined(separator: ", ")
    }

    /// The text sizes the count badge follows the person's setting through: caption1 bold grows with Dynamic Type up to xLarge
    /// (the cap the disc's initials already follow), then holds, so the badge stays a small marker on the disc and never covers it.
    static let badgeTypeRange: ClosedRange<DynamicTypeSize> = .xSmall ... .xLarge

    /// `size` held inside ``badgeTypeRange``.
    static func badgeTypeSize(for size: DynamicTypeSize) -> DynamicTypeSize {
        min(max(size, badgeTypeRange.lowerBound), badgeTypeRange.upperBound)
    }

#if os(iOS)
    /// `category` held inside ``badgeTypeRange``: the same cap as ``badgeTypeSize(for:)``, for the UIKit shell, so it needs no SwiftUI type.
    static func badgeContentSize(_ category: UIContentSizeCategory) -> UIContentSizeCategory {
        guard let size = DynamicTypeSize(category) else { return category }
        return badgeTypeSize(for: size) == size ? category : .extraLarge
    }
#endif

    /// How the button draws for a name.
    enum Presentation: Equatable {
        /// The initials on the button's own filled disc.
        case monogram(String)
        /// The person symbol on the bar's standard glass circle, until the name is known.
        case symbol

        /// Resolves the presentation: a name with letters is a monogram, anything else the symbol.
        static func resolve(name: String?) -> Presentation {
            ProfileButton.initials(name).map(Presentation.monogram) ?? .symbol
        }
    }

    /// The disc's size and how far it draws past its layout width.
    struct Metrics: Equatable {
        /// The disc's diameter in points.
        let diameter: CGFloat
        /// Points the disc draws past its layout width on each side (the bar's hidden-glass padding).
        let overhang: CGFloat
        /// A 44 pt material circle shows behind the disc (before iOS 26, where the bar draws no glass).
        let ringed: Bool

        /// The padding a bar puts on each side of an item whose shared glass is hidden.
        static let hiddenGlassPadding: CGFloat = 10

        /// Resolves the metrics for the bar the button sits in: with Liquid Glass a 44 pt disc that overhangs the padding,
        /// before iOS 26 the 32 pt disc inside Quick Links' 44 pt material circle.
        static func resolve(liquidGlassBar: Bool) -> Metrics {
            liquidGlassBar
                ? Metrics(diameter: HassTokens.minTarget, overhang: hiddenGlassPadding, ringed: false)
                : Metrics(diameter: 32, overhang: 0, ringed: true)
        }

        /// The metrics for the running system.
        static var current: Metrics {
            if #available(iOS 26.0, macOS 26.0, *) { return resolve(liquidGlassBar: true) }
            return resolve(liquidGlassBar: false)
        }
    }
}
