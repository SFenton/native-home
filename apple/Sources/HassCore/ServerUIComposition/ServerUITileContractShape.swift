import Foundation

// MARK: - Closed grammar of swipe, words and groups

extension ServerUICompositionShape {
    private static let finite = Shape.number(-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, integer: false)

    /// `props.swipe` of a `state-tile` or `light-group-tile` (`sh.tile-swipe@1`). The call, the range and the fields one tile type owns are compiled.
    static let tileSwipe: Shape = object([
        "axis": fixed("horizontal"),
        "range": object(["min": finite, "max": finite, "step": finite]),
        "value": .optional(operand), "action": .optional(callService),
        "commit": fixed("release"), "detent": .optional(finite), "haptic": .optional(.choice(ServerUITileSwipe.Haptic.allCases.map(\.rawValue))),
        "band": .optional(.bool), "format": .optional(.text(80, blank: false)), "label": .optional(.text(40, blank: false))
    ])

    /// `props.words` of a light group tile, a brightness control and a room overview (`sh.state-words@1`).
    static let stateWords: Shape = object([
        "on": .optional(title), "off": .optional(title), "unavailable": .optional(title),
        "count": .optional(.text(80, blank: false)), "level": .optional(.text(80, blank: false))
    ])

    /// `props.groups` of a `tile-grid` (`sh.grid-state-groups@1`).
    static let gridGroups: Shape = object([
        "by": fixed("state"),
        "items": array(object([
            "id": id, "title": .text(80, blank: false),
            "states": array(.choice(ServerUIGridGroups.State.allCases.map(\.rawValue)), ServerUIGridGroups.State.allCases.count, minimum: 1)
        ]), ServerUIGridGroups.maximumGroups, minimum: 1)
    ])
}
