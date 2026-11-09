import Foundation

/// The house's media remotes, ported from the React dashboard.
///
/// Source: `ha-sfenton-react-dash@9ac2a46:src/constants/mediaRemotes.ts` (service calls, entity IDs, optimistic
/// intents and revert times are verbatim) and `src/i18n/locales/en/pages/media.json` (Music Room copy).
public enum MediaRemotes {
    /// Every remote, in the web's `MEDIA_REMOTE_CONFIGS` order: the server's document.
    public static var all: [MediaRemoteConfig] { HouseConfigSource.active.read { $0.media.remotes } ?? [] }

    /// Looks up a remote by its id (the web hash without `#`).
    public static func config(id: String) -> MediaRemoteConfig? {
        let id = id.hasPrefix("#") ? String(id.dropFirst()) : id
        return all.first { $0.id == id }
    }

    /// The remote a media player opens (web `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID`, surfaceSemantics.ts:83).
    public static func config(forMediaPlayer entityId: String) -> MediaRemoteConfig? {
        remoteIdByMediaPlayer[entityId].flatMap { config(id: $0) }
    }

    /// Which remote each media player opens (web `MEDIA_PAGE_REMOTE_HASH_BY_ENTITY_ID`, surfaceSemantics.ts:83).
    public static var remoteIdByMediaPlayer: [String: String] { HouseConfigSource.active.read { $0.media.remoteIdByMediaPlayer } ?? [:] }

    // MARK: - Builders (mediaRemotes.ts:107-148)

    static let deviceOffStates = ["off", "unavailable", "unknown"]

    static func inputButtonPress(_ target: String) -> MediaRemoteCommand {
        .service(ServiceCall("input_button", "press", target: target))
    }

    /// `pcPowerAction` (mediaRemotes.ts:122): pressing the "off" button while on, else the "on" button.
    static func pcPowerAction(on onTarget: String, off offTarget: String) -> MediaRemoteAction {
        .state(entityId: nil, cases: [.init(["on"], inputButtonPress(offTarget))], otherwise: inputButtonPress(onTarget))
    }

    // MARK: - Music Room (mediaRemotes.ts:158-583)

    /// Music Room entity IDs, states, revert times and actions.
    public enum MusicRoom {
        // The facades below answer the server's `media.sourceSelect` role constants; with no document they are empty.

        /// The Music Room's `controlEntityId`: the server's document.
        public static var controlEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["control"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `xboxEntityId`: the server's document.
        public static var xboxEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["console"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `remoteEntityId`: the server's document.
        public static var remoteEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["remote"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `volumeEntityId`: the server's document.
        public static var volumeEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["volume"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `mediaSourceEntityId`: the server's document.
        public static var mediaSourceEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["mediaSource"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `activeMediaSourceEntityId`: the server's document.
        public static var activeMediaSourceEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["activeMediaSource"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `xboxHdmiStatusEntityId`: the server's document.
        public static var xboxHdmiStatusEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["consoleHdmiStatus"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `hueSyncPowerEntityId`: the server's document.
        public static var hueSyncPowerEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["syncPower"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `hueSyncLightSyncEntityId`: the server's document.
        public static var hueSyncLightSyncEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["syncLightSync"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `hueSyncBrightnessEntityId`: the server's document.
        public static var hueSyncBrightnessEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["syncBrightness"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `hueSyncHdmiInputEntityId`: the server's document.
        public static var hueSyncHdmiInputEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["syncHdmiInput"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `hueSyncModeEntityId`: the server's document.
        public static var hueSyncModeEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["syncMode"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `hueSyncIntensityEntityId`: the server's document.
        public static var hueSyncIntensityEntityId: String { HouseConfigSource.active.read { $0.media.sourceSelect.entityIds["syncIntensity"] }.flatMap { $0 } ?? "" }
        /// The Music Room's `hueSyncHdmiStatusEntityIds`: the server's document.
        public static var hueSyncHdmiStatusEntityIds: [String] { HouseConfigSource.active.read { $0.media.sourceSelect.syncHdmiStatusEntityIds } ?? [] }
        /// The Music Room's `xboxActiveHold`: the server's document.
        public static var xboxActiveHold: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.activeHoldSeconds }.map { .seconds($0) } ?? .zero }
        /// The Music Room's `xboxActiveStates`: the server's document.
        public static var xboxActiveStates: [String] { HouseConfigSource.active.read { $0.media.sourceSelect.activeStates } ?? [] }
        /// The Music Room's `xboxLinkedState`: the server's document.
        static var xboxLinkedState: String { HouseConfigSource.active.read { $0.media.sourceSelect.linkedState } ?? "" }
        static var mediaOptimisticEntityIds: [String] {
            [activeMediaSourceEntityId, controlEntityId, xboxEntityId, xboxHdmiStatusEntityId,
             hueSyncPowerEntityId, hueSyncLightSyncEntityId, hueSyncHdmiInputEntityId]
        }

        /// `MUSIC_ROOM_MEDIA_SOURCE_STATES`.
        public enum Source {
            /// The Music Room's `fortnite`: the server's document.
            public static var fortnite: String { HouseConfigSource.active.read { $0.media.sourceSelect.sources["launcher"] }.flatMap { $0 } ?? "" }
            /// The Music Room's `off`: the server's document.
            public static var off: String { HouseConfigSource.active.read { $0.media.sourceSelect.sources["off"] }.flatMap { $0 } ?? "" }
            /// The Music Room's `server`: the server's document.
            public static var server: String { HouseConfigSource.active.read { $0.media.sourceSelect.sources["server"] }.flatMap { $0 } ?? "" }
            /// The Music Room's `tv`: the server's document.
            public static var tv: String { HouseConfigSource.active.read { $0.media.sourceSelect.sources["tv"] }.flatMap { $0 } ?? "" }
            /// The Music Room's `windowsPC`: the server's document.
            public static var windowsPC: String { HouseConfigSource.active.read { $0.media.sourceSelect.sources["pc"] }.flatMap { $0 } ?? "" }
            /// The Music Room's `xbox`: the server's document.
            public static var xbox: String { HouseConfigSource.active.read { $0.media.sourceSelect.sources["console"] }.flatMap { $0 } ?? "" }
            /// Every source, once each and in order: a document that maps two roles to one state does not repeat it.
            static var all: [String] {
                var seen = Set<String>()
                return [fortnite, off, server, tv, windowsPC, xbox].filter { seen.insert($0).inserted }
            }
        }

        /// `MUSIC_ROOM_COMMAND_REVERT_MS`, `MUSIC_ROOM_XBOX_*` and `HUE_SYNC_OPTIMISTIC_REVERT_MS`.
        public enum Revert {
            /// The Music Room's `fortnite`: the server's document.
            public static var fortnite: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.revertSeconds["launcher"] }.flatMap { $0 }.map { .seconds($0) } ?? .zero }
            /// The Music Room's `server`: the server's document.
            public static var server: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.revertSeconds["server"] }.flatMap { $0 }.map { .seconds($0) } ?? .zero }
            /// The Music Room's `tv`: the server's document.
            public static var tv: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.revertSeconds["tv"] }.flatMap { $0 }.map { .seconds($0) } ?? .zero }
            /// The Music Room's `windowsPC`: the server's document.
            public static var windowsPC: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.revertSeconds["pc"] }.flatMap { $0 }.map { .seconds($0) } ?? .zero }
            /// The Music Room's `xbox`: the server's document.
            public static var xbox: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.revertSeconds["console"] }.flatMap { $0 }.map { .seconds($0) } ?? .zero }
            /// The Music Room's `xboxOff`: the server's document.
            public static var xboxOff: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.revertSeconds["consoleOff"] }.flatMap { $0 }.map { .seconds($0) } ?? .zero }
            /// The Music Room's `hueSync`: the server's document.
            public static var hueSync: Duration { HouseConfigSource.active.read { $0.media.sourceSelect.revertSeconds["sync"] }.flatMap { $0 }.map { .seconds($0) } ?? .zero }
        }

        /// `musicRoomXboxState` (mediaRemotes.ts:224): on when the Xbox cloud state is active, or when the TV is on,
        /// the Sync Box is powered on HDMI 1 and HDMI 1 reports `linked`; off when anything reports a real state.
        public static func xboxState(_ states: [String: String]) -> String {
            let cloud = states[xboxEntityId]
            let hdmi = states[xboxHdmiStatusEntityId]
            let tv = states[controlEntityId]
            let power = states[hueSyncPowerEntityId]
            let input = states[hueSyncHdmiInputEntityId]
            let cloudActive = cloud.map(xboxActiveStates.contains) ?? false
            let linkedOnActivePath = tv.map { $0 != "off" && !EntityState.isUnavailable($0) } == true
                && power == "on"
                && input?.hasSuffix(" 1") == true
                && hdmi == xboxLinkedState
            if cloudActive || linkedOnActivePath { return "on" }
            let known = [cloud, hdmi, tv, power, input].contains { $0.map { !EntityState.isUnavailable($0) } ?? false }
            return known ? "off" : "unavailable"
        }

        // MARK: Action graphs

        private static func command(_ role: String) -> MediaRemoteCommand? {
            HouseConfigSource.active.read { $0.media.sourceSelect.commands[role] }.flatMap { $0 }
        }

        private static func action(_ role: String) -> MediaRemoteAction? {
            HouseConfigSource.active.read { $0.media.sourceSelect.actions[role] }.flatMap { $0 }
        }

        /// What a role answers when the document has no graph for it: a command that calls no service. A page with no
        /// document draws a skeleton or message instead of tiles, so nothing reaches this.
        public static let inertCommand = MediaRemoteCommand.service(ServiceCall("script", ""))

        /// Turns the TV on: the server's document.
        public static var tvOn: MediaRemoteCommand { command("tvOn") ?? inertCommand }
        /// Turns the TV off: the server's document.
        public static var tvOff: MediaRemoteCommand { command("tvOff") ?? inertCommand }
        /// Starts the console: the server's document.
        public static var xboxOn: MediaRemoteCommand { command("consoleOn") ?? inertCommand }
        /// Stops the console: the server's document.
        public static var xboxOff: MediaRemoteCommand { command("consoleOff") ?? inertCommand }
        /// Selects the server: the server's document.
        public static var serverOn: MediaRemoteCommand { command("serverOn") ?? inertCommand }
        /// Selects the PC: the server's document.
        public static var windowsPCOn: MediaRemoteCommand { command("pcOn") ?? inertCommand }
        /// `MUSIC_ROOM_MEDIA_ACTIONS.fortnite`: the server's document.
        public static var fortnite: MediaRemoteAction { action("launcher") ?? .command(inertCommand) }
        /// `MUSIC_ROOM_MEDIA_ACTIONS.serverToggle`: the server's document.
        public static var serverToggle: MediaRemoteAction { action("serverToggle") ?? .command(inertCommand) }
        /// `MUSIC_ROOM_MEDIA_ACTIONS.tvToggle`, also the power button: the server's document.
        public static var tvToggle: MediaRemoteAction { action("tvToggle") ?? .command(inertCommand) }
        /// `MUSIC_ROOM_MEDIA_ACTIONS.windowsPcToggle`: the server's document.
        public static var windowsPCToggle: MediaRemoteAction { action("pcToggle") ?? .command(inertCommand) }
        /// `MUSIC_ROOM_MEDIA_ACTIONS.xboxSourceToggle`: the server's document.
        public static var xboxSourceToggle: MediaRemoteAction { action("consoleSourceToggle") ?? .command(inertCommand) }
        /// `MUSIC_ROOM_MEDIA_ACTIONS.xboxToggle`: the server's document.
        public static var xboxToggle: MediaRemoteAction { action("consoleToggle") ?? .command(inertCommand) }

        /// `musicRoomSourceLabels`: "On" for the active source, "Off" for every other source.
        static func sourceLabels(active: String) -> [String: String] {
            Dictionary(uniqueKeysWithValues: Source.all.map { ($0, $0 == active ? "On" : "Off") })
        }
    }

    /// The id of the remote the source-select roles belong to: the document's `media.sourceSelect.remoteId`.
    public static var sourceSelectRemoteId: String {
        HouseConfigSource.active.read { $0.media.sourceSelect.remoteId }.flatMap { $0 } ?? ""
    }

    /// The source-select remote (the one `media.sourceSelect` describes): the server's copy by ``sourceSelectRemoteId``, else an
    /// unconfigured placeholder with no entities.
    public static var sourceSelectRemote: MediaRemoteConfig { config(id: sourceSelectRemoteId) ?? .unconfigured }
}

extension MediaRemoteConfig {
    /// A remote with nothing behind it, for a house with no document: no entities, and every button calls no service.
    public static let unconfigured: MediaRemoteConfig = {
        func button(_ title: String) -> MediaRemoteButton {
            MediaRemoteButton(title, icon: " ", action: .command(MediaRemotes.MusicRoom.inertCommand))
        }
        return MediaRemoteConfig(
            id: "", title: "", roomTitle: "", remoteTitle: "", mediaEntityId: "", controlEntityId: "",
            power: button("Power"), up: button("Up"), left: button("Left"), select: button("Select"), right: button("Right"),
            down: button("Down"), back: button("Back"), home: button("Home"), pause: button("Pause"), play: button("Play"),
            volumeTitle: "", volumeEntityId: "", volumeDown: button("Volume Down"), volumeMute: button("Mute"),
            volumeUp: button("Volume Up")
        )
    }()
}
