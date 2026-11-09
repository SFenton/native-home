import HassCore
import HassDesign

/// What a media remote tile shows and runs beyond Power, shared by the Media page and the room pages so the two cannot disagree
/// (pattern: `.agents/patterns/action-tiles.md`). Pure: the feature views feed it the shown states.
enum RemoteTileSupport {
    /// `MediaPlayerEntityFeature.VOLUME_SET`.
    static let volumeSetFeature = 4

    /// Whether `specs` are the transport of a playing, paused or buffering remote (not the Power disc of an idle one).
    static func showsTransport(_ specs: [TileActionSpec]) -> Bool {
        specs.contains { $0.id != PowerToggleActions.actionId }
    }

    /// Whether the volume slider shows under the transport: the remote is in a transport state, its volume entity reports a state,
    /// the speaker is on (or the remote shows volume while off, as the Yamaha receiver and the Beam do), and the entity supports
    /// setting a level (an absent `supported_features` allows it, as the media remote sheet does).
    /// - Parameters:
    ///   - config: The remote.
    ///   - specs: The tile's specs for its shown state.
    ///   - volume: The volume entity's live state (the speaker, which may not be the remote's own player).
    static func showsVolume(config: MediaRemoteConfig, specs: [TileActionSpec], volume: EntityState?) -> Bool {
        guard showsTransport(specs), let volume else { return false }
        if !config.showVolumeWhenOff, MediaRemoteState.isOff(volume.state) { return false }
        return supportsVolumeSet(volume)
    }

    /// Whether the entity can set a level: its `supported_features` has the bit, or does not say.
    static func supportsVolumeSet(_ state: EntityState) -> Bool {
        guard let features = state.attributes["supported_features"]?.number else { return true }
        return Int(features) & volumeSetFeature != 0
    }

    /// The speaker's level in percent from its `volume_level` (0 when absent).
    static func volumePercent(_ state: EntityState?) -> Int {
        let level = state?.attributes["volume_level"]?.number ?? 0
        return min(100, max(0, Int((level * 100).rounded())))
    }
}
