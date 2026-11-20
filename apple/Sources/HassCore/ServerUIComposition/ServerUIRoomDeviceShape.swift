import Foundation

// MARK: - Closed room-device grammar

extension ServerUICompositionShape {
    static func roomDeviceSource(_ model: String) -> Shape {
        var inputs = ServerUIRoomDeviceDescriptor.domains(model).mapValues { _ in Shape.text(160, blank: false) }
        switch model {
        case "air-purifier@1": inputs["roomTitle"] = title
        case "bathroom-fan@1":
            inputs.merge(["id": id, "roomTitle": title, "scriptService": .text(160, blank: false)]) { _, next in next }
        case "grill@1":
            inputs.merge(["title": title, "roomTitle": title,
                          "details": array(object(["title": title, "entityId": .text(160, blank: false),
                                                   "icon": .text(80, blank: false)]), 32, minimum: 1)]) { _, next in next }
        default:
            inputs.merge(["id": id, "title": title, "scheduleId": .text(160, blank: false),
                          "applyProfileScriptService": .text(160, blank: false),
                          "setLevelScriptService": .text(160, blank: false)]) { _, next in next }
        }
        return object(["id": id, "kind": fixed("model"), "model": fixed(model), "inputs": object(inputs)])
    }

    static let roomDeviceControl: Shape = {
        let option = object(["value": .text(80, blank: false), "label": label,
                             "actionLabel": .optional(title)])
        let labels = object([
            "loading": title, "unavailable": title, "failed": title, "on": title, "off": title,
            "action": title, "cancel": title, "footnote": .text(2_000, blank: true),
            "sleep": title, "tankFault": title, "waterFault": title, "invalidTarget": title, "highTarget": title
        ])
        return object([
            "id": id, "title": title, "type": fixed("room-device-control"),
            "layout": object(["span": .number(1, 4, integer: true), "foldSide": .optional(foldSide)]), "icon": symbol,
            "binding": object(["sourceId": id]),
            "props": object([
                "control": .choice(ServerUIRoomDeviceControl.Kind.allCases.map(\.rawValue)),
                "family": .choice(["neutral", "air", "security", "cooking", "water"]),
                "options": array(option, 12), "labels": labels,
                "detailEntityId": .optional(.text(160, blank: false)),
                "info": .optional(.choice(ServerUIRoomDeviceControl.Info.allCases.map(\.rawValue))),
                "initialMinutes": .optional(.number(5, 60, integer: true)),
                "modalId": .optional(id),
                "fanRail": .optional(object([
                    "order": array(.choice(["lock", "power"]), 2, minimum: 2),
                    "powerIcon": symbol, "lockedIcon": symbol, "unlockedIcon": symbol,
                    "powerOn": title, "powerOff": title, "lock": title, "unlock": title, "locked": title
                ]))
            ])
        ])
    }()
}
