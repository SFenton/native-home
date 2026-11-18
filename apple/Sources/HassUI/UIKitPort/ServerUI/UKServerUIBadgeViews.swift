#if os(iOS)
import Accessibility
import HassCore
import HassDesign
import HassTelemetry
import UIKit

// MARK: - Badges

/// A count or short text on the top trailing corner of a tile or chip (`sh.badges@1`).
///
/// HIG, Badging: a badge shows a short count or word in a capsule on the corner of the thing it describes. A value of 0 or an empty
/// text draws nothing. The badge keeps what it showed while its value is loading, so a reconnect never blanks it. VoiceOver reads it
/// as its own element labelled "Badge, 3"; with no text it is not an element.
@MainActor
enum UKServerUIBadgeViews {
    /// The tag of the badge view a node carries, so one is made once.
    private static let tag = 0x5348_4247

    /// Draws `badge` on `view`: shows the capsule with `text`, or hides it for none.
    /// - Parameters:
    ///   - text: The text, or `nil` for no badge.
    ///   - view: The node's view.
    static func show(_ text: String?, on view: UIView) {
        let badge = (view.viewWithTag(tag) as? UKSegmentBadge) ?? {
            let made = UKSegmentBadge()
            made.tag = tag
            made.translatesAutoresizingMaskIntoConstraints = false
            made.isUserInteractionEnabled = false
            view.addSubview(made)
            NSLayoutConstraint.activate([
                made.topAnchor.constraint(equalTo: view.topAnchor, constant: HassTokens.Spacing.xs),
                made.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -HassTokens.Spacing.xs),
            ])
            return made
        }()
        badge.update(text)
        view.bringSubviewToFront(badge)
        badge.isAccessibilityElement = text != nil
        badge.accessibilityLabel = text.map { "Badge, \($0)" }
    }

    /// Watches a node's badge for as long as its observation bag lives, drawing it on the node's view.
    /// - Parameters:
    ///   - component: The node, whose `badgeValue` is the badge.
    ///   - entry: The node's keyed view and its bag.
    ///   - renderer: The renderer whose reader the value is read through, so the observation tracks exactly the entities it names.
    static func bind(_ component: ServerUICompositionDocument.Component, entry: UKServerUINode, renderer: UKServerUIRenderer) {
        guard let value = component.node.badgeValue else { return }
        var last: String?
        entry.bag.observe { [weak view = entry.view, weak renderer] in
            guard let view, let renderer else { return }
            switch ServerUILayoutRules.badge(value, in: renderer.reader()) {
            case .loading: return
            case .text(let text):
                guard text != last else { return LogicCost.skippedEqual() }
                last = text
                show(text, on: view)
            }
        }
    }
}
#endif
