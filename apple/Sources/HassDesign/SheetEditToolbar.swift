import SwiftUI

// MARK: - Create and edit sheets


/// When a create or edit sheet's confirm check can be pressed.
///
/// The check is always shown and is **disabled until there is something to confirm** (owner, 2026-10-16: "should the
/// confirm checkmark only appear if things are changed, as opposed to a gray checkmark visible then blue on change?";
/// answer: visible, disabled until a change, as in Calendar and Reminders; HIG Toolbars: keep controls in a stable
/// place, and disable rather than hide one that does not apply now). A new item needs a valid draft; an edit also
/// needs a change, so confirming never re-saves what is already saved.
public enum SheetEditState {
    /// - Parameters:
    ///   - isValid: The draft can be saved (a name is present, the item has loaded).
    ///   - hasChanges: The draft differs from what is saved; always true for a new item, whose draft is the change.
    ///   - isBusy: A save or a load is in flight.
    /// - Returns: Whether the confirm check is enabled.
    public static func canConfirm(isValid: Bool, hasChanges: Bool, isBusy: Bool = false) -> Bool {
        isValid && hasChanges && !isBusy
    }
}
