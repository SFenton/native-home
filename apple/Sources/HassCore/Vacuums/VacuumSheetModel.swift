import Foundation

// MARK: - Cleaning mode

/// The vacuum's cleaning mode as the `select` entity's options name it (`vacuum`, `mop`, `vacuum_and_mop`), and which
/// settings that mode makes meaningful (owner, 2026-10-28: Water is absent when Mode is vacuum-only, Fan is absent when
/// Mode is mop-only). Pure, so the rule is unit-tested apart from the sheet that animates the rows in and out.
public enum VacuumCleaningMode: Equatable, Sendable {
    case vacuum, mop, vacuumAndMop
    /// No mode entity, or a value that names none of the three: every setting stays.
    case unknown

    /// Reads an option or state: case, spaces and underscores do not matter (`"Vacuum And Mop"`, `"vacuum_and_mop"`).
    public init(option: String?) {
        let key = (option ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "&", with: "and")
        switch key {
        case "vacuum": self = .vacuum
        case "mop": self = .mop
        case "vacuum_and_mop": self = .vacuumAndMop
        default: self = .unknown
        }
    }

    /// Fan (suction) matters unless the robot only mops.
    public var showsFan: Bool { self != .mop }
    /// Water (mop flow) matters unless the robot only vacuums.
    public var showsWater: Bool { self != .vacuum }

    /// The option's label in the pop-up: `Vacuum`, `Mop`, `Vacuum and Mop`.
    public var label: String? {
        switch self {
        case .vacuum: "Vacuum"
        case .mop: "Mop"
        case .vacuumAndMop: "Vacuum and Mop"
        case .unknown: nil
        }
    }
}

// MARK: - Setting rows

/// Which setting a row of the Cleaning Settings group is.
public enum VacuumSettingRole: String, Sendable, CaseIterable {
    case mode, fan, water, passes, other
}

/// One row of the Cleaning Settings group, whether or not it shows now. The sheet keeps hidden rows in the tree so a
/// change of mode animates them in and out (row height with `standard`, content with `quick`).
public struct VacuumCleaningSettingRow: Identifiable, Equatable, Sendable {
    public var setting: VacuumController.Setting
    public var role: VacuumSettingRole
    public var isShown: Bool
    public var id: String { setting.id }

    public init(setting: VacuumController.Setting, role: VacuumSettingRole, isShown: Bool) {
        self.setting = setting
        self.setting.role = role
        self.role = role
        self.isShown = isShown
    }
}

/// The words around the Cleaning Settings group.
public enum VacuumSheetCopy {
    /// The one footer under the group; the long per-setting descriptions are the rows' VoiceOver hints.
    public static let settingsFooter = "Water is available when Mode includes mopping."
    /// The Selected Rooms row's VoiceOver value when no room is selected.
    public static let fullCleanSpoken = "No rooms are selected. Cleaning starts on every mapped area."
    /// Under the selected-rooms summary.
    public static let roomsTargetFooter = "The vacuum cleans the selected rooms in order."
    /// Under the area tiles.
    public static let areaTargetFooter = "The vacuum cleans inside the drawn area, with the settings below."
    /// Under the Rooms grid.
    public static let roomsFooter = "Tap rooms here or on the map. Rooms are cleaned in the order you choose them; the numbers show the order."
    /// Under the Auto-Clean grid.
    public static let autoCleanFooter = "Checked rooms are included when the coordinator starts an automatic away clean. Unchecked rooms are skipped and hatched on the map. Manual cleans from Rooms are unaffected."
}

// MARK: - Status tiles

/// One of the three read-only tiles under the map: Status, Battery, Dock (caption over value, toned glyph).
public struct VacuumStatusTile: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable { case status, battery, dock }

    /// How the glyph is inked.
    public enum Tint: Equatable, Sendable {
        case tone(VacuumTone)
        /// The primary ink (a battery that reports, a dock that is idle).
        case primary
        case secondary
    }

    public var kind: Kind
    /// What VoiceOver names the tile and the caption reads: `Status`, `Battery`, `Dock`.
    public var caption: String
    public var value: String
    /// An SF Symbol, or an MDI name when ``symbolIsMDI``.
    public var symbol: String
    public var symbolIsMDI: Bool
    public var tint: Tint
    public var id: String { kind.rawValue }

    /// The glyph for a vacuum state: Docked reads as a green check, the rest keep their own.
    public static func stateGlyph(_ state: String) -> (symbol: String, isMDI: Bool) {
        state.lowercased() == "docked" ? ("checkmark.circle.fill", false) : (VacuumVisual.state(state).icon, true)
    }

    /// The battery glyph nearest the level in a label such as `87%`; the empty battery while the level is unknown.
    public static func batterySymbol(_ label: String) -> String {
        guard label.hasSuffix("%"), let level = Double(label.dropLast()) else { return "battery.0percent" }
        return switch level {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    /// The dock's status in words for a tile ("Washing" while it cleans the pads).
    public static func dockValue(_ state: String?, available: Bool) -> String {
        guard available else { return "Unknown" }
        if state == "cleaning" { return "Washing" }
        return VacuumFormat.state(state, fallback: "Unknown")
    }
}

public extension VacuumController {
    /// Status, Battery and, when the robot has a dock, Dock.
    var statusTiles: [VacuumStatusTile] {
        let status = status
        let state = statusState
        let glyph = VacuumStatusTile.stateGlyph(state)
        var tiles = [
            VacuumStatusTile(kind: .status, caption: "Status", value: VacuumFormat.state(state), symbol: glyph.symbol, symbolIsMDI: glyph.isMDI,
                             tint: .tone(VacuumVisual.state(state).tone)),
            VacuumStatusTile(kind: .battery, caption: "Battery", value: batteryLabel, symbol: VacuumStatusTile.batterySymbol(batteryLabel),
                             symbolIsMDI: false, tint: status.primaryAvailable ? .primary : .secondary),
        ]
        if vacuum.dockControls != nil {
            let dock = VacuumVisual.dock(dockState)
            let tone = status.primaryAvailable ? dock.tone : .unavailable
            let plain = tone == .neutral || tone == .unavailable
            tiles.append(VacuumStatusTile(kind: .dock, caption: "Dock", value: VacuumStatusTile.dockValue(dockState, available: status.primaryAvailable),
                                          symbol: plain ? "ev.charger" : dock.icon, symbolIsMDI: !plain,
                                          tint: tone == .neutral ? .primary : .tone(tone)))
        }
        return tiles
    }
}

// MARK: - Choice tiles (Rooms, Auto-Clean)

/// What a Rooms or Auto-Clean choice tile shows: chosen or not, its order, what VoiceOver says. Pure, so the mapping is
/// unit-tested; the view draws it with the shared tile and its numbered or check disc.
public struct VacuumChoiceTile: Equatable, Sendable {
    public var title: String
    /// The MDI glyph (drawn only where the disc does not carry the tile).
    public var icon: String
    public var isChosen: Bool
    /// The cleaning order (Rooms); `nil` draws a check (Auto-Clean).
    public var order: Int?
    public var subtitle: String?
    public var isUnavailable: Bool
    public var accessibilityLabel: String
    public var accessibilityValue: String

    /// A room on the Rooms section.
    public static func room(title: String, icon: String, order: Int?, editable: Bool) -> VacuumChoiceTile {
        VacuumChoiceTile(title: title, icon: icon, isChosen: order != nil, order: order, subtitle: nil, isUnavailable: !editable,
                         accessibilityLabel: order.map { "\(title), cleaning order \($0)" } ?? title,
                         accessibilityValue: order == nil ? "Not selected" : "Selected")
    }

    /// A room on the Auto-Clean section: checked means included in automatic cleans (the entity says "disabled", so it is
    /// inverted here and nowhere else).
    public static func autoClean(title: String, icon: String, skipped: Bool, unavailable: Bool) -> VacuumChoiceTile {
        let value = unavailable ? "Unavailable" : skipped ? "Skipped" : "Included"
        return VacuumChoiceTile(title: title, icon: icon, isChosen: !skipped && !unavailable, order: nil,
                                subtitle: unavailable ? "Unavailable" : skipped ? "Skipped" : nil, isUnavailable: unavailable,
                                accessibilityLabel: "\(title) auto-clean", accessibilityValue: value)
    }
}

public extension VacuumController {
    /// What VoiceOver reads as the value of the Selected Rooms row: the rooms in cleaning order, or the Full Clean notice.
    var selectedRoomsSpokenValue: String {
        let rooms = selectedZones
        guard !rooms.isEmpty else { return VacuumSheetCopy.fullCleanSpoken }
        return rooms.enumerated().map { "\($0 + 1). \($1.title)" }.joined(separator: ", ")
    }

    /// The map's VoiceOver value: the room names are not drawn on the map, so this is where it names the selected rooms, in
    /// cleaning order like the badges ("Selected rooms: 1. Kitchen, 2. Office"); empty when none is selected.
    var selectedRoomsMapValue: String {
        selectedZones.isEmpty ? "" : "Selected rooms: " + selectedRoomsSpokenValue
    }

    /// The Rooms section's tiles in configuration order.
    var roomTiles: [(zone: VacuumConfig.Zone, tile: VacuumChoiceTile)] {
        let selected = selectedZones
        return vacuum.zones.map { zone in
            let order = selected.firstIndex { $0.entityId == zone.entityId }.map { $0 + 1 }
            return (zone, .room(title: zone.title, icon: zone.icon, order: order, editable: roomsEditable))
        }
    }

    /// The Auto-Clean section's tiles in configuration order.
    var autoCleanTiles: [(room: VacuumConfig.AutoCleanRoom, tile: VacuumChoiceTile)] {
        vacuum.autoCleanDisabledRooms.map { room in
            let unavailable = VacuumStatusResolver.isUnavailable(store.entity(room.entityId).state?.state)
            return (room, .autoClean(title: room.title, icon: room.icon, skipped: isAutoCleanDisabled(room), unavailable: unavailable))
        }
    }
}

// MARK: - Action tiles (Controls, Dock)

/// A command drawn as an action tile (text, then one disc).
public struct VacuumCommandTile: Identifiable, Equatable, Sendable {
    public var action: VacuumController.Action
    public var spec: TileActionSpec
    /// The tile's second line ("Starting…"), or nil.
    public var subtitle: String?
    /// The filled face: a stop command while its cycle runs.
    public var isFilled: Bool
    /// The explanation under the tile, an iOS-style footer (dock commands).
    public var footer: String?
    public var id: String { action.id }

    /// The tile for a run or dock command.
    /// - Parameters:
    ///   - action: The command.
    ///   - pending: A dock cycle was just started and the dock has not confirmed it yet (the tracked in-flight disc).
    ///   - showsFooter: Whether the explanation goes under the tile (dock) or is only the VoiceOver value (run).
    public static func make(_ action: VacuumController.Action, pending: Bool = false, showsFooter: Bool) -> VacuumCommandTile {
        let stops = [.stopDockClean, .stopDrying].contains(action.kind)
        let tracked = [.cleanDock, .stopDockClean, .dryMops, .stopDrying].contains(action.kind)
        let inFlight = pending && tracked && !action.isDisabled
        let spec = TileActionSpec(id: action.kind.rawValue, verb: action.title, symbol: action.kind.symbol,
                                  phase: inFlight ? .inFlight : action.isDisabled ? .unavailable : .ready,
                                  feedback: tracked ? .tracked : .momentary)
        return VacuumCommandTile(action: action, spec: spec, subtitle: inFlight ? "Starting…" : stops && !action.isDisabled ? (action.kind == .stopDrying ? "Drying" : "Washing") : nil,
                                 isFilled: stops && !action.isDisabled, footer: showsFooter ? action.detail : nil)
    }
}

public extension VacuumController.Action.Kind {
    /// The tile disc's SF Symbol.
    var symbol: String {
        switch self {
        case .clean, .cleanArea, .resume: "play.fill"
        case .pause: "pause.fill"
        case .stop, .cancelResume, .cancelSession, .stopDockClean, .stopDrying: "stop.fill"
        case .dock: "house.fill"
        case .cleanDock: "drop"
        case .dryMops: "wind"
        case .emptyBin: "trash.circle"
        }
    }
}

public extension VacuumController {
    /// A dock cycle was started and the dock has not reported it yet.
    var dockCommandPending: Bool {
        guard let id = vacuum.dockControls?.dockStatusEntityId else { return false }
        return displayedDockState != (live(id) ?? "unknown")
    }

    /// Pause, Stop, Resume… as tiles (no text under them; the reason a command is dim is its VoiceOver value).
    var runtimeTiles: [VacuumCommandTile] { runtimeActions.map { .make($0, showsFooter: false) } }

    /// Dock commands as tiles, each with its explanation as a footer.
    var dockTiles: [VacuumCommandTile] {
        let pending = dockCommandPending
        return dockActions.map { .make($0, pending: pending, showsFooter: true) }
    }
}

public extension VacuumFormat {
    /// An area's size for the Edit Area tile and the editor's summary: `3.8 m × 2.6 m`.
    static func areaSize(_ area: MapGridRect, pixelSize: Double) -> String {
        let size = area.dimensionsCm(pixelSize: pixelSize)
        return "\(metres(size.width)) × \(metres(size.height))"
    }
}
