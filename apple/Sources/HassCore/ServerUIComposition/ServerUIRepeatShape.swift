import Foundation

// MARK: - Closed grammar of the repeat node

/// The closed shape of the `repeat` node (`sh.repeat@1`), kept apart from ``ServerUICompositionShape``'s tables so the lanes that extend those
/// tables do not collide. It is referenced from one line of the table it extends.
extension ServerUICompositionShape {
    private static let repeatPaging: Shape = object([
        "compact": .number(1, 12, integer: true), "regular": .number(1, 12, integer: true),
        // Each factor is above 0 and at most 1; the least positive number stands for "above 0".
        "scaleByTextSize": .optional(array(.number(Double.leastNonzeroMagnitude, 1, integer: false), 4, minimum: 4)),
        "minimum": .optional(.number(1, 12, integer: true)), "indicator": .optional(.bool),
        "buttons": .optional(.choice(ServerUIRepeat.Buttons.allCases.map(\.rawValue))), "label": .optional(title)
    ])

    private static let repeatProps: Shape = object([
        "providerId": id, "axis": .choice(ServerUIRepeat.Axis.allCases.map(\.rawValue)), "spacing": space,
        "limit": .optional(.number(1, Double(ServerUIRepeat.maximumCells), integer: true)),
        "paging": .optional(repeatPaging),
        "placeholder": .optional(object(["count": .number(1, Double(ServerUIRepeat.maximumPlaceholders), integer: true)])),
        "loadingText": title, "emptyText": title, "unavailableText": title, "errorText": title, "staleText": title
    ])

    /// The `repeat` node over the fields every node has.
    static func repeatNodes(base: [String: Shape]) -> [String: Shape] {
        ["repeat": object(base.merging(["type": fixed("repeat"), "props": repeatProps, "children": array(.component, 2, minimum: 1)]) { _, rhs in rhs })]
    }
}
