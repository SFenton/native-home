import HassCore
import HassDesign
import SwiftUI

// MARK: - Controls

/// Cleaning target, cleaning settings, the Clean button and the run's commands (web `VacuumControlsTab`; the decided design
/// is `.agents/design/mockups/proposals/vacuum-sheet-redesign`). While a run is going the setup collapses to Pause and
/// Stop as action tiles, with no state header and no text under them.
struct VacuumControlsTab {
    var controller: VacuumController
    var mapState: VacuumMapState
    /// The runtime mode drawn. While a clean starts or ends the sheet keeps drawing the outgoing mode as it fades out
    /// (web `useVacuumRuntimeContentTransition`).
    var mode: VacuumRuntimeMode
    var onOpenRooms: () -> Void
    var onEditArea: () -> Void

    enum Confirmation: Identifiable {
        case toRooms, toArea
        var id: Self { self }

        /// The alert's copy: one decision, one set of words on every path.
        var spec: AlertCopy.Spec { self == .toRooms ? AlertCopy.switchToRooms : AlertCopy.switchToArea }
    }









}
