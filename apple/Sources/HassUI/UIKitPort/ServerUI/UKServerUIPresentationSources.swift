#if os(iOS)
import HassCore

// MARK: - Observed presentation projections

/// Values only: the domain provider owns state, permissions and command lifetimes.
struct UKServerUISectionState {
    var header: String?
    var footer: String?
    var detail: String?
    var visible = true
}

/// The allowed set is immutable for one authenticated scope. Hidden tabs never mount their providers.
@MainActor
struct UKServerUITabScope {
    let allowedTabIDs: [String]
    let initialTabID: String
    var title: () -> String? = { nil }
    var badges: () -> [String: Int] = { [:] }
    var automaticSelection: (() -> String)? = nil
}

/// Bridges an existing domain exit guard without teaching the shell about that domain's draft.
@MainActor
struct UKServerUIExitGate {
    let blocksExit: (UKServerUIPage) -> Bool
    let request: (UKServerUIPage, @escaping () -> Void) -> Void
    var canDiscard: (UKServerUIPage) -> Bool = { _ in false }
}
#endif
