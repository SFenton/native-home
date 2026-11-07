import Foundation

/// A momentary command: one service or script call behind one disc (Admin's power recovery). Press highlight and the tap
/// haptic, nothing else (``TileActionSpec/Feedback/momentary``); a failed call shows the tile's "Didn't Respond" face, which the
/// view drives from the call's failure key, not from this provider.
///
/// | state of ``availabilityEntityId`` | phase |
/// |---|---|
/// | no entity configured | ready |
/// | any live state | ready |
/// | missing, `unavailable`, `unknown` | unavailable (dims in place) |
public struct CommandActions: TileActionProviding {
    /// The action's id when none is given.
    public static let defaultActionId = "command"

    /// The action's id (the identifier suffix `<tile-id>.action.<id>`).
    public var actionId: String
    /// What the command does: "Run".
    public var verb: String
    /// The disc's glyph, the *action* (`bolt.fill`).
    public var symbol: String
    /// The call.
    public var call: ServiceCall
    /// The whole VoiceOver label ("Run power recovery"), or nil for "verb title".
    public var label: String?
    /// Asked first, or nil.
    public var confirmation: TileActionSpec.Confirmation?
    /// An entity whose absence makes the disc unavailable, or nil when the command always runs.
    public var availabilityEntityId: String?

    /// Creates the provider.
    public init(actionId: String = CommandActions.defaultActionId, verb: String, symbol: String, call: ServiceCall, label: String? = nil,
                confirmation: TileActionSpec.Confirmation? = nil, availabilityEntityId: String? = nil) {
        self.actionId = actionId
        self.verb = verb
        self.symbol = symbol
        self.call = call
        self.label = label
        self.confirmation = confirmation
        self.availabilityEntityId = availabilityEntityId
    }

    /// Admin's "Attempt to turn power back on": `automation.trigger` on the Living Room power recovery automation, a `bolt.fill`
    /// disc labelled "Run power recovery" (the rollout mockup, item 21). It dims and fires nothing while the automation is unavailable
    /// (owner, 2026-11-03: "Yes").
    public static var powerRecovery: CommandActions {
        let automation = HouseholdSettingsConfig.Admin.powerRecoveryAutomation
        return CommandActions(
            actionId: "power_recovery", verb: "Run", symbol: "bolt.fill",
            call: ServiceCall("automation", "trigger", target: automation),
            label: "Run power recovery", availabilityEntityId: automation
        )
    }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let unavailable = availabilityEntityId != nil && EntityState.isUnavailable(state?.state)
        return [TileActionSpec(
            id: actionId, verb: verb, symbol: symbol, phase: unavailable ? .unavailable : .ready, feedback: .momentary, call: call,
            label: label, confirmation: confirmation
        )]
    }

    public var stateTextCandidates: [String] { ["Didn't Respond", "Unavailable"] }
}
