import HassCore
import HassDesign

// MARK: - Mode tile

/// The Vacation Mode card's disc and gates, shared with the UIKit Vacation page (`UKVacation`): *text, disc* with the toggle-styled
/// `power` disc (``AwayTileActions``). It keeps its gates: turning it on opens the dates sheet (or shows the unfinished-checklist error),
/// and turning it off asks first with ``AlertCopy/turnOffVacation`` as the tile's confirmation. ``VacationModeController`` stays the engine.
@MainActor
enum VacationModeTile {
    /// The tile's accessibility identifier; the question's buttons are `<id>.confirm` and `<id>.cancel`.
    static let identifier = "vacation.modeCard"

    /// The card's disc for what the controller shows, asking before it turns an engaged vacation off.
    static func specs(for controller: VacationModeController) -> [TileActionSpec] {
        let specs = AwayTileActions.vacationMode(isOn: controller.cardEnabled, isPending: controller.isConfirming, isDisabled: controller.cardDisabled)
        guard controller.cardEnabled, !controller.isConfirming else { return specs }
        return specs.map { $0.with(confirmation: TileActionSpec.Confirmation(AlertCopy.turnOffVacation)) }
    }

    /// The tap, after any question: off runs the turn-off (the tile already asked), otherwise the controller's own card tap.
    static func run(_ controller: VacationModeController) {
        guard !controller.cardDisabled else { return }
        if controller.cardEnabled { controller.confirmDisable() } else { controller.tapCard() }
    }
}

// MARK: - Solo Trip toggle

/// The Solo Trip toggle's disc: turning a trip on opens the editor sheet, turning it off asks first (``AlertCopy/endSoloTrip``).
@MainActor
enum SoloTripToggleTile {
    /// The toggle's disc for what the controller shows, asking before it ends a trip.
    static func specs(for controller: SoloTripController) -> [TileActionSpec] {
        let specs = AwayTileActions.soloTrip(isOn: controller.toggleChecked, isDisabled: controller.toggleDisabled)
        guard controller.toggleChecked else { return specs }
        return specs.map { $0.with(confirmation: TileActionSpec.Confirmation(AlertCopy.endSoloTrip)) }
    }
}

// MARK: - Traveler tile

/// A resident tile's selection face: the chosen traveler fills in the blue Vents family with a check disc.
@MainActor
enum TravelerTileView {
    /// A selection fills in a family colour; Solo Trip's own blue is not one, so the travelers borrow the blue Vents family.
    static let family = ColorFamily.vents

    /// The tile's selection disc: chosen unless muted (a vacation owns the plan), dimmed in place while locked.
    static func spec(for tile: SoloTripController.TravelerTile) -> TileActionSpec {
        SelectionActions.single(isSelected: tile.isSelected && !tile.isMuted, isEnabled: !tile.isDisabled)
    }
}
