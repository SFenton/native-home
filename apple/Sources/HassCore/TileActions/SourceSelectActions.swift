import Foundation
import HassTelemetry

/// A Music Room source: one of several, chosen (owner, 2026-10-27, items 5 and 7). The tile draws the selection face
/// (``TileActionSpec/Selection/single(isSelected:)``): filled with a white check when chosen, dark with an empty ring when not.
///
/// The source is chosen when the active-source sensor reports one of ``selectedStates``, as the tiles do today
/// (``MediaRemoteDevice/activeStates``); with the launcher active, the console and the launcher both read chosen.
///
/// | state | symbol | selection | verb | call |
/// |---|---|---|---|---|
/// | one of ``selectedStates`` | `checkmark` | chosen | "Turn Off TV" (the whole label) | ``deselect`` (the TV-off script), or ``select`` again when ``deselect`` is nil (Fortnite, as today) |
/// | any other live state | `circle` | not chosen | Select | ``select`` (the source's script) |
/// | missing, `unavailable`, `unknown` | `circle` | not chosen | Select | unavailable |
///
/// Feedback is ``TileActionSpec/Feedback/optimistic``: the commands carry the intents today's tiles show (the source, the TV, the
/// Sync Box), so the check moves at once and rolls back on failure. The view's `OptimisticActions` must track
/// ``trackedEntityIds``.
public struct SourceSelectActions: TileActionProviding {
    /// The source-select sources that have a tile, by role (`media.sourceSelect.sources`): a game console, a media server, a
    /// PC and an app launcher that runs on the console. The tile's title is the document's name for the role.
    public enum MusicRoomSource: String, CaseIterable, Sendable {
        case console, server, pc, launcher

        /// The tile's title.
        public var title: String {
            switch self {
            case .console: MediaRemotes.MusicRoom.Source.xbox
            case .server: MediaRemotes.MusicRoom.Source.server
            case .pc: MediaRemotes.MusicRoom.Source.windowsPC
            case .launcher: MediaRemotes.MusicRoom.Source.fortnite
            }
        }
    }

    /// The action's id in every state.
    public static let actionId = "source"
    /// The whole label of a chosen source's disc.
    public static let turnOffLabel = "Turn Off TV"

    /// The entity whose state names the source.
    public var entityId: String
    /// The tile's title.
    public var title: String
    /// States that read chosen.
    public var selectedStates: [String]
    /// Chooses the source (its script and optimistic values).
    public var select: MediaRemoteCommand
    /// Runs when the chosen source is tapped (turns the TV off); nil re-runs ``select``.
    public var deselect: MediaRemoteCommand?
    /// False when the document's script for this source is unusable; the tile then reads unavailable and does nothing.
    public var isAvailable: Bool

    /// Creates the provider.
    public init(
        entityId: String, title: String, selectedStates: [String], select: MediaRemoteCommand, deselect: MediaRemoteCommand? = nil,
        isAvailable: Bool = true
    ) {
        self.isAvailable = isAvailable
        self.entityId = entityId
        self.title = title
        self.selectedStates = selectedStates
        self.select = select
        self.deselect = deselect
    }

    /// A Music Room source, with today's scripts, selected states and optimistic values.
    public static func musicRoom(_ source: MusicRoomSource) -> SourceSelectActions {
        typealias M = MediaRemotes.MusicRoom
        let entity = M.activeMediaSourceEntityId
        switch source {
        case .console:
            return SourceSelectActions(entityId: entity, title: source.title, selectedStates: [M.Source.xbox, M.Source.fortnite],
                                       select: M.xboxOn, deselect: M.tvOff)
        case .server:
            return SourceSelectActions(entityId: entity, title: source.title, selectedStates: [M.Source.server], select: M.serverOn, deselect: M.tvOff)
        case .pc:
            return SourceSelectActions(entityId: entity, title: source.title, selectedStates: [M.Source.windowsPC], select: M.windowsPCOn, deselect: M.tvOff)
        case .launcher:
            // The launcher tile always launches its app; it has no off branch.
            // A document whose launcher is not a plain command (a server mistake) leaves the tile unavailable rather than crashing.
            guard case let .command(fortnite) = M.fortnite else {
                Telemetry.event("houseconfig.launcher", detail: "media.sourceSelect launcher is not a plain command")
                return SourceSelectActions(entityId: entity, title: source.title, selectedStates: [M.Source.fortnite],
                                           select: M.inertCommand, isAvailable: false)
            }
            return SourceSelectActions(entityId: entity, title: source.title, selectedStates: [M.Source.fortnite], select: fortnite)
        }
    }

    /// Every Music Room source in tile order.
    public static var allMusicRoom: [SourceSelectActions] { MusicRoomSource.allCases.map(musicRoom) }

    /// Entities the sources' optimistic values touch, for the view's `OptimisticActions` rules.
    public static var trackedEntityIds: [String] { MediaRemotes.MusicRoom.mediaOptimisticEntityIds }

    /// Whether `state` reads chosen.
    public func isSelected(_ state: String?) -> Bool {
        guard let state, !EntityState.isUnavailable(state) else { return false }
        return selectedStates.contains(state)
    }

    public func actions(for state: EntityState?) -> [TileActionSpec] {
        let selected = isSelected(state?.state)
        let unavailable = EntityState.isUnavailable(state?.state) || !isAvailable
        let command = selected ? (deselect ?? select) : select
        var call: ServiceCall?
        var intents: [OptimisticIntent] = []
        if isAvailable, case let .service(serviceCall, optimistic) = command { call = serviceCall; intents = optimistic }
        let turnsOff = selected && deselect != nil
        return [TileActionSpec(
            id: Self.actionId, verb: turnsOff ? Self.turnOffLabel : "Select", symbol: selected ? "checkmark" : "circle",
            phase: unavailable ? .unavailable : .ready, feedback: .optimistic, call: call, optimistic: intents,
            label: turnsOff ? Self.turnOffLabel : nil, selection: .single(isSelected: selected)
        )]
    }

    /// The tile's state line (selection-tiles option C): "On the TV" while chosen, nothing while not, "Unavailable" when the source
    /// entity cannot be reached.
    public func stateText(for state: String?) -> String? {
        if EntityState.isUnavailable(state) { return "Unavailable" }
        return isSelected(state) ? "On the TV" : nil
    }

    public var stateTextCandidates: [String] { ["On", "Off", "On the TV", "Unavailable", "Didn't Respond"] }
}
