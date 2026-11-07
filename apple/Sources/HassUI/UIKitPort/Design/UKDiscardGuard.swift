#if os(iOS)
import HassDesign
import UIKit

/// Confirm before a form sheet loses its draft (`DiscardGuard`; HIG: Sheets, Modality). Only a form that holds user-generated
/// content is guarded; a selection-only sheet closes at once. The words and the rules are the SwiftUI ones
/// (``DiscardChangesCopy``, ``DiscardGuard``).
@MainActor
enum UKDiscardGuard {
    /// Blocks the swipe-down while there are changes or a save is running (`discardGuard(hasChanges:isBusy:)`): the
    /// confirmation is reached through Cancel, Back or Close. Call it whenever `hasChanges` or `isBusy` changes.
    /// - Parameter controller: The sheet's root controller (or any page inside it).
    static func apply(to controller: UIViewController, hasChanges: Bool, isBusy: Bool = false) {
        let presented = controller.presentationController?.presentedViewController ?? controller.navigationController ?? controller
        presented.isModalInPresentation = DiscardGuard.blocksInteractiveDismissal(hasChanges: hasChanges, isBusy: isBusy)
    }

    /// Leaves through the guard: with changes shows "Discard changes?" (an action sheet, a popover on iPad anchored to
    /// `source`), without them runs `leave` at once.
    /// - Parameters:
    ///   - controller: Presents the confirmation.
    ///   - source: The control that asked to leave, so iPad anchors the popover there.
    ///   - hasChanges: The draft differs from what it started as.
    ///   - isBusy: A save is in flight; the dismissal is blocked outright, so there is nothing to ask.
    ///   - leave: Drops the draft and leaves.
    static func leave(from controller: UIViewController, source: UKPopoverSource, hasChanges: Bool, isBusy: Bool = false, leave: @escaping () -> Void) {
        guard DiscardGuard.needsConfirmation(hasChanges: hasChanges, isBusy: isBusy) else { leave(); return }
        confirm(from: controller, source: source, onDiscard: leave)
    }

    /// The "Discard changes?" confirmation dialog: destructive "Discard Changes" (`discard.confirm`), cancel "Keep Editing"
    /// (`discard.keep`); the identifiers are set once it is on screen (``UIAlertController/ukApplyIdentifiers(_:)``).
    static func confirm(from controller: UIViewController, source: UKPopoverSource, onDiscard: @escaping () -> Void) {
        let dialog = UIAlertController(title: DiscardChangesCopy.title, message: nil, preferredStyle: .actionSheet)
        dialog.addAction(UIAlertAction(title: DiscardChangesCopy.discard, style: .destructive) { _ in onDiscard() })
        dialog.addAction(UIAlertAction(title: DiscardChangesCopy.keepEditing, style: .cancel))
        source.attach(to: dialog.popoverPresentationController, fallback: controller.view)
        controller.ukPresent(dialog, identifiers: [
            DiscardChangesCopy.discard: "discard.confirm", DiscardChangesCopy.keepEditing: "discard.keep",
        ])
    }
}

/// Where an iPad popover (a confirmation dialog) anchors: the bar button or view that raised it.
enum UKPopoverSource {
    case barButton(UIBarButtonItem)
    case view(UIView)
    case none

    @MainActor
    func attach(to popover: UIPopoverPresentationController?, fallback: UIView) {
        guard let popover else { return }
        switch self {
        case let .barButton(item): popover.barButtonItem = item
        case let .view(view): popover.sourceView = view; popover.sourceRect = view.bounds
        case .none:
            popover.sourceView = fallback
            popover.sourceRect = CGRect(x: fallback.bounds.midX, y: fallback.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
    }
}

/// Every alert and confirmation dialog the app raises, from the shared copy (`AlertCopy`; pattern `alerts.md`): an **alert**
/// asks a yes or no about a state change, a **confirmation dialog** (an action sheet, a popover on iPad) asks before deleting a
/// thing. Every one has a Cancel; only a loss of data is destructive; a plain confirm is the bold default.
@MainActor
enum UKAlerts {
    /// Presents `spec` as an alert.
    /// - Parameters:
    ///   - onCancel: Runs when the person cancels.
    ///   - confirmID: The confirming button's identifier (`confirmID:` of the SwiftUI alert), when UIKit lets an action carry one.
    ///   - cancelID: The cancelling button's identifier.
    static func alert(_ spec: AlertCopy.Spec, from controller: UIViewController, confirmID: String? = nil, cancelID: String? = nil,
                      onCancel: (() -> Void)? = nil, onConfirm: @escaping () -> Void) {
        present(spec, style: .alert, from: controller, source: .none, confirmID: confirmID, cancelID: cancelID, onCancel: onCancel, onConfirm: onConfirm)
    }

    /// Presents `spec` as a confirmation dialog attached to the control that raised it.
    /// - Parameter confirmIdentifier: The confirming button's identifier, set once the dialog is on screen (``UIAlertController/ukApplyIdentifiers(_:)``).
    static func confirmationDialog(_ spec: AlertCopy.Spec, from controller: UIViewController, source: UKPopoverSource,
                                   confirmIdentifier: String? = nil, onConfirm: @escaping () -> Void) {
        present(spec, style: .actionSheet, from: controller, source: source, confirmID: confirmIdentifier, onConfirm: onConfirm)
    }

    private static func present(_ spec: AlertCopy.Spec, style: UIAlertController.Style, from controller: UIViewController,
                                source: UKPopoverSource, confirmID: String? = nil, cancelID: String? = nil, onCancel: (() -> Void)? = nil,
                                onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: spec.title, message: spec.message, preferredStyle: style)
        let confirm = UIAlertAction(title: spec.confirm.title, style: spec.confirm.role == .destructive ? .destructive : .default) { _ in onConfirm() }
        let cancel = UIAlertAction(title: spec.cancel.title, style: .cancel) { _ in onCancel?() }
        // Cancel first, as the system orders a two-button alert; the confirming button is the bold default unless it is destructive.
        alert.addAction(cancel)
        alert.addAction(confirm)
        if spec.confirm.role != .destructive { alert.preferredAction = confirm }
        if style == .actionSheet { source.attach(to: alert.popoverPresentationController, fallback: controller.view) }
        // UIKit has no public identifier for an alert action: the buttons are labelled once the alert is on screen.
        var identifiers: [String: String] = [:]
        if let confirmID { identifiers[spec.confirm.title] = confirmID }
        if let cancelID { identifiers[spec.cancel.title] = cancelID }
        controller.ukPresent(alert, identifiers: identifiers)
    }
}

// MARK: - Keyboard Done

/// A Done button above the keyboard, for a number pad that has no return key (`keyboardDone(focused:)`; HIG Keyboards: give
/// people a way to finish). Tapping it ends editing, which commits the field.
extension UITextField {
    /// Sets the Done accessory (identifier `keyboard.done`, semibold).
    func ukAddKeyboardDone() {
        let finish = UIAction { [weak self] _ in
            self?.resignFirstResponder()
            self?.window?.endEditing(true)
        }
        let done = UIBarButtonItem(title: "Done", image: nil, primaryAction: finish, menu: nil)
        done.style = .done
        done.setTitleTextAttributes([.font: UIFont.ukFont(.body, weight: .semibold)], for: .normal)
        done.accessibilityIdentifier = "keyboard.done"
        // The iPad keyboard (and its hardware-keyboard bar) shows the shortcut bar, where Done goes; an accessory toolbar there would draw
        // a second Done above it. The iPhone has no shortcut bar, so Done sits in a toolbar above the number pad.
        if UIDevice.current.userInterfaceIdiom == .pad {
            inputAssistantItem.trailingBarButtonGroups = [UIBarButtonItemGroup(barButtonItems: [done], representativeItem: nil)]
        } else {
            let bar = UIToolbar()
            bar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil), done]
            bar.sizeToFit()
            inputAccessoryView = bar
        }
    }

}
#endif
