import HassCore
import HassDesign
import SwiftUI

// MARK: - Clean target

/// Rooms or Area, the Controls section's two cleaning targets (web `VacuumCleanTarget`), and what picking one does through
/// its "Use Rooms" and "Use Area" tiles. Pure, so the confirmation rules are unit-tested apart from the view.
enum VacuumCleanTarget: Hashable {
    case rooms, area

    /// What a pick leads to.
    enum Outcome: Equatable {
        /// Open the Rooms section.
        case openRooms
        /// Open the area editor.
        case openAreaEditor
        /// Ask before discarding the drawn area.
        case confirmRooms
        /// Ask before clearing the selected rooms.
        case confirmArea
        /// Nothing (the map is not ready for drawing).
        case none
    }

    /// The target the sheet is on.
    static func current(areaDrawn: Bool) -> Self { areaDrawn ? .area : .rooms }

    /// The outcome of picking `target` (the web's target buttons).
    static func outcome(picking target: Self, areaDrawn: Bool, roomsSelected: Bool, mapReady: Bool) -> Outcome {
        switch target {
        case .rooms: return areaDrawn ? .confirmRooms : .openRooms
        case .area:
            guard mapReady else { return .none }
            return roomsSelected && !areaDrawn ? .confirmArea : .openAreaEditor
        }
    }
}
