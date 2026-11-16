import Foundation

// MARK: - Generic part grammar (TC3)

/// The closed shapes of the five generic part capabilities: choice options read from an entity (`sh.bound-options-read@1`), a toggle
/// row's own parts (`sh.bound-row-parts@1`) and check face (`sh.check-face@1`). A tile button's rule slots (`sh.tile-disc-rules@1`) and
/// the grid's least columns (`sh.grid-min-columns@1`) sit in ``ServerUICompositionShape/tileParts`` and the `tile-grid` node.
extension ServerUICompositionShape {
    /// `props.optionsFrom` of a bound choice: the list to read, the value now, how to word the items and what choosing one does.
    static let optionsFrom: Shape = {
        object([
            "from": object(["type": fixed("source"), "sourceId": id, "path": array(.text(160, blank: false), 8, minimum: 1)]),
            "current": operand, "labels": .choice(ServerUIOptionsRead.Labels.allNames), "action": callService
        ])
    }()

    /// The `props` of a bound toggle row beyond the shipped ones, each optional.
    static let boundRowParts: [String: Shape] = [
        "subtitle": .optional(textValue(.text(2_000, blank: true))),
        "hint": .optional(.text(240, blank: false)),
        "metrics": .optional(.choice(ServerUIRowParts.Metrics.allNames)),
        "failureText": .optional(title),
        "glyph": .optional(solidSlot),
        "face": .optional(.choice(ServerUIRowParts.Face.allNames)),
        "checkTint": .optional(.choice(ServerUIRowParts.CheckTint.allNames))
    ]
}

extension ServerUIOptionsRead.Labels {
    static let allNames = ["as-is", "title-case"]
}

extension ServerUIRowParts.Metrics {
    static let allNames = ["form", "module"]
}

extension ServerUIRowParts.Face {
    static let allNames = ["switch", "check"]
}

extension ServerUIRowParts.CheckTint {
    static let allNames = ["action", "success"]
}
