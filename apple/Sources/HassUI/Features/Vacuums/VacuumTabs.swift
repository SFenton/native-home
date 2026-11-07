import HassCore
import HassDesign
import SwiftUI

// MARK: - Section bar

/// The vacuum sheet's sections in the bottom glass section bar (``ModalTabBar``; direction G, Sheets: "symbols only at
/// five segments (the vacuum)"). Fewer sections (a run in progress shows Controls, Auto-Clean and Info) read as text.
enum VacuumTabSymbols {
    /// The symbol for a section (mockup n6-vacuum-sheet: robot, floor plan, auto-clean clock, dock, info).
    static func symbol(for tab: VacuumTab) -> String {
        switch tab {
        case .controls: VacuumStyle.symbol(tab.icon)
        case .zones: VacuumStyle.symbol(tab.icon)
        case .autoClean: "clock.arrow.circlepath"
        case .more: "ev.charger"
        case .info: VacuumStyle.symbol(tab.icon)
        }
    }
}
