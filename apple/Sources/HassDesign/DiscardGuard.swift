import Foundation

// MARK: - Copy

/// The words of the discard confirmation, in one place so the alerts work can fold them into `AlertCopy`
/// (owner, 2026-10-24, `sheet-discard-guard`: title "Discard changes?", destructive "Discard Changes", cancel
/// "Keep Editing"). Saving stays the confirming action of the sheet and is never offered here.
public enum DiscardChangesCopy {
    /// The dialog title.
    public static let title = "Discard changes?"
    /// The destructive action: drop the draft and leave.
    public static let discard = "Discard Changes"
    /// The cancel action: stay on the form.
    public static let keepEditing = "Keep Editing"
}

// MARK: - Logic

/// When leaving a form asks first (HIG: Sheets, "if changes are unsaved when swiping begins, confirm with an action
/// sheet"; Modality). Only a form that holds user-generated content is guarded; a selection-only sheet (filters, sorts,
/// a two-date picker) closes at once because one tap redoes it.
public enum DiscardGuard {
    /// - Parameters:
    ///   - hasChanges: The draft differs from what it started as.
    ///   - isBusy: A save is in flight. The dismissal is blocked outright then, so there is nothing to ask.
    /// - Returns: Whether Cancel, Back or Close must show the confirmation instead of leaving.
    public static func needsConfirmation(hasChanges: Bool, isBusy: Bool = false) -> Bool {
        hasChanges && !isBusy
    }

    /// Whether the system swipe-down is blocked: while a save runs, or while the draft has changes (the confirmation
    /// is then reached through Cancel, Back or Close).
    public static func blocksInteractiveDismissal(hasChanges: Bool, isBusy: Bool = false) -> Bool {
        hasChanges || isBusy
    }
}
