import Foundation

/// A media remote tile's actions: Power while the device is off or idle, previous / play-pause / next while it plays
/// or is paused (owner, option B: "Off: Power beside the chevron. Playing: previous / play-pause / next").
///
/// | player state | specs |
/// |---|---|
/// | `playing`, `buffering` | `previous`, `play_pause` (Pause, `pause.fill`, emphasized), `next` |
/// | `paused` | `previous`, `play_pause` (Play, `play.fill`), `next` |
/// | anything else (off, standby, idle, on) | `power` (``PowerToggleActions/remote(_:symbol:)``) |
/// | missing, `unavailable`, `unknown` | `power`, ``TileActionSpec/Phase/unavailable`` |
///
/// Previous and next are ``TileActionSpec/Feedback/momentary`` (`media_player.media_previous_track` /
/// `media_next_track`). Play/pause is ``TileActionSpec/Feedback/optimistic``, runs the remote's own Pause / Play
/// command (`remote.send_command MEDIA_PAUSE` on a SHIELD) and shows the opposite state at once. The symbol is the
/// *action*: pause while playing, play while paused. `supported_features` gates each button: previous (16),
/// next (32), pause (1) and play (16384); an absent attribute offers everything.
public struct MediaTransportActions: TileActionProviding {
    /// The remote.
    public var config: MediaRemoteConfig

    /// Creates the provider for `config`.
    public init(config: MediaRemoteConfig) {
        self.config = config
    }

    /// `MediaPlayerEntityFeature` bits.
    public enum Feature {
        public static let pause = 1
        public static let previousTrack = 16
        public static let nextTrack = 32
        public static let play = 16384
    }

    /// States that show the transport.
    public static let transportStates: Set<String> = ["playing", "paused", "buffering"]

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let value = state?.state
        guard let value, Self.transportStates.contains(value) else {
            return PowerToggleActions.remote(config).actions(for: state)
        }
        let features = state?.attributes["supported_features"]?.number.map { Int($0) }
        func supports(_ bit: Int) -> Bool { features.map { $0 & bit != 0 } ?? true }
        let player = config.mediaEntityId
        var specs: [TileActionSpec] = []
        if supports(Feature.previousTrack) {
            specs.append(TileActionSpec(id: "previous", verb: "Previous", symbol: "backward.fill", feedback: .momentary,
                                        call: ServiceCall("media_player", "media_previous_track", target: player)))
        }
        let playing = value != "paused"
        if supports(playing ? Feature.pause : Feature.play) {
            let button = playing ? config.pause : config.play
            var call: ServiceCall?
            var intents: [OptimisticIntent] = []
            if case let .service(resolved, _) = button.action.resolve(entityId: config.controlEntityId, displayedState: { _ in value }) {
                call = resolved
            }
            intents = [OptimisticIntent(player, value: playing ? "paused" : "playing")]
            // Emphasized in every transport state, so its ink never flips on a pause (orchestrator default, 2026-10-26).
            specs.append(TileActionSpec(id: "play_pause", verb: playing ? "Pause" : "Play", symbol: playing ? "pause.fill" : "play.fill",
                                        feedback: .optimistic, call: call, optimistic: intents, isEmphasized: true))
        }
        if supports(Feature.nextTrack) {
            specs.append(TileActionSpec(id: "next", verb: "Next", symbol: "forward.fill", feedback: .momentary,
                                        call: ServiceCall("media_player", "media_next_track", target: player)))
        }
        return specs
    }

    public var stateTextCandidates: [String] { ["Playing", "Paused", "Buffering", "Idle", "Standby", "On", "Off", "Unavailable"] }
}
