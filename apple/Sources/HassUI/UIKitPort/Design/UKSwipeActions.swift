#if os(iOS)
import UIKit

/// One swipe action on a list row (SwiftUI `.swipeActions { Button … }`). The repo's SwiftUI lists use the system `List`
/// swipe actions (Chores todo rows, Inventory rows), so the UIKit lists use the system's too: a list layout's
/// `UISwipeActionsConfiguration` has the same geometry, full-swipe behaviour and haptics, drawn by UIKit. (HassDesign has no
/// custom swipe implementation to port.)
///
/// ```swift
/// list.trailingSwipe = { item in
///     UKSwipeAction.configuration([UKSwipeAction("Delete", systemImage: "trash", role: .destructive) { done in delete(item); done(true) }])
/// }
/// ```
@MainActor
struct UKSwipeAction {
    var title: String
    var systemImage: String?
    var tint: UIColor?
    /// The button's accessibility identifier (`swipeActions { Button … .accessibilityIdentifier }`), where the system supports one.
    var identifier: String?
    var isDestructive: Bool
    /// Runs when the action is chosen; call `done(true)` when it succeeded (the row closes), `done(false)` to leave it open.
    var handler: (_ done: @escaping (Bool) -> Void) -> Void

    init(_ title: String, systemImage: String? = nil, tint: UIColor? = nil, identifier: String? = nil, role: UIContextualAction.Style = .normal,
         handler: @escaping (_ done: @escaping (Bool) -> Void) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.identifier = identifier
        self.isDestructive = role == .destructive
        self.handler = handler
    }

    /// The system action for this one.
    func contextualAction() -> UIContextualAction {
        let handler = self.handler
        let action = UIContextualAction(style: isDestructive ? .destructive : .normal, title: title) { _, _, completion in
            handler { completion($0) }
        }
        action.image = systemImage.flatMap { UIImage(systemName: $0) }
        if let tint { action.backgroundColor = tint }
        if let identifier, action.responds(to: NSSelectorFromString("setAccessibilityIdentifier:")) { action.setValue(identifier, forKey: "accessibilityIdentifier") }
        return action
    }

    /// A swipe configuration of `actions`, in the order SwiftUI lists its buttons.
    /// - Parameter allowsFullSwipe: A long swipe runs the first action (SwiftUI's `allowsFullSwipe: true`).
    static func configuration(_ actions: [UKSwipeAction], allowsFullSwipe: Bool = true) -> UISwipeActionsConfiguration? {
        guard !actions.isEmpty else { return nil }
        let configuration = UISwipeActionsConfiguration(actions: actions.map { $0.contextualAction() })
        configuration.performsFirstActionWithFullSwipe = allowsFullSwipe
        return configuration
    }
}
#endif
