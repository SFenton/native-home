import Foundation

// MARK: - Actions

/// What a remote control does once any state-dependent choice has been made.
public enum MediaRemoteCommand: Hashable, Sendable, Codable {
    /// Calls a service, showing the optimistic values meanwhile.
    case service(ServiceCall, optimistic: [OptimisticIntent] = [])
    /// Opens the inline keyboard that types into `targetEntityId` (web `textPrompt`).
    case textPrompt(targetEntityId: String)

    /// The service this command calls, or `nil` for a command that calls none (a text prompt, or an inert placeholder).
    public var serviceName: String? {
        guard case let .service(call, _) = self, !call.service.isEmpty else { return nil }
        return call.service
    }
}

/// A remote control's action (web `MediaRemoteAction`).
public enum MediaRemoteAction: Hashable, Sendable, Codable {
    /// Always the same command.
    case command(MediaRemoteCommand)
    /// Picks a command from an entity's displayed state (web `type: 'state'`). When `entityId` is `nil`
    /// the control's own entity decides.
    case state(entityId: String?, cases: [StateCase], otherwise: MediaRemoteCommand)

    /// One branch of a ``state(entityId:cases:otherwise:)`` action.
    public struct StateCase: Hashable, Sendable, Codable {
        public var states: [String]
        public var command: MediaRemoteCommand

        /// Creates a branch taken when the state is one of `states`.
        public init(_ states: [String], _ command: MediaRemoteCommand) {
            self.states = states
            self.command = command
        }
    }

    /// A plain service call.
    public static func service(
        _ domain: String, _ service: String, target: String? = nil,
        data: [String: JSONValue] = [:], optimistic: [OptimisticIntent] = []
    ) -> MediaRemoteAction {
        .command(.service(ServiceCall(domain, service, target: target, data: data), optimistic: optimistic))
    }
}

// MARK: - Semantics

/// What assistive technologies should be told a control is (web `ControlSemantics`).
public enum ControlSemantics: Hashable, Sendable {
    /// Fires a command; no state.
    case command
    /// Shows a state; not actionable.
    case state
    /// An on/off switch.
    case toggle(isOn: Bool)
    /// One of a set of choices.
    case selection(isSelected: Bool)
}

/// Maps a displayed state to ``ControlSemantics`` (web `ControlSemanticsResolver`).
public enum SemanticsRule: Hashable, Sendable, Codable {
    /// A toggle that is on unless the state is missing or one of these.
    case toggleOnUnless([String])
    /// A toggle that is on when the state is one of these.
    case toggleOnWhen([String])
    /// Selected when the state is one of these.
    case selectedWhen([String])
    /// Read-only state.
    case state

    /// The semantics for a displayed state.
    public func semantics(for state: String?) -> ControlSemantics {
        switch self {
        case let .toggleOnUnless(off): .toggle(isOn: state.map { !off.contains($0) } ?? false)
        case let .toggleOnWhen(on): .toggle(isOn: state.map(on.contains) ?? false)
        case let .selectedWhen(selected): .selection(isSelected: state.map(selected.contains) ?? false)
        case .state: .state
        }
    }
}

/// The power icon's color: red while the device is on, green while it is off (web `powerIconColorRule`).
public struct IconColorRule: Hashable, Sendable, Codable {
    /// The icon shows inactive only when every one of these is in its inactive states.
    public var entityIds: [String]
    public var inactiveStates: [String]
    public var inactiveStatesByEntity: [String: [String]]

    /// Creates a rule.
    public init(entityIds: [String], inactiveStates: [String], inactiveStatesByEntity: [String: [String]] = [:]) {
        self.entityIds = entityIds
        self.inactiveStates = inactiveStates
        self.inactiveStatesByEntity = inactiveStatesByEntity
    }
}

/// The two tones an ``IconColorRule`` picks between.
public enum IconTone: Hashable, Sendable {
    /// The device is on (web `red`).
    case active
    /// The device is off (web `green`).
    case inactive
}

// MARK: - Controls

/// One remote button (web `MediaRemoteButtonConfig`).
public struct MediaRemoteButton: Hashable, Sendable, Codable {
    /// VoiceOver label, e.g. `Up`.
    public var label: String
    /// MDI icon name; blank draws no icon (the SHIELD select button).
    public var icon: String
    /// Rotation applied to the icon (the SHIELD back triangle points left).
    public var iconRotationDegrees: Double
    public var action: MediaRemoteAction
    public var iconColorRule: IconColorRule?
    public var semantics: SemanticsRule?

    /// Creates a button.
    public init(
        _ label: String, icon: String, rotation: Double = 0, action: MediaRemoteAction,
        iconColorRule: IconColorRule? = nil, semantics: SemanticsRule? = nil
    ) {
        self.label = label
        self.icon = icon
        self.iconRotationDegrees = rotation
        self.action = action
        self.iconColorRule = iconColorRule
        self.semantics = semantics
    }

    /// Whether the button draws an icon.
    public var hasIcon: Bool { !icon.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// An app launch tile (web `MediaRemoteAppConfig`).
public struct MediaRemoteApp: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var action: MediaRemoteAction
    /// Artwork path on the Home Assistant server, e.g. `/local/images/apps/plex.png`.
    public var imagePath: String?
    /// MDI icon shown when there is no artwork or it fails to load.
    public var icon: String?
    /// Draw the artwork on white (YouTube).
    public var whiteBackground: Bool
    /// The entity whose state marks this app as running.
    public var stateEntityId: String?
    public var activeStates: [String]
    public var semantics: SemanticsRule?

    public var id: String { title }

    /// Creates an app tile.
    public init(
        _ title: String, action: MediaRemoteAction, imagePath: String? = nil, icon: String? = nil,
        whiteBackground: Bool = false, stateEntityId: String? = nil, activeStates: [String] = [],
        semantics: SemanticsRule? = nil
    ) {
        self.title = title
        self.action = action
        self.imagePath = imagePath
        self.icon = icon
        self.whiteBackground = whiteBackground
        self.stateEntityId = stateEntityId
        self.activeStates = activeStates
        self.semantics = semantics
    }
}

/// Derives one device state from several entities (web `MediaRemoteStateResolver`).
public enum MediaRemoteStateResolver: Hashable, Sendable, Codable {
    /// `musicRoomXboxState` (mediaRemotes.ts:224).
    case consoleState

    /// Resolves the state from the listed entities' states.
    public func resolve(_ states: [String: String]) -> String {
        switch self {
        case .consoleState: MediaRemotes.MusicRoom.xboxState(states)
        }
    }
}

/// A device tile on the Devices tab (web `MediaRemoteDeviceConfig`).
public struct MediaRemoteDevice: Hashable, Sendable, Identifiable, Codable {
    public var title: String
    public var entityId: String
    public var icon: String
    /// `nil` for a read-only tile.
    public var action: MediaRemoteAction?
    /// Keep showing active this long after the live state drops (the Xbox's cloud state flickers).
    public var activeHold: Duration?
    /// A change to any of these ends the hold.
    public var activeHoldResetEntityIds: [String]
    /// States that count as active; empty means "not off, unavailable or unknown".
    public var activeStates: [String]
    public var semantics: SemanticsRule?
    /// Entities the state comes from; defaults to ``entityId``.
    public var stateEntityIds: [String]?
    /// Subtitle overrides by state.
    public var stateLabels: [String: String]
    public var stateResolver: MediaRemoteStateResolver?

    public var id: String { title }

    /// Creates a device tile.
    public init(
        _ title: String, entityId: String, icon: String, action: MediaRemoteAction? = nil,
        activeHold: Duration? = nil, activeHoldResetEntityIds: [String] = [], activeStates: [String] = [],
        semantics: SemanticsRule? = nil, stateEntityIds: [String]? = nil, stateLabels: [String: String] = [:],
        stateResolver: MediaRemoteStateResolver? = nil
    ) {
        self.title = title
        self.entityId = entityId
        self.icon = icon
        self.action = action
        self.activeHold = activeHold
        self.activeHoldResetEntityIds = activeHoldResetEntityIds
        self.activeStates = activeStates
        self.semantics = semantics
        self.stateEntityIds = stateEntityIds
        self.stateLabels = stateLabels
        self.stateResolver = stateResolver
    }
}

/// The Hue Sync tab's entities (web `MediaRemoteHueSyncConfig`).
public struct HueSyncConfig: Hashable, Sendable, Codable {
    public var powerEntityId: String
    public var lightSyncEntityId: String
    public var syncModeEntityId: String
    public var intensityEntityId: String
    public var brightnessEntityId: String
    public var hdmiInputEntityId: String
    /// HDMI 1–4 status sensors, in port order.
    public var hdmiStatusEntityIds: [String]

    /// Creates the Hue Sync configuration.
    public init(
        powerEntityId: String, lightSyncEntityId: String, syncModeEntityId: String, intensityEntityId: String,
        brightnessEntityId: String, hdmiInputEntityId: String, hdmiStatusEntityIds: [String]
    ) {
        self.powerEntityId = powerEntityId
        self.lightSyncEntityId = lightSyncEntityId
        self.syncModeEntityId = syncModeEntityId
        self.intensityEntityId = intensityEntityId
        self.brightnessEntityId = brightnessEntityId
        self.hdmiInputEntityId = hdmiInputEntityId
        self.hdmiStatusEntityIds = hdmiStatusEntityIds
    }

    /// Every entity the tab reads, which the remote shows optimistic values for.
    public var entityIds: [String] {
        [powerEntityId, lightSyncEntityId, syncModeEntityId, intensityEntityId, brightnessEntityId, hdmiInputEntityId] + hdmiStatusEntityIds
    }
}

// MARK: - Tabs

/// The remote sheet's tabs; only those with content appear (web `mediaRemoteModalTabs`).
public enum MediaRemoteTab: String, CaseIterable, Hashable, Sendable, Identifiable {
    case controls, apps, devices, hueSync

    public var id: String { rawValue }

    /// The segment title. The pad's section is "Remote" (direction G, n4 remote).
    public var title: String {
        switch self {
        case .controls: "Remote"
        case .apps: "Apps"
        case .devices: "Devices"
        case .hueSync: "Hue Sync"
        }
    }
}

// MARK: - Remote

/// One media remote (web `MediaRemoteConfig`).
public struct MediaRemoteConfig: Hashable, Sendable, Identifiable, Codable {
    /// The web hash without `#`, e.g. `living-room-shield`.
    public var id: String
    public var title: String
    public var roomTitle: String
    public var remoteTitle: String
    public var mediaEntityId: String
    /// The entity whose state enables the d-pad, navigation and playback controls.
    public var controlEntityId: String

    public var power: MediaRemoteButton
    public var up: MediaRemoteButton
    public var left: MediaRemoteButton
    public var select: MediaRemoteButton
    public var right: MediaRemoteButton
    public var down: MediaRemoteButton
    public var back: MediaRemoteButton
    public var home: MediaRemoteButton
    public var keyboard: MediaRemoteButton?
    public var pause: MediaRemoteButton
    public var play: MediaRemoteButton

    public var volumeTitle: String
    public var volumeEntityId: String
    public var volumeDown: MediaRemoteButton
    public var volumeMute: MediaRemoteButton
    public var volumeUp: MediaRemoteButton
    /// Keep the volume section while the speaker is off (it is then disabled).
    public var showVolumeWhenOff: Bool
    public var hideKeyboardWhenOff: Bool

    public var appSectionTitle: String
    public var apps: [MediaRemoteApp]
    public var devices: [MediaRemoteDevice]
    public var lightSync: HueSyncConfig?

    /// Entities whose commands show optimistic values (web `optimisticStateEntityIds`).
    public var optimisticEntityIds: [String]
    /// Of those, the ones whose optimistic value clears on any live change rather than on confirmation.
    public var liveChangeEntityIds: [String]

    /// Creates a remote.
    public init(
        id: String, title: String, roomTitle: String, remoteTitle: String, mediaEntityId: String, controlEntityId: String,
        power: MediaRemoteButton, up: MediaRemoteButton, left: MediaRemoteButton, select: MediaRemoteButton,
        right: MediaRemoteButton, down: MediaRemoteButton, back: MediaRemoteButton, home: MediaRemoteButton,
        keyboard: MediaRemoteButton? = nil, pause: MediaRemoteButton, play: MediaRemoteButton,
        volumeTitle: String, volumeEntityId: String, volumeDown: MediaRemoteButton, volumeMute: MediaRemoteButton,
        volumeUp: MediaRemoteButton, showVolumeWhenOff: Bool = false, hideKeyboardWhenOff: Bool = false,
        appSectionTitle: String = "Media", apps: [MediaRemoteApp] = [], devices: [MediaRemoteDevice] = [],
        lightSync: HueSyncConfig? = nil, optimisticEntityIds: [String] = [], liveChangeEntityIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.roomTitle = roomTitle
        self.remoteTitle = remoteTitle
        self.mediaEntityId = mediaEntityId
        self.controlEntityId = controlEntityId
        self.power = power
        self.up = up
        self.left = left
        self.select = select
        self.right = right
        self.down = down
        self.back = back
        self.home = home
        self.keyboard = keyboard
        self.pause = pause
        self.play = play
        self.volumeTitle = volumeTitle
        self.volumeEntityId = volumeEntityId
        self.volumeDown = volumeDown
        self.volumeMute = volumeMute
        self.volumeUp = volumeUp
        self.showVolumeWhenOff = showVolumeWhenOff
        self.hideKeyboardWhenOff = hideKeyboardWhenOff
        self.appSectionTitle = appSectionTitle
        self.apps = apps
        self.devices = devices
        self.lightSync = lightSync
        self.optimisticEntityIds = optimisticEntityIds
        self.liveChangeEntityIds = liveChangeEntityIds
    }

    /// Tabs with content, in web order.
    public var tabs: [MediaRemoteTab] {
        [.controls] + (apps.isEmpty ? [] : [.apps]) + (devices.isEmpty ? [] : [.devices]) + (lightSync == nil ? [] : [.hueSync])
    }

    /// The d-pad buttons in reading order: up, left, select, right, down.
    public var directionalButtons: [MediaRemoteButton] { [up, left, select, right, down] }
}

// MARK: - Literals

/// Lets configs and tests write service data as literals (`["command": "DPAD_UP"]`).
extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}
