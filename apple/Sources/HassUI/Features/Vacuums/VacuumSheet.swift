import HassCore

/// What the vacuum sheet's tab column shows: a tab in a runtime mode. The sheet fades the column between keys
/// (`UKSmoothContentSwapView`), and a change of runtime mode (a clean starting or ending) also animates the layout.
@MainActor
enum VacuumSheetContent {
    /// What the tab column draws: a tab in a runtime mode.
    struct Key: Equatable {
        var tab: VacuumTab
        var mode: VacuumRuntimeMode
    }

    /// The requested tab in the live mode, or Controls when that mode hides it (web `vacuumModalTabsForMode`).
    static func key(requested: VacuumTab, controller: VacuumController) -> Key {
        let mode = controller.runtimeMode
        return Key(tab: controller.tabs(in: mode).contains(requested) ? requested : .controls, mode: mode)
    }
}
