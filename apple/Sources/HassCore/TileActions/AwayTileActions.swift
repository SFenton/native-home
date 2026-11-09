import Foundation

/// The Vacation Mode card and the Solo Trip toggle as action tiles (rollout lane M, audit items 27 and 28; pattern:
/// `.agents/patterns/action-tiles.md`). Pure rules: the controllers (``VacationModeController``, ``SoloTripController``) own the
/// effect, the optimistic value and the gates, so a spec built here has no ``TileActionSpec/call``; the body and the disc both run
/// the feature's own tap.
///
/// Both tiles are toggle-styled `power` discs (owner, 2026-10-27, answer D). Turning one **on** opens a sheet (the vacation dates, the
/// trip's departure and return), which is the gate; turning one **off** is asked first by the tile's confirmation, which the view
/// attaches in the app's words (`AlertCopy`), so a disc tap and a body tap take the same path.
public enum AwayTileActions {
    /// The action's id in every state (the power toggle's).
    public static let actionId = PowerToggleActions.actionId

    /// The tile's class: it acts, it opens nothing.
    public static var classification: TileClassification {
        .classify(hasDestination: false, actions: TileActionKind.power.restingActionCount)
    }

    /// The Vacation Mode card's disc.
    /// - Parameters:
    ///   - isOn: The mode shows enabled.
    ///   - isPending: The confirmation sheet is open: the card shows Pending and a tap withdraws it.
    ///   - isDisabled: The card cannot be tapped (unavailable, busy, or recovering invalid dates): the disc dims in place.
    public static func vacationMode(isOn: Bool, isPending: Bool, isDisabled: Bool) -> [TileActionSpec] {
        [spec(isOn: isOn || isPending, verb: isPending ? "Cancel" : isOn ? "Turn Off" : "Turn On", isDisabled: isDisabled)]
    }

    /// The Solo Trip toggle's disc.
    /// - Parameters:
    ///   - isOn: A trip is scheduled or running.
    ///   - isDisabled: The toggle cannot be tapped (no traveler chosen yet, a command in flight, or a vacation owns the plan).
    public static func soloTrip(isOn: Bool, isDisabled: Bool) -> [TileActionSpec] {
        [spec(isOn: isOn, verb: isOn ? "Turn Off" : "Turn On", isDisabled: isDisabled)]
    }

    private static func spec(isOn: Bool, verb: String, isDisabled: Bool) -> TileActionSpec {
        TileActionSpec(id: actionId, verb: verb, symbol: "power", isOn: isOn, phase: isDisabled ? .unavailable : .ready, feedback: .optimistic)
    }
}
