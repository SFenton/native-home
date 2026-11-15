import Foundation

// MARK: - Closed security grammar

extension ServerUICompositionShape {
    static let securityConfirmation: Shape = {
        object(["title": title, "message": .text(2_000, blank: false),
                "confirmLabel": title, "cancelLabel": fixed("Cancel")])
    }()
    static let alarmPanelProps: Shape = {
        object([
            "sourceId": id,
            "modes": array(object([
                "state": .choice(["disarmed", "armed_home", "armed_away", "armed_night"]),
                "label": label, "hint": title, "icon": symbol, "fill": solidFill
            ]), 4, minimum: 1),
            "states": array(object([
                "state": .choice(["disarmed", "armed_home", "armed_away", "armed_night", "armed_vacation",
                                  "armed_custom_bypass", "triggered", "arming", "pending", "disarming"]),
                "appearance": alarmAppearance
            ]), 10),
            "fallback": alarmAppearance, "subtitle": title, "sincePrefix": .text(80, blank: true),
            "separator": .text(80, blank: true), "loadingText": title, "unavailableText": title,
            "hiddenText": title, "errorText": title, "pendingText": title,
            "confirmation": securityConfirmation, "triggeredWash": solidFill
        ])
    }()
    static let doorTileProps: Shape = {
        object([
            "sourceId": id, "kind": .choice(["lock", "garage"]),
            "states": array(object([
                "state": .choice(["locked", "unlocked", "locking", "unlocking", "open", "jammed",
                                  "closed", "opening", "closing"]),
                "appearance": alarmAppearance, "active": .bool, "error": .bool
            ]), 9),
            "fallback": alarmAppearance, "loadingText": title, "unavailableText": title,
            "hiddenText": title, "errorText": title, "sendingOpenText": title, "sendingCloseText": title,
            "openLabel": label, "closeLabel": label, "reverseLabel": label
        ])
    }()
}
