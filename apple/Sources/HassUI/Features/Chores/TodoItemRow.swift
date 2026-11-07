import HassCore
import HassDesign
import SwiftUI

/// A checkable task row with its due label and an optional edit button (web `CheckboxRow` in `TodoListPanel`; direction
/// G mockups n5: a check circle the size of the title, a 17 pt title, a 15 pt due line, and a trailing edit glyph). The
/// title starts 16 + 24 + 14 pt in, where the module's hairlines inset, so it keeps its own toggle and edit layout over
/// ``ModuleRow``'s.
///
/// Owner, 2026-10-16: the check circle is the size of the text. It takes the title's font at the symbol's default scale,
/// so it follows Dynamic Type with the title, inside a 24 pt `@ScaledMetric` column. The whole row is the toggle's hit
/// area, 52 pt tall or more.
struct TodoItemRow {
    var item: TodoItem
    var now: Date = .now
    var onToggle: () -> Void
    var onEdit: (() -> Void)?
    /// Puts the task back, while it is checked off and still listed for a few seconds; replaces the edit button.
    var onUndo: (() -> Void)?
    /// Asks to delete the task (a VoiceOver custom action; the swipe and the context menu live on the list row).
    var onDelete: (() -> Void)?
    /// The swipe actions as VoiceOver actions (Complete or Mark Not Done, Edit): a row in a lazy stack has no system swipe
    /// actions to expose them, so it names them here, with the labels the swipe buttons carry.
    var exposedActions: TodoRowActions?

    /// The check column's width, scaled with the title so the title stays on the module's hairline inset.
    @ScaledMetric(relativeTo: .body) private var checkColumn: CGFloat = ModuleRowMetrics.glyphWidth

    /// One VoiceOver custom action on the row.
    struct VoiceOverAction: Equatable {
        /// What the action does (which handler it calls).
        enum Kind: Equatable { case undo, toggle, edit, delete }
        var kind: Kind
        /// The name VoiceOver reads; the swipe buttons carry the same labels.
        var title: String
    }

    /// The row's VoiceOver actions, in the order VoiceOver lists them: Undo while it is offered, then Complete or Mark Not
    /// Done and Edit (only with `exposedActions`, the stack row), then Delete. A pure function so a test can read the list
    /// without a screen reader (``voiceOverActions``).
    static func voiceOverActions(
        hasUndo: Bool, exposed: TodoRowActions?, hasEdit: Bool, hasDelete: Bool
    ) -> [VoiceOverAction] {
        var actions: [VoiceOverAction] = []
        if hasUndo { actions.append(VoiceOverAction(kind: .undo, title: "Undo")) }
        if let exposed {
            if let first = exposed.leading.first { actions.append(VoiceOverAction(kind: .toggle, title: first.title)) }
            if exposed.trailing.contains(.edit), hasEdit {
                actions.append(VoiceOverAction(kind: .edit, title: TodoRowActions.Action.edit.title))
            }
        }
        if hasDelete { actions.append(VoiceOverAction(kind: .delete, title: TodoRowActions.Action.delete.title)) }
        return actions
    }

    /// This row's VoiceOver actions (see ``voiceOverActions(hasUndo:exposed:hasEdit:hasDelete:)``).
    var voiceOverActions: [VoiceOverAction] {
        Self.voiceOverActions(hasUndo: onUndo != nil, exposed: exposedActions, hasEdit: onEdit != nil, hasDelete: onDelete != nil)
    }

    /// Runs the handler a VoiceOver action stands for.
    func perform(_ kind: VoiceOverAction.Kind) {
        switch kind {
        case .undo: onUndo?()
        case .toggle: onToggle()
        case .edit: onEdit?()
        case .delete: onDelete?()
        }
    }

    /// The glyph for an open and a done task.
    static func checkSymbol(done: Bool) -> String { done ? "checkmark.circle.fill" : "circle" }

    /// The edit button's glyph (owner, 2026-10-16: not the info circle).
    static let editSymbol = "square.and.pencil"


    /// "Not done, Due in 3 days" or "Done".
    static func accessibilityValue(completed: Bool, due: String?) -> String {
        if completed { return "Done" }
        return ["Not done", due].compactMap { $0 }.joined(separator: ", ")
    }
}

