#if os(iOS)
import UIKit

extension UIAlertController {
    /// Gives this alert's buttons the accessibility identifiers the SwiftUI alert sets on its buttons (`bed.scope.left`,
    /// `discard.confirm`, `account.signOut.confirm` …), so the same journeys find them in the port.
    ///
    /// UIKit has no public identifier on `UIAlertAction`, but each action is drawn by a view whose accessibility label is the
    /// action's title; once the alert is on screen (call this from `present`'s completion, or use ``UIViewController/ukPresent(_:identifiers:)``)
    /// the views are found by title and given the identifier. Titles that match no view are ignored.
    /// - Parameter identifiers: Identifier by action title.
    func ukApplyIdentifiers(_ identifiers: [String: String]) {
        guard !identifiers.isEmpty else { return }
        var stack: [UIView] = [view]
        while let current = stack.popLast() {
            stack.append(contentsOf: current.subviews)
            // A button view exposes its title as its label; an action sheet's rows can draw the title in a plain label inside.
            let label = current.accessibilityLabel ?? (current as? UILabel)?.text
            if let label, let identifier = identifiers[label], current.isAccessibilityElement || current is UILabel {
                if current is UILabel, let host = current.superview, host.isAccessibilityElement { host.accessibilityIdentifier = identifier } else {
                    current.accessibilityIdentifier = identifier
                }
            }
        }
    }
}

extension UIViewController {
    /// Presents an alert and labels its buttons with `identifiers` (title → identifier) once it is on screen.
    func ukPresent(_ alert: UIAlertController, identifiers: [String: String], animated: Bool = true, completion: (() -> Void)? = nil) {
        let presenter = presentedViewController ?? self
        presenter.present(alert, animated: animated) {
            alert.ukApplyIdentifiers(identifiers)
            // The action views are laid out lazily (a collection of cells since iOS 17): label them again once they exist.
            for delay in [0.15, 0.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak alert] in alert?.ukApplyIdentifiers(identifiers) }
            }
            completion?()
        }
    }
}
#endif
