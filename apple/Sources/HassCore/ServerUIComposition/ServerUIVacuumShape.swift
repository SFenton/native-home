import Foundation

// MARK: - Closed vacuum grammar

extension ServerUICompositionShape {
    static let vacuumDescriptor: Shape = {
        let entity = Shape.text(160, blank: false)
        let sensor = entity
        let pair = object(["roomId": id, "entityId": entity])
        let focus = object([
            "maximumViewAreaRatio": .optional(.number(0, 1, integer: false)),
            "minimumExcludedAreaM2": .optional(.number(0, 1_000_000, integer: false)),
            "minimumExcludedFraction": .optional(.number(0, 1, integer: false)),
            "paddingCm": .optional(.number(0, 100_000, integer: false)),
            "requiredSegments": array(object(["id": .text(80, blank: false), "name": .optional(title)]), 64, minimum: 1),
            "wallAssociationCm": .optional(.number(0, 100_000, integer: false))
        ])
        return object([
            "title": title, "entityId": entity, "batteryEntityId": sensor, "cleanScript": entity,
            "errorEntityId": sensor, "passesEntityId": entity, "statusEntityId": sensor, "statusFlagEntityId": sensor,
            "vacuumMapId": .text(120, blank: false), "mapRotationDegrees": .number(-360, 360, integer: false),
            "mapScale": .number(0.01, 10, integer: false), "mapRoomSelection": .bool,
            "coordinatorSessionEntityId": .optional(sensor), "dockButtonEntityId": .optional(entity),
            "fanEntityId": .optional(entity), "modeEntityId": .optional(entity),
            "modeTextEntityId": .optional(entity), "waterEntityId": .optional(entity),
            "dockControls": .optional(object([
                "cleanScript": entity, "dryScript": entity, "dockStatusEntityId": sensor, "mopAttachmentEntityId": entity
            ])),
            "areaCleaning": .optional(object([
                "minimumSizeCm": .number(1, 100_000, integer: false), "script": entity
            ])),
            "mapFocus": .optional(focus),
            "consumables": array(object([
                "title": title, "entityId": entity, "icon": .text(80, blank: false), "kind": .choice(["duration", "status"])
            ]), 64),
            "autoCleanDisabledRooms": array(object(["title": title, "entityId": entity, "icon": .text(80, blank: false)]), 64),
            "autoCleanControl": .optional(object(["title": title, "entityId": entity, "kind": .choice(["automation", "pause"])])),
            "outcomeRoomNames": array(object(["roomId": id, "name": title]), 128), "outcomeReconciliations": array(pair, 128),
            "zoneDescription": array(title, 16),
            "zones": array(object([
                "title": title, "entityId": entity, "icon": .text(80, blank: false),
                "mapName": .optional(title), "mopRequired": .optional(.bool), "mopRequiredEntityId": .optional(sensor)
            ]), 64)
        ])
    }()

    static let vacuumPrimitive: Shape = {
        let destination = Shape.variant("type", [
            "push": push,
            "present": object(["type": fixed("present"), "modalId": id, "arguments": arguments, "ifPresented": fixed("reject")])
        ])
        let exit = Shape.variant("type", [
            "back": object(["type": fixed("back")]),
            "dismiss": object(["type": fixed("dismiss"), "scope": fixed("current-modal")])
        ])
        func primitive(_ kind: String, _ fields: [String: Shape] = [:]) -> Shape {
            object(["kind": fixed(kind)].merging(fields, uniquingKeysWith: { _, next in next }))
        }
        return .variant("kind", [
            "card": primitive("card", [
                "icon": symbol, "commands": array(.choice(["start_pause", "dock"]), 2),
                "destination": destination
            ]),
            "map": primitive("map", [
                "overlay": .choice(["rooms", "autoClean"]), "height": .number(100, 800, integer: false),
                "runtimeHeight": .number(100, 800, integer: false), "label": title,
                "loadingText": title, "unavailableText": title, "locate": .bool
            ]),
            "status": primitive("status", ["metric": .choice(["status", "battery", "dock"])]),
            "notices": primitive("notices"),
            "auto-clean": primitive("auto-clean"),
            "settings": primitive("settings", ["rows": array(object([
                "role": .choice(["mode", "fan", "water", "passes"]), "title": label, "hint": title
            ]), 4, minimum: 1)]),
            "command": primitive("command", ["command": .choice([
                "clean", "cleanArea", "dock", "stop", "resume", "cancelResume", "pause", "cancelSession",
                "cleanDock", "stopDockClean", "dryMops", "stopDrying", "emptyBin"
            ]), "icon": symbol]),
            "choice": primitive("choice", ["entityId": .text(160, blank: false), "selection": .choice(["rooms", "autoClean"])]),
            "consumable": primitive("consumable", ["entityId": .text(160, blank: false)]),
            "report": primitive("report", ["destination": destination]), "outcomes": primitive("outcomes"),
            "target": primitive("target", ["mode": .choice(["rooms", "area"]), "icon": symbol, "destination": destination]),
            "clear-area": primitive("clear-area", ["icon": symbol]),
            "area-editor": primitive("area-editor", [
                "height": .number(320, 1_000, integer: false), "onUse": exit, "discardLabel": label, "onDiscard": exit
            ])
        ])
    }()
}
