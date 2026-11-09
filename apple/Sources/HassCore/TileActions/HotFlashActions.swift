import Foundation

/// Hot Flash Mode's one disc (audit item 13): a snowflake that starts the mode, which becomes a stop disc while it runs. The
/// body and the disc both do what the disc shows (the convention), so a tap on the active tile cancels.
///
/// | state of the side's hot-flash-active boolean | symbol | verb (whole label) | call |
/// |---|---|---|---|
/// | `off` | `snowflake` | "Start Hot Flash Mode" | press the side's hot flash button |
/// | `on` | `stop.fill` | "Cancel Hot Flash Mode" | press the cancel button |
/// | missing, `unavailable`, `unknown`, or ``isReadOnly`` | `snowflake` | Start | unavailable (dims in place) |
///
/// The disc is not toggle-styled (``TileActionSpec/isOn`` nil): the tile's own fill says the mode runs. Feedback is
/// ``TileActionSpec/Feedback/optimistic`` with the active boolean as the intent. `BedSideController.startHotFlash()` also commits
/// the side's power and owns the overlay the sheet reads, so the sheet runs the controller for the spec's id.
public struct HotFlashActions: TileActionProviding {
    /// The action's id in every state.
    public static let actionId = "hot_flash"

    /// The side hot-flash-active boolean.
    public var activeEntityId: String
    /// The side hot-flash button.
    public var startButtonEntityId: String
    /// The side cancel-hot-flash button.
    public var cancelButtonEntityId: String
    /// The traveler's side on a Solo Trip: read-only.
    public var isReadOnly: Bool

    /// Creates the provider.
    public init(activeEntityId: String, startButtonEntityId: String, cancelButtonEntityId: String, isReadOnly: Bool = false) {
        self.activeEntityId = activeEntityId
        self.startButtonEntityId = startButtonEntityId
        self.cancelButtonEntityId = cancelButtonEntityId
        self.isReadOnly = isReadOnly
    }

    /// The provider for a configured side.
    public init(_ config: BedSideConfig, isReadOnly: Bool = false) {
        self.init(activeEntityId: config.hotFlashActiveEntityId, startButtonEntityId: config.hotFlashButtonEntityId,
                  cancelButtonEntityId: config.hotFlashCancelButtonEntityId, isReadOnly: isReadOnly)
    }

    /// Whether `state` reads active.
    public func isActive(_ state: String?) -> Bool { state == "on" }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let unavailable = EntityState.isUnavailable(state?.state) || isReadOnly
        let active = !unavailable && isActive(state?.state)
        return [TileActionSpec(
            id: Self.actionId, verb: active ? "Cancel" : "Start", symbol: active ? "stop.fill" : "snowflake",
            phase: unavailable ? .unavailable : .ready, feedback: .optimistic,
            call: ServiceCall("input_button", "press", target: active ? cancelButtonEntityId : startButtonEntityId),
            optimistic: [OptimisticIntent(activeEntityId, value: active ? "off" : "on")],
            label: active ? "Cancel Hot Flash Mode" : "Start Hot Flash Mode"
        )]
    }

    public var stateTextCandidates: [String] { ["Inactive", "Active", "Hot Flash Mode • Cooling", "59:59 Remaining", "Unavailable"] }
}
