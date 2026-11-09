import HassCore
import HassDesign

/// What the room page and the Media page share when a tile adopts the rollout providers (pattern:
/// `.agents/patterns/action-tiles.md`, Rollout foundations): the script-powered devices and the Music Room sources. A view feeds
/// the pure providers the live state and runs the spec; none of the domain rules live here.
@MainActor
enum RolloutTileSupport {
    // MARK: Switch and SHIELD

    /// The provider for a card or device whose active boolean is `entityId` (Nintendo Switch, Cinema Streamer).
    static func scriptProvider(forEntity entityId: String) -> ScriptPowerActions? {
        ScriptPowerActions.all.first { $0.activeEntityId == entityId }
    }

    /// The disc's specs with the hold applied: the boolean's live state, the overlay's pending target and both scripts' states.
    static func scriptSpecs(_ provider: ScriptPowerActions, store: EntityStore, actions: OptimisticActions?) -> [TileActionSpec] {
        provider.actions(live: store.entity(provider.activeEntityId).state, pending: actions?.overlay.pending[provider.activeEntityId],
                         onScript: store.entity(provider.onScriptEntityId).state, offScript: store.entity(provider.offScriptEntityId).state)
    }

    /// The optimistic path a tapped device runs through: its pending target clears when the boolean reports it, and a call that
    /// throws or a state that never arrives shows "Didn't Respond" (``OptimisticActions/isFailed(_:)``).
    static func scriptActions(_ provider: ScriptPowerActions, store: EntityStore, caller: any HassServiceCalling) -> OptimisticActions {
        OptimisticActions(store: store, rules: [provider.activeEntityId: .confirmation], caller: caller)
    }

    // MARK: Music Room sources

    /// The provider for a Music Room source tile by its title.
    static func sourceProvider(title: String) -> SourceSelectActions? {
        SourceSelectActions.allMusicRoom.first { $0.title == title }
    }

    /// A source tile's disc and state line for the source entity's shown state.
    static func sourceFace(_ provider: SourceSelectActions, state: EntityState?) -> (specs: [TileActionSpec], subtitle: String?) {
        (provider.actions(for: state), provider.stateText(for: state?.state))
    }
}
