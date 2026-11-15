import Foundation

// MARK: - Retained automatic content selection

/// Keeps an engaged composed panel after its source returns to the initial chooser.
/// A chooser departed by pushing a child remains the chooser for the rest of that visit.
public struct ServerUIAutomaticSelection: Equatable, Sendable {
    /// The content currently shown, or `nil` before the first resolution.
    public private(set) var displayed: String?
    private var lastEngaged: String?
    private var keepsInitial = false
    /// Creates a selection with nothing displayed or engaged.
    public init() {}

    /// Chooses the content to display and remembers the last engaged choice.
    ///
    /// Every input is validated before any state changes, and an engaged choice that `allowed` no longer lists
    /// is forgotten rather than failing every later resolution.
    /// - Throws: ``ServerUIRecordFailure/invalidValue`` when `allowed` is empty, repeats a value, or omits
    ///   `initial` or `proposed`.
    public mutating func resolve(_ proposed: String, initial: String, allowed: [String], retainsEngaged: Bool) throws -> String {
        guard !allowed.isEmpty, Set(allowed).count == allowed.count,
              allowed.contains(initial), allowed.contains(proposed) else { throw ServerUIRecordFailure.invalidValue }
        var engaged = lastEngaged.flatMap { allowed.contains($0) ? $0 : nil }
        if proposed != initial { engaged = proposed }
        let value = retainsEngaged && keepsInitial ? initial : (retainsEngaged && proposed == initial ? engaged ?? initial : proposed)
        guard allowed.contains(value) else { throw ServerUIRecordFailure.invalidValue }
        lastEngaged = engaged
        displayed = value
        return value
    }

    /// Marks the initial chooser as departed by a push, so it stays the chooser for the rest of the visit.
    public mutating func departed(initial: String, retainsEngaged: Bool) {
        if retainsEngaged, displayed == initial { keepsInitial = true }
    }
}
