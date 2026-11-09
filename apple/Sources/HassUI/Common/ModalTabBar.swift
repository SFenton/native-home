import HassCore
import HassDesign
import SwiftUI

/// One section of a ``ModalTabBar`` with its values already resolved.
struct ModalTabSegment<Item: Hashable & Identifiable>: Identifiable {
    let item: Item
    let title: String
    let symbol: String?
    let badge: Int
    var id: Item.ID { item.id }
}

/// Measurements and the form of the glass section bar.
enum ModalTabBarStyle {
    /// Glass visible around the segmented control.
    static let glassInset: CGFloat = 4

    /// A segment's place in the bar, spoken as its value the way the system segmented control does ("2 of 4").
    /// - Parameters:
    ///   - index: Zero-based position.
    ///   - count: Number of segments.
    static func positionValue(index: Int, count: Int) -> String { "\(index + 1) of \(count)" }

    /// How the control draws its sections.
    enum Form: Equatable {
        /// A segmented control of icons (iPhone), each named for VoiceOver.
        case icons
        /// A segmented control of text titles (iPad, unfolded Duo, or no icons supplied).
        case text
        /// A menu naming the selected section (accessibility text sizes, where segments cannot grow).
        case menu
        /// Our own segments of icons with count badges (iPhone, folded Duo).
        case badged
        /// Our own segments of an icon over its title, with count badges (iPad, unfolded Duo).
        case badgedWithTitles
    }

    /// The form for the environment.
    /// - Parameters:
    ///   - hasSymbols: The caller supplied an SF Symbol per section.
    ///   - hasBadges: The caller supplied a count per section, which the system's segmented control cannot draw.
    ///   - compactWidth: Compact horizontal size class (iPhone, folded Duo).
    ///   - accessibilitySize: An accessibility Dynamic Type size.
    static func form(hasSymbols: Bool, hasBadges: Bool = false, compactWidth: Bool, accessibilitySize: Bool) -> Form {
        if accessibilitySize { return .menu }
        if hasBadges { return hasSymbols && compactWidth ? .badged : .badgedWithTitles }
        return hasSymbols && compactWidth ? .icons : .text
    }

    /// A badge as drawn: capped at "9+" like the header's Profile badge; nil for none.
    static func badgeText(_ count: Int) -> String? { ProfileSummary.badgeText(count) }

    /// What VoiceOver says for a section: its title, then the count ("Overdue Chores, 3 items").
    static func accessibilityTitle(_ title: String, badge: Int) -> String {
        guard badge > 0 else { return title }
        return "\(title), \(badge) \(badge == 1 ? "item" : "items")"
    }

    /// Height of a badged segment showing an icon alone, and one with its title under the icon (HIG: 44 pt targets).
    static let iconSegmentHeight: CGFloat = 44
    static let titledSegmentHeight: CGFloat = 56
}
