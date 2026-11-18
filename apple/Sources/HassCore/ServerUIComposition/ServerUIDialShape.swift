import Foundation

// MARK: - Closed grammar of the dial and the arc track

/// The closed shapes of the `dial` (`sh.dial@1`) and `arc-track` (`sh.arc-track@1`) nodes, kept apart from ``ServerUICompositionShape``'s tables so
/// the lanes that extend those tables do not collide. They follow the Studio's `schema.ts` (`dialNode`, `arcTrackNode`) field for field.
extension ServerUICompositionShape {
    private static let dialShare: Shape = .number(0, 1, integer: false)
    private static let arcPoint: Shape = array(.number(0, 1000, integer: false), 2, minimum: 2)

    private static let dialTicks: Shape = object([
        "count": .number(2, 120, integer: true), "inner": dialShare, "outer": dialShare, "width": .number(0.5, 6, integer: false), "ink": inkSlot,
        "alternate": .optional(object(["inner": dialShare])), "skip": .optional(array(.number(0, 119, integer: true), 8))
    ])

    private static let dialPointer: Shape = .variant("kind", [
        "tick": object([
            "kind": fixed("tick"), "value": operand, "inner": dialShare, "outer": dialShare, "width": .number(0.5, 8, integer: false), "ink": inkSlot
        ]),
        "needle": object([
            "kind": fixed("needle"), "value": operand, "ink": inkSlot, "tailInk": inkSlot, "dotInk": inkSlot, "animates": .optional(.bool)
        ])
    ])

    /// One line in the middle of a dial: the props of a `text`.
    private static let dialLine: Shape = object([
        "value": textValue(.text(16_384, blank: true)),
        "style": .choice(ServerUICompositionDocument.TextStyle.allCases.map(\.rawValue)),
        "unavailableText": .text(16_384, blank: false)
    ].merging(textLookFields) { _, rhs in rhs })

    private static let meterAccessibility: Shape = .variant("element", [
        "hidden": object(["element": fixed("hidden")]),
        "value": object(["element": fixed("value"), "label": textValue(.text(240, blank: false)),
                         "value": .optional(textValue(.text(240, blank: true)))])
    ])

    /// The nodes `sh.dial@1` and `sh.arc-track@1` add, over the fields every node has.
    static func dialNodes(base: [String: Shape]) -> [String: Shape] {
        func node(_ type: String, _ extra: [String: Shape]) -> Shape {
            object(base.merging(["type": fixed(type)]) { _, rhs in rhs }.merging(extra) { _, rhs in rhs })
        }
        return [
            "dial": node("dial", [
                "props": object([
                    "sweep": object(["start": .number(-360, 360, integer: false), "length": .number(1, 360, integer: false)]),
                    "scale": .optional(.choice(ServerUIDialLayout.Scale.allCases.map(\.rawValue))),
                    "aspect": .optional(.number(0.5, 2, integer: false)), "centerY": .optional(dialShare),
                    "size": .optional(object([
                        "points": .number(16, 512, integer: false),
                        "relativeTo": .optional(.choice(ServerUITextSize.allCases.map(\.rawValue))),
                        "maxPoints": .optional(.number(16, 1_024, integer: false))
                    ])),
                    "maxWidth": .optional(.number(16, 1_024, integer: false)),
                    "ticks": .optional(dialTicks), "pointer": .optional(dialPointer),
                    "labels": .optional(object([
                        "ink": inkSlot,
                        "items": array(object(["at": dialShare, "text": .text(8, blank: false), "needsValue": .optional(.bool)]), 12, minimum: 1)
                    ])),
                    "flag": .optional(object(["at": dialShare, "ink": inkSlot])),
                    "center": .optional(array(dialLine, 3, minimum: 1)),
                    "mirrors": .optional(.bool)
                ]),
                "a11y": meterAccessibility
            ]),
            "arc-track": node("arc-track", [
                "props": object([
                    "curve": object(["from": arcPoint, "control": arcPoint, "to": arcPoint]),
                    "box": array(.number(1, 1_000, integer: false), 2, minimum: 2),
                    "maxWidth": .optional(.number(16, 1_024, integer: false)),
                    "ink": inkSlot, "width": .number(0.5, 8, integer: false),
                    "dash": .optional(array(.number(0.5, 32, integer: false), 2, minimum: 2)),
                    "horizon": .optional(object(["from": arcPoint, "to": arcPoint, "ink": inkSlot, "width": .number(0.5, 8, integer: false)])),
                    "progress": .optional(operand),
                    "scale": .optional(.choice(ServerUIArcLayout.Scale.allCases.map(\.rawValue))),
                    "marker": .optional(object(["size": .number(6, 32, integer: false), "ink": inkSlot])),
                    "mirrors": .optional(.bool)
                ]),
                "a11y": meterAccessibility
            ])
        ]
    }
}
