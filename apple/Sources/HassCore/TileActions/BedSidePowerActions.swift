import Foundation

/// A bed side's power disc on its navigation tile (audit item 4). Turning on is at once; **turning off is confirmed**, with the
/// question the sheet's Turn Off capsule asks today ("Turn off Alex's Bed?", a dialog anchored to the tile).
///
/// The bed controller owns the effect (a script through the hot-flash broker for one side, the Solo Trip command for a whole
/// bed), so the spec carries no ``TileActionSpec/call``: the view runs `BedSideController.setPower(on:)` for the spec's id.
///
/// | state of the side's climate entity | verb | isOn | phase |
/// |---|---|---|---|
/// | anything but `off`, `unavailable`, `unknown` | Turn Off (confirmed) | true | ready |
/// | `off` | Turn On | false | ready |
/// | missing, `unavailable`, `unknown`, or ``isReadOnly`` (the traveler's side on a Solo Trip) | Turn On | false | unavailable |
public struct BedSidePowerActions: TileActionProviding {
    /// The action's id in every state.
    public static let actionId = "power"

    /// The side's climate entity (``BedSideConfig/climateEntityId``).
    public var entityId: String
    /// The bed's title ("Alex's Bed"), for the confirmation.
    public var title: String
    /// The traveler's side during a Solo Trip: the disc dims in place.
    public var isReadOnly: Bool

    /// Creates the provider.
    public init(entityId: String, title: String, isReadOnly: Bool = false) {
        self.entityId = entityId
        self.title = title
        self.isReadOnly = isReadOnly
    }

    /// The provider for a configured side.
    public init(_ config: BedSideConfig, isReadOnly: Bool = false) {
        self.init(entityId: config.climateEntityId, title: config.title, isReadOnly: isReadOnly)
    }

    /// The question asked before a side turns off.
    public var turnOffConfirmation: TileActionSpec.Confirmation {
        TileActionSpec.Confirmation(title: "Turn off \(title)?", confirmVerb: "Turn Off", isDestructive: true, style: .dialog)
    }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let value = state?.state
        let unavailable = EntityState.isUnavailable(value) || isReadOnly
        let on = !EntityState.isUnavailable(value) && value != "off"
        return [TileActionSpec(
            id: Self.actionId, verb: on ? "Turn Off" : "Turn On", symbol: "power", isOn: on,
            phase: unavailable ? .unavailable : .ready, feedback: .optimistic, call: nil,
            confirmation: on ? turnOffConfirmation : nil
        )]
    }

    public var stateTextCandidates: [String] { ["Off", "Away · Read Only", "Unavailable", "Didn't Respond"] }
}
