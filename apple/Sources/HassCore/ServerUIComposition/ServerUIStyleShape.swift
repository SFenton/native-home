import Foundation

// MARK: - Closed grammar of the style parts

/// The closed shapes of the four style capabilities (`sh.text-style@1`, `sh.stack@1`, `sh.symbol-part@1`, `sh.choice-icons@1`), kept
/// apart from ``ServerUICompositionShape``'s tables so the lanes that extend those tables do not collide. Each is referenced from one
/// line of the table it extends.
extension ServerUICompositionShape {
    // MARK: Ink

    /// An exact colour with an opacity: the channels of a `solid-rgb`, and `alpha` from 0 (clear) to 1 (opaque).
    static let rgbaFill: Shape = object([
        "type": fixed("rgba"), "red": .number(0, 255, integer: true), "green": .number(0, 255, integer: true),
        "blue": .number(0, 255, integer: true), "alpha": .number(0, 1, integer: false)
    ])

    /// One colour for each appearance, in a slot `sh.text-style@1` adds: each side is a `solid-rgb` or an `rgba`.
    static let inkAppearance: Shape = {
        let side = Shape.variant("type", ["solid-rgb": solidFill, "rgba": rgbaFill])
        return object(["type": fixed("solid-appearance"), "light": side, "dark": side])
    }()

    /// The colour of a slot `sh.text-style@1` adds: an exact colour with or without opacity, or one for each appearance. Slots that existed
    /// before keep ``exactSolid``.
    static let inkSlot: Shape = .variant("type", ["solid-rgb": solidFill, "rgba": rgbaFill, "solid-appearance": inkAppearance])

    // MARK: Text

    /// The fields a text carries beyond its value and style (`sh.text-style@1`), each optional.
    static let textLookFields: [String: Shape] = [
        "font": .optional(object([
            "weight": .optional(.choice(ServerUITextLook.Weight.allCases.map(\.rawValue))),
            "digits": .optional(.choice(ServerUITextLook.Digits.allCases.map(\.rawValue))),
            "scale": .optional(object([
                "points": .number(8, 160, integer: false), "relativeTo": .choice(ServerUITextSize.allCases.map(\.rawValue)),
                "maxPoints": .optional(.number(8, 240, integer: false))
            ]))
        ])),
        "ink": .optional(inkSlot), "lines": .optional(.number(0, 12, integer: true)),
        "align": .optional(.choice(ServerUITextLook.Align.allCases.map(\.rawValue))),
        "overflow": .optional(.choice(ServerUITextLook.Overflow.allCases.map(\.rawValue)))
    ]

    // MARK: Choice options

    /// One option of a local choice: its words, and for a segmented choice a symbol and a hint (`sh.choice-icons@1`).
    static let choiceOption: Shape = object(["id": id, "label": label, "symbol": .optional(symbol), "hint": .optional(.text(240, blank: false))])

    // MARK: Stack, shape and symbol nodes

    private static let alignment = Shape.choice(ServerUIStack.Align.allCases.map(\.rawValue))
    private static let line: Shape = object(["ink": inkSlot, "width": .number(0.5, 4, integer: false)])
    private static let stackGroup: Shape = object([
        "children": array(id, 16, minimum: 1), "spacing": .optional(space),
        "distribution": .optional(.choice(ServerUIStack.Distribution.allCases.map(\.rawValue))), "align": .optional(alignment),
        "grow": .optional(.bool)
    ])
    private static let stackProps: Shape = object([
        "axis": .choice(ServerUIStack.Axis.allCases.map(\.rawValue)), "spacing": space, "padding": .optional(insets),
        "align": .optional(alignment), "distribution": .optional(.choice(ServerUIStack.Distribution.allCases.map(\.rawValue))),
        "groups": .optional(array(stackGroup, 16)),
        "collapse": .optional(object([
            "to": fixed("vertical"), "when": array(.choice(ServerUIStack.Trigger.allCases.map(\.rawValue)), 2, minimum: 1),
            "fits": .optional(array(id, 16)), "spacing": .optional(space), "groups": .optional(array(stackGroup, 16))
        ])),
        "dividers": .optional(line),
        "surface": .optional(.variant("type", [
            "module": object(["type": fixed("module"), "density": .choice(ServerUIStack.Density.allCases.map(\.rawValue))]),
            "fill": object([
                "type": fixed("fill"), "fill": inkSlot, "border": .optional(line),
                "radius": .optional(.variant("type", [
                    "token": object(["type": fixed("token"), "name": fixed("tile")]),
                    "points": object(["type": fixed("points"), "value": .number(0, 64, integer: false)])
                ]))
            ])
        ]))
    ])
    private static let stackAccessibility: Shape = object([
        "element": .choice(ServerUIStack.Accessibility.Element.allCases.map(\.rawValue)),
        "role": .optional(.choice(ServerUIStack.Accessibility.Role.allCases.map(\.rawValue))),
        "label": .optional(textValue(.text(240, blank: false))), "value": .optional(textValue(.text(240, blank: true))),
        "hint": .optional(.text(240, blank: false))
    ])

    /// The nodes `sh.stack@1` and `sh.symbol-part@1` add, over the fields every node has.
    static func styleNodes(base: [String: Shape]) -> [String: Shape] {
        func node(_ type: String, _ extra: [String: Shape]) -> Shape {
            object(base.merging(["type": fixed(type)]) { _, rhs in rhs }.merging(extra) { _, rhs in rhs })
        }
        return [
            "stack": node("stack", [
                "props": stackProps, "action": .optional(ruledAction), "a11y": .optional(stackAccessibility),
                "children": array(.component, 100)
            ]),
            "shape": node("shape", [
                "props": object(["form": .choice(ServerUIShapePart.Form.allCases.map(\.rawValue)),
                                 "width": .number(1, 1_024, integer: false), "height": .number(1, 1_024, integer: false), "fill": inkSlot])
            ]),
            "symbol": node("symbol", [
                "props": object([
                    "name": symbolSlot,
                    "size": object(["points": .number(8, 160, integer: false),
                                    "relativeTo": .optional(.choice(ServerUITextSize.allCases.map(\.rawValue))),
                                    "maxScale": .optional(.number(1, 4, integer: false))]),
                    "rendering": .choice(ServerUISymbolPart.Rendering.allCases.map(\.rawValue)), "tint": .optional(inkSlot),
                    "trim": .optional(.choice(ServerUISymbolPart.Trim.allCases.map(\.rawValue))), "rotate": .optional(operand)
                ]),
                "a11y": .variant("element", [
                    "hidden": object(["element": fixed("hidden")]),
                    "image": object(["element": fixed("image"), "label": textValue(.text(240, blank: false))])
                ])
            ])
        ]
    }
}
