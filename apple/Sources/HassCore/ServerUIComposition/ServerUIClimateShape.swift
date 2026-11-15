import Foundation

// MARK: - Closed climate grammar

extension ServerUICompositionShape {
    static let climateInputs: Shape = {
        object([
            "entityId": .text(160, blank: false),
            "rangeCommitEntityIds": array(.text(160, blank: false), 64),
            "actionEntityId": .optional(.text(160, blank: false)),
            "sensorEntityId": .optional(.text(160, blank: false)),
            "occupancyEntityId": .optional(.text(160, blank: false)),
            "effectiveAway": .optional(object([
                "ecoEntityId": .text(160, blank: false), "modeEntityId": .text(160, blank: false),
                "fallbackEntityId": .text(160, blank: false)
            ])),
            "trackingGate": .optional(object([
                "selectedEntityId": .text(160, blank: false),
                "criticalEntityId": .optional(.text(160, blank: false)),
                "criticalOption": .optional(title),
                "trackedEntityId": .optional(.text(160, blank: false))
            ])),
            "homeAway": .optional(object([
                "modeEntityId": .text(160, blank: false), "reasonEntityId": .text(160, blank: false),
                "fallbackEntityId": .text(160, blank: false), "vacationEntityId": .text(160, blank: false)
            ])),
            "tracking": .optional(object([
                "policyEntityId": .text(160, blank: false), "criticalOption": title,
                "rooms": array(object([
                    "selectedEntityId": .text(160, blank: false), "criticalEntityId": .text(160, blank: false),
                    "occupiedOnlyEntityId": .text(160, blank: false)
                ]), 64, minimum: 1)
            ]))
        ])
    }()

    static let climateProps: Shape = {
        let choice = object([
            "value": label, "label": label, "icon": .text(80, blank: false), "detail": .text(2_000, blank: true)
        ])
        var variants: [String: Shape] = [:]
        for kind in ServerUIClimateControl.Kind.allCases {
            var fields: [String: Shape] = [
                "kind": fixed(kind.rawValue), "sourceId": id, "icon": .text(80, blank: false),
                "hint": .text(2_000, blank: true), "loadingText": title,
                "unavailableText": title, "errorText": title
            ]
            switch kind {
            case .dial:
                fields["dial"] = object([
                    "minimum": .number(-100, 200, integer: false), "maximum": .number(-100, 200, integer: false),
                    "step": .number(0.01, 10, integer: false), "unit": .choice(["°F", "°C"]),
                    "size": .choice(["page", "modal", "compact"])
                ])
            case .mode, .fan, .preset, .options:
                fields["choices"] = array(choice, 64, minimum: 1)
            case .hub:
                fields["hub"] = object([
                    "modeLabel": label, "fanLabel": label, "modes": array(choice, 64, minimum: 1), "fans": array(choice, 64)
                ])
            case .notice:
                fields["notice"] = object([
                    "useEffectiveMode": .bool, "isWarning": .bool,
                    "awayText": .text(2_000, blank: false), "vacationText": .text(2_000, blank: false),
                    "unknownText": title, "unavailableModeText": title, "reasonFallback": .text(2_000, blank: false),
                    "separator": .text(80, blank: true)
                ])
            case .status:
                fields["presentation"] = .optional(.choice(["row", "metric", "headline", "paragraphs"]))
                fields["status"] = climateStatus
            case .link:
                fields["status"] = climateStatus
            case .roomTile:
                fields["paletteIndex"] = .optional(.number(0, 255, integer: true))
            case .explicitSwitch:
                fields["status"] = .optional(climateStatus)
            case .toggle, .check: break
            }
            variants[kind.rawValue] = object(fields)
        }
        return .variant("kind", variants)
    }()

    static let climateStatus: Shape = {
        object([
            "projection": .choice(["state", "action", "temperature", "occupancy", "vent", "recommendation", "reason",
                                   "indoor", "predicted", "comfortLow", "comfortHigh", "forecastLow", "forecastHigh", "weather", "adjustment",
                                   "comfortBand", "forecastRange", "explanation", "predictive",
                                   "trackingSelected", "trackingCritical", "trackingOccupiedOnly"]),
            "unit": .choice(["°F", "°C"]),
            "states": array(object(["state": label, "text": title]), 64),
            "fallbackText": title
        ])
    }()
}
