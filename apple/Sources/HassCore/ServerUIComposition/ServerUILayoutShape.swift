import Foundation

// MARK: - Layout grammar (L3)

/// The closed shapes of the layout capabilities: tab areas and bar, overlay, tile parts and look, and badges.
///
/// They are kept apart from ``ServerUICompositionShape``'s tables so the lanes that extend those tables do not collide. Each is
/// referenced from one line of the table it extends.
extension ServerUICompositionShape {
    /// A badge (`sh.badges@1`): none, or a value that is a number or text. The compiler checks the value's kind.
    static let badge: Shape = {
        .variant("type", ["none": object(["type": fixed("none")]),
                          "value": object(["type": fixed("value"), "value": operand])])
    }()

    /// A node's `layout`: its column span is optional, and unset leaves the width to the grid (`layout.span`).
    static let layoutSpan: Shape = object(["span": .optional(.number(1, 4, integer: true))])

    /// `props.tabBar` of a tab container (`sh.tab-bar@1`).
    static let tabBar: Shape = {
        object(["placement": .choice(["bottom", "top"]),
                "labels": .choice(["by-size", "icons", "titles", "icons-and-titles"])])
    }()

    /// One area of a tab container (`sh.tab-blocks@1`).
    static let tabBlock: Shape = {
        object(["id": id,
                "tabs": .allOrIdentifiers(5),
                "visibleWhen": .optional(predicate), "whenUnknown": .optional(whenUnknown),
                "children": array(.component, 100)])
    }()

    /// Fields every tab of a container may carry beyond the shipped ones.
    static let tabRule: [String: Shape] = ["visibleWhen": .optional(predicate), "whenUnknown": .optional(whenUnknown)]

    /// The overlay node's own fields (`sh.overlay@1`).
    static let overlayFields: [String: Shape] = [
        "props": object(["anchors": array(object(["childId": id,
            "anchor": .choice(["top-leading", "top-trailing", "bottom-leading", "bottom-trailing", "center"]),
            "inset": space]), ServerUIOverlay.maximumOnTop)]),
        "children": array(.component, ServerUIOverlay.maximumOnTop + 1)
    ]

    /// A state tile's own parts (`sh.tile-parts@1`) in `props`.
    static let tileParts: Shape = {
        object(["subtitle": .optional(value(literal: .text(2_000, blank: true))),
                "progress": .optional(operand),
                "discs": .optional(array(object(["id": id, "icon": symbol, "label": label, "action": action,
                                                 "visibleWhen": .optional(predicate), "whenUnknown": .optional(whenUnknown)]),
                                         ServerUITileParts.maximumDiscs))])
    }()

    /// The fields a state tile carries beyond its binding: a destination, the three face conditions and a badge.
    static let stateTileFields: [String: Shape] = [
        "action": .optional(navigationAction),
        "activeWhen": .optional(predicate), "filledWhen": .optional(predicate), "errorWhen": .optional(predicate),
        "badge": .optional(badge)
    ]
}
