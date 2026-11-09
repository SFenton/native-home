import Foundation

/// Which action provider a configured tile uses, so a config can be classified without a screen.
public enum TileActionKind: String, Equatable, Sendable, CaseIterable {
    /// No actions: the tile opens something or only shows state.
    case none
    /// ``LockActions``.
    case lock
    /// ``CoverActions`` (garage doors).
    case garageDoor
    /// ``PowerToggleActions`` (PCs, towel racks, guest toggles, lights and switches).
    case power
    /// ``FanRailActions``.
    case bathroomFan
    /// ``VacuumActions``.
    case vacuum
    /// ``MediaTransportActions``: Power while off, transport while playing.
    case mediaRemote
    /// A single config-defined command with no dedicated provider yet.
    case command
    /// ``CommandActions``: one momentary service or script call (Admin's power recovery).
    case momentaryCommand
    /// ``SourceSelectActions``: a Music Room source, single choice.
    case sourceSelect
    /// ``ScriptPowerActions``: Nintendo Switch and Cinema Streamer, a power disc tracked through a script.
    case scriptPower
    /// ``BedSidePowerActions``: a bed side's power disc on a navigation tile.
    case bedSidePower
    /// ``HotFlashActions``: Hot Flash Mode's snowflake and stop disc.
    case hotFlash
    /// ``AlarmModeActions``: Quick Links Security System, Arm Home or Disarm.
    case alarmMode
    /// ``SprinklerActions``: Stop Watering on a controller card.
    case sprinkler
    /// ``RoomLightsPowerActions``: a Home overview Lights room card's room power disc.
    case roomLightsPower
    /// A tile that chooses (``SelectionActions``): vacuum rooms, Solo Trip travelers.
    case selection

    /// The actions the tile carries in its resting state (a remote is off: Power only), which fixes its class.
    public var restingActionCount: Int {
        switch self {
        case .none: 0
        case .lock, .garageDoor, .power, .mediaRemote, .command, .momentaryCommand, .sourceSelect, .scriptPower, .bedSidePower,
             .hotFlash, .alarmMode, .sprinkler, .selection, .roomLightsPower: 1
        case .bathroomFan, .vacuum: 2
        }
    }
}
