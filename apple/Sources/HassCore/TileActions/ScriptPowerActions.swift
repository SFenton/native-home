import Foundation

/// A device powered through scripts (Nintendo Switch, Cinema Streamer): a toggle-styled `power` disc with **tracked** feedback
/// (owner, 2026-10-27, items 6 and 8).
///
/// - **Off:** the disc reads "Turn On" and runs the tile's own script (its ``onScript``).
/// - **On:** the disc reads "Turn Off" and runs ``offScript`` (the remote's Power key, which
///   takes its turn-off branch whenever the tile shows On).
/// - **In flight:** from the tap until the script stops running and the device's active helper reports the new state. The
///   disc is then the arc spinner (``TileActionSpec/Phase/inFlight``), keeps its label, and animates out to the final glyph and
///   fill. A call that fails, or a state that never arrives within ``holdDuration``, shows the tile's "Didn't Respond" face.
///
/// **How the hold is kept** (the lock's mechanism, reused): the provider is pure and takes the *live* active state, the *pending*
/// target and the script's state. The view runs the call through `OptimisticActions` with ``TileActionSpec/tracking`` (an intent
/// on the active boolean with the target value, rule `.confirmation`, failing on timeout), so `pending` is the overlay's pending
/// value for the boolean and clears itself when the boolean reports it, when the call throws, or after ``holdDuration``. In
/// flight is therefore `pending != live` or the watched script `on`; nothing else is stored.
public struct ScriptPowerActions: TileActionProviding, Codable, Hashable {
    /// The action's id in every state.
    public static let actionId = "power"
    /// The script the remote's Power key runs, which turns the room off when the tile shows On: the first device's turn-off
    /// script in the document (`media.scriptPowerDevices`).
    public static var toggleScript: String { all.first?.offScript ?? "" }
    /// How long the disc waits for the boolean to report the new state before the failed face.
    public static let holdDuration: Duration = .seconds(45)

    /// The `input_boolean` that is on while the device is the active source.
    public var activeEntityId: String
    /// The tile's own script, without the `script.` domain.
    public var onScript: String
    /// The script that turns the room off, without the domain.
    public var offScript: String
    /// The disc's glyph.
    public var symbol: String

    /// Creates the provider.
    public init(activeEntityId: String, onScript: String, offScript: String = ScriptPowerActions.toggleScript, symbol: String = "power") {
        self.activeEntityId = activeEntityId
        self.onScript = onScript
        self.offScript = offScript
        self.symbol = symbol
    }


    /// Every script-powered device, in tile order: the document's `media.scriptPowerDevices`.
    public static var all: [ScriptPowerActions] { HouseConfigSource.active.read { $0.media.scriptPowerDevices }.flatMap { $0 } ?? [] }

    /// The entity id of a script (`script.<name>`).
    public static func scriptEntityId(_ name: String) -> String { "script.\(name)" }

    /// The tile's own script entity.
    public var onScriptEntityId: String { Self.scriptEntityId(onScript) }
    /// The turn-off script entity.
    public var offScriptEntityId: String { Self.scriptEntityId(offScript) }

    /// Whether `state` reads on.
    public func isOn(_ state: String?) -> Bool { state == "on" }

    // MARK: Provider

    /// The resting specs for the live state: ready or unavailable, never in flight.
    public func actions(for state: EntityState?) -> [TileActionSpec] {
        actions(live: state, pending: nil, onScript: nil, offScript: nil)
    }

    /// The specs with the hold applied.
    /// - Parameters:
    ///   - live: The active boolean's live state (not the shown one: the glyph and fill change only when it reports).
    ///   - pending: The overlay's pending value for the boolean (`"on"` or `"off"`), or nil.
    ///   - onScript: The tile's own script entity. The disc stays in flight while it, or `offScript`, is `on`.
    ///   - offScript: The turn-off script entity (shared by the room's Power key).
    public func actions(live: EntityState?, pending: String?, onScript: EntityState?, offScript: EntityState?) -> [TileActionSpec] {
        let unavailable = EntityState.isUnavailable(live?.state)
        let on = isOn(live?.state)
        let waiting = pending.map { $0 != live?.state } ?? false
        let running = onScript?.state == "on" || offScript?.state == "on"
        let phase: TileActionSpec.Phase = unavailable ? .unavailable : (waiting || running ? .inFlight : .ready)
        let call = on ? ServiceCall("script", self.offScript) : ServiceCall("script", self.onScript)
        let target = on ? "off" : "on"
        return [TileActionSpec(
            id: Self.actionId, verb: on ? "Turn Off" : "Turn On", symbol: symbol, isOn: on, phase: phase, feedback: .tracked, call: call,
            tracking: [OptimisticIntent(activeEntityId, target, revertAfter: Self.holdDuration, failsOnTimeout: true)]
        )]
    }

    /// The tile's state line for the live boolean and the disc's phase: "On", "Off", "Turning On…" while the hold waits,
    /// "Unavailable" when the boolean cannot be reached.
    public func stateText(live: EntityState?, phase: TileActionSpec.Phase) -> String {
        if EntityState.isUnavailable(live?.state) { return "Unavailable" }
        let on = isOn(live?.state)
        if phase == .inFlight { return on ? "Turning Off…" : "Turning On…" }
        return on ? "On" : "Off"
    }

    public var stateTextCandidates: [String] { ["On", "Off", "Turning On…", "Turning Off…", "Unavailable", "Didn't Respond"] }
}
