import Foundation

/// A ``StateStyle`` as a tile's action provider: the one disc a door, a lock or the alarm offers, decided from entity state alone.
///
/// It replaces the fixed shapes `CoverActions`, `LockActions` and `AlarmModeActions`, which the parity tests (`StateStyleParityTests`)
/// proved the styles equal to before they were deleted. The spec's id is the style's ``StateStyle/actionId`` in every state, so the disc is one
/// view whose glyph and label change and the symbol transition survives. Feedback is ``TileActionSpec/Feedback/tracked``: the moving state
/// comes from the entity (or the controller), so the spec carries no intents. A state the style gives no action offers the unavailable disc.
public struct StateStyleActions: TileActionProviding {
    /// The style that decides the disc.
    public var style: StateStyle
    /// The entity the actions call.
    public var entityId: String
    /// A call was just sent and the state has not moved: the disc is in flight whatever the state says.
    public var requestInFlight: Bool

    /// Creates the provider.
    public init(_ style: StateStyle, entityId: String, requestInFlight: Bool = false) {
        self.style = style
        self.entityId = entityId
        self.requestInFlight = requestInFlight
    }

    /// The tile actions available in the entity state.
    public func actions(for state: EntityState?) -> [TileActionSpec] {
        if let spec = style.spec(for: state, entityId: entityId, requestInFlight: requestInFlight) { return [spec] }
        let unknown = style.resolve(nil, entityId: entityId)
        return [TileActionSpec(id: style.actionId, verb: unknown.action?.verb ?? "Open", symbol: unknown.glyph, phase: .unavailable, feedback: .tracked)]
    }

    public var stateTextCandidates: [String] {
        let words = style.rules.compactMap(\.words) + style.rules.flatMap(\.states).filter { $0 != "unavailable" && $0 != "unknown" }.map { StateStyle.title($0) }
        let request = style.request.map { Array($0.pendingWords.values) + [$0.errorWords] } ?? []
        return words + request + ["Unavailable"]
    }

    /// The Stop feature bit of a cover (`CoverEntityFeature.STOP`).
    public static let stopFeature = StateStyle.coverStopFeature

    /// Whether the cover reports Stop support.
    public static func supportsStop(_ state: EntityState?) -> Bool {
        guard let features = state?.attributes["supported_features"]?.number else { return false }
        return Int(features) & stopFeature != 0
    }
}
