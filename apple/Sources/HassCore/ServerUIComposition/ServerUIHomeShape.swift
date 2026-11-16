import Foundation

// MARK: - Closed Home grammar

extension ServerUICompositionShape {
    static let homeNavigationAction: Shape = {
        .variant("type", [
            "push": push,
            "select-tab": object(["type": fixed("select-tab"), "tabId": id]),
            "present": object(["type": fixed("present"), "modalId": id, "arguments": arguments, "ifPresented": fixed("reject")]),
            "dismiss-then-push": object(["type": fixed("dismiss-then-push"), "destination": push])
        ])
    }()

    static let homeStatusSource: Shape = {
        object([
            "id": id, "kind": fixed("model"), "model": fixed("home-status@1"),
            "inputs": object([
                "projection": .choice(["lights", "climate", "occupancy", "contacts", "air-quality", "entity"]),
                "format": .choice(["summary", "room", "item", "detail"]),
                "entityIds": array(literalEntity, 128),
                "rangeEntityId": .optional(literalEntity), "secondaryEntityId": .optional(literalEntity),
                "alarmEntityId": .optional(literalEntity), "awayEntityIds": array(literalEntity, 16),
                "colorEntityId": .optional(literalEntity),
                "members": .optional(array(object([
                    "entityId": literalEntity, "title": title,
                    "contactCount": .number(1, 128, integer: true), "contactKind": .choice(["door", "window"])
                ]), 128))
            ]),
            "labels": object([
                "idle": title, "active": title, "countSuffix": .text(80, blank: true),
                "loading": title, "unavailable": title, "empty": title, "hidden": title
            ])
        ])
    }()
    static let homeWeatherSource: Shape = {
        object([
            "id": id, "kind": fixed("model"), "model": fixed("home-weather@1"),
            "inputs": object([
                "weatherEntityId": literalEntity, "sunEntityId": .optional(literalEntity),
                "airQualityEntityId": .optional(literalEntity), "units": fixed("source@1")
            ])
        ])
    }()
    static let homeLightSource: Shape = {
        object(["id": id, "kind": fixed("model"), "model": fixed("home-light@1"),
                "inputs": object(["entityId": literalEntity, "memberEntityIds": .optional(array(literalEntity, 64))])])
    }()
    static let statusAppearance: Shape = {
        object(["icon": symbolSlot, "glyph": .optional(solidSlot), "fill": fillSlot])
    }()
    /// A home navigation action, or one chosen by rule (`sh.action-rules@1`).
    static let ruledHomeNavigationAction: Shape = {
        guard case .variant(let key, let variants) = homeNavigationAction else { return homeNavigationAction }
        let choice = Shape.variant(key, variants.merging(["none": object(["type": fixed("none")])]) { $1 })
        return .variant(key, variants.merging(["conditional": object([
            "type": fixed("conditional"), "cases": array(object(["when": predicate, "then": homeNavigationAction]), 16, minimum: 1),
            "otherwise": choice])]) { $1 })
    }()
    static let statusProps: [String: Shape] = {
        [
            "sourceId": id, "states": array(object([
                "state": .text(80, blank: false), "appearance": statusAppearance, "text": .optional(title)
            ]), 32), "fallback": statusAppearance, "announcement": .choice(["none", "value-change"])
        ]
    }()
    static let weatherProps: Shape = {
        object([
            "sourceId": id, "panel": .choice(["summary", "hero", "briefing", "hourly", "daily", "highlights"]),
            "modes": array(.choice(["condition", "precipitation", "wind"]), 3, minimum: 1),
            "initialMode": .choice(["condition", "precipitation", "wind"]),
            "highlights": array(.choice(["aqi", "precipitation", "accumulation", "humidity", "cloud",
                                         "feels", "uv", "wind", "sun", "visibility", "pressure"]), 11),
            "compactHours": .number(1, 12, integer: true), "regularHours": .number(1, 12, integer: true),
            "labels": object(["loading": title, "empty": title, "stale": title, "error": title, "open": title])
        ])
    }()
}
