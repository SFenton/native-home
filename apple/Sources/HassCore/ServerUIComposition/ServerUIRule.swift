import Foundation

// MARK: - Which case of a rule

/// Which case of a rule is used.
public enum ServerUIRulePick: Equatable, Sendable {
    /// The index of the first case that holds.
    case matched(Int)
    /// No case holds.
    case otherwise
    /// A case that cannot be answered yet stands before any that holds.
    case stalled
}

/// The tri-state rule for every rule-shaped value: a `choose` operand, a `conditional` look, tone or action.
///
/// This is the ONE place that decides what "a case that can't tell" means. Today an unknown case stops the rule: nothing later may
/// stand in for it (unknown is loading, and the slot keeps its value). Each caller then decides what a stalled rule shows: a
/// `choose` is `loading`, so the slot keeps what it showed; a look or tone falls back to `otherwise`; an action does nothing.
/// To make a rule skip a case that can't tell instead, change the `.unknown` line below and nothing else.
public enum ServerUIRule {
    /// The first case that holds, `otherwise` when none does, or `stalled` when an undecided case stands before any that holds.
    public static func pick(count: Int, answer: (Int) -> ServerUITri) -> ServerUIRulePick {
        for index in 0..<count {
            switch answer(index) {
            case .yes: return .matched(index)
            case .unknown: return .stalled
            case .no: continue
            }
        }
        return .otherwise
    }
}
