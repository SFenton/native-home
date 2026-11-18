/// Why a list is applying a new snapshot (``ListUpdateTransition`` decides on it). Pattern: `.agents/patterns/list-row-removal.md`.
public enum ListUpdateCause: Equatable, Sendable {
    /// The list was rebuilt around a different question (search, sort, filter, a page or tab switch): it replaces, never animates.
    case reset
    /// The data changed underneath the screen (another device, a server push, a refresh). A removal or insertion that is on screen
    /// animates; a reapply, a reconnect and a cold launch never do.
    case live
    /// The person did it (a confirmed delete, a completed chore, an undo, a failed action coming back). Announced and focused.
    case person
}
