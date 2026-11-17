import Foundation

// MARK: - Closed grammar of orientation and corner groups

extension ServerUICompositionShape {
    /// `inputs.orientation` of a vacuum source: both flips, written (`sh.surface-orientation@1`). A rotation is the source's own `mapRotationDegrees`.
    static let surfaceOrientation: Shape = object(["flipHorizontal": .bool, "flipVertical": .bool])

    /// What a map button does: the surface's Locate, a command of the source, a service call, or navigation. Not a power toggle, a local
    /// state change, a back or a dismiss.
    static let mapControlAction: Shape = {
        var variants: [String: Shape] = [
            "map": object(["type": fixed("map"), "command": .choice(["locate"])]),
            "source-command": object(["type": fixed("source-command"), "command": .pattern("^[a-zA-Z]{2,24}$", 24)]),
            "call-service": .callService
        ]
        if case .variant(_, let navigation) = navigationAction {
            for (name, shape) in navigation where name != "set-local" { variants[name] = shape }
        }
        return .closedVariant("type", variants)
    }()

    /// `props.primitive.controls` of a map: up to one group for each corner, each a row or a column of one to eight buttons.
    static let mapControls: Shape = {
        let button = object([
            "id": id, "icon": symbolSlot, "label": discLabel, "hint": .optional(.text(160, blank: false)), "action": mapControlAction,
            "visibleWhen": .optional(predicate), "whenUnknown": .optional(whenUnknown), "enabledWhen": .optional(enabledWhen)
        ])
        let group = object([
            "corner": .choice(MapControlCorner.allCases.map(\.rawValue)), "axis": .choice(["row", "column"]),
            "buttons": array(button, ServerUIMapControls.maximumButtons, minimum: 1)
        ])
        return array(group, ServerUIMapControls.maximumGroups)
    }()
}
