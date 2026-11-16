import Foundation

// MARK: - Corner button groups (`sh.surface-controls@1`)

/// What a map button does.
public enum ServerUIMapControlAction: Equatable, Sendable {
    /// The surface's own Locate: the robot plays a sound. It hides while the robot is unavailable.
    case locate
    /// A command of the vacuum, drawn with the state rules of its command tile: shown only when the command is offered, dimmed while it
    /// is blocked, the reason spoken as the VoiceOver value.
    case sourceCommand(VacuumController.Action.Kind)
    /// A service call or a navigation, run through the renderer like any other action.
    case perform(ServerUICompositionDocument.Action)
}

/// One button of a corner group: a 44 pt glass button with a symbol and a label VoiceOver and Voice Control read.
public struct ServerUIMapControlButton: Equatable, Sendable {
    /// The id, unique across the whole surface; `map.control.<id>` is its accessibility identifier (Locate keeps `vacuum.locate`).
    public let id: String
    /// What VoiceOver adds after the label.
    public let hint: String?
    /// What the button does when pressed.
    public let action: ServerUIMapControlAction
    /// The symbol, label, `visibleWhen` and `enabledWhen`, each plain or following a rule (`sh.tile-disc-rules@1`, as a tile's buttons do).
    /// Its own `action` is not used: ``action`` is the button's action.
    public let look: ServerUITileParts.Disc

    public init(id: String, hint: String?, action: ServerUIMapControlAction, look: ServerUITileParts.Disc) {
        self.id = id
        self.hint = hint
        self.action = action
        self.look = look
    }

    /// The accessibility identifier: Locate keeps the one it has always had.
    public var identifier: String { action == .locate ? "vacuum.locate" : "map.control.\(id)" }
}

/// One corner's group: a row or a column of buttons in authored order.
public struct ServerUIMapControlGroup: Equatable, Sendable {
    /// The corner the group sits in.
    public let corner: MapControlCorner
    /// Whether the buttons run in a row or a column.
    public let axis: MapControlAxis
    /// The buttons in authored order.
    public let buttons: [ServerUIMapControlButton]

    public init(corner: MapControlCorner, axis: MapControlAxis, buttons: [ServerUIMapControlButton]) {
        self.corner = corner
        self.axis = axis
        self.buttons = buttons
    }
}

/// The rules for a surface's groups that are not the shape: what an unauthored map draws, and the truth `locate` must state.
public enum ServerUIMapControls {
    /// The most groups: one for each corner.
    public static let maximumGroups = 4
    /// The most buttons in a group; the fit rule, not this limit, decides how many show.
    public static let maximumButtons = 8

    /// The Locate button an unauthored map has today: a `scope` glyph, "Locate", the robot plays a sound.
    public static let locateButton = ServerUIMapControlButton(
        id: "locate", hint: "Asks the robot to play a sound.", action: .locate,
        look: .init(id: "locate", icon: .init(name: "scope", rendering: .canonical, unavailable: .fallback), label: "Locate",
                    action: .back, visibility: nil, enabledWhen: nil))

    /// What a surface without `controls` draws: one column at top leading holding Locate when `locate` is true, else nothing.
    public static func defaultGroups(locate: Bool) -> [ServerUIMapControlGroup] {
        locate ? [.init(corner: .topLeading, axis: .column, buttons: [locateButton])] : []
    }

    /// The groups a map draws: the authored ones, or the default derived from `locate`.
    public static func effective(locate: Bool, controls: [ServerUIMapControlGroup]?) -> [ServerUIMapControlGroup] {
        controls ?? defaultGroups(locate: locate)
    }

    /// Whether any button is Locate: the truth `locate` must state when `controls` is authored.
    public static func hasLocate(_ controls: [ServerUIMapControlGroup]) -> Bool {
        controls.contains { $0.buttons.contains { $0.action == .locate } }
    }

    /// The groups as the fit rule takes them.
    public static func fitGroups(_ groups: [ServerUIMapControlGroup]) -> [MapControlFit.Group] {
        groups.map { .init(corner: $0.corner, axis: $0.axis, count: $0.buttons.count) }
    }
}
