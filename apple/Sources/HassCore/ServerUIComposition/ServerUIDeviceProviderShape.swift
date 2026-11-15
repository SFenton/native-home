import Foundation

// MARK: - Closed authored controller inputs

extension ServerUICompositionShape {
    static let providerModels = ["media-remote-config@1", "bedroom-config@1", "custom-lights@1", "sprinkler-controller@1"]

    static func deviceProviderSource(_ model: String) -> Shape {
        let inputs: Shape
        switch model {
        case "media-remote-config@1": inputs = remoteConfiguration
        case "bedroom-config@1": inputs = bedroomConfiguration
        case "custom-lights@1": inputs = customLightsConfiguration
        default: inputs = sprinklerConfiguration
        }
        return object(["id": id, "kind": fixed("model"), "model": fixed(model), "inputs": inputs])
    }

    // MARK: - Media remote

    static let providerEntity: Shape = .pattern("^[a-z][a-z0-9_]*\\.[a-z0-9_]+$", 160)
    /// A service name inside an authored call; ``ServerUIServiceVocabulary`` decides which names are allowed.
    static let providerService: Shape = .pattern("^[a-z][a-z0-9_]*$", 160)
    static let providerStates: Shape = array(.text(160, blank: false), 64)
    static let remoteSemantics: Shape = {
        .variant("type", [
            "state": object(["type": fixed("state")]),
            "toggleOnUnless": object(["type": fixed("toggleOnUnless"), "states": providerStates]),
            "toggleOnWhen": object(["type": fixed("toggleOnWhen"), "states": providerStates]),
            "selectedWhen": object(["type": fixed("selectedWhen"), "states": providerStates])
        ])
    }()
    static let remoteCommand: Shape = {
        .variant("type", [
            "textPrompt": object(["type": fixed("textPrompt"), "targetEntityId": providerEntity]),
            "service": object([
                "type": fixed("service"),
                "call": object([
                    "domain": .choice(["script", "remote", "media_player", "input_button", "switch", "select", "input_select"]),
                    "service": providerService, "target": .optional(providerEntity),
                    "data": object([
                        "command": .optional(.text(512, blank: false)), "app_id": .optional(.text(240, blank: false)),
                        "app_name": .optional(title), "entity": .optional(providerEntity),
                        "remote_entity": .optional(providerEntity), "entity_id": .optional(providerEntity),
                        "sonosdevice": .optional(array(providerEntity, 16)),
                        "speakerdevice": .optional(array(providerEntity, 16)), "turn_on_projector": .optional(.bool),
                        "is_volume_muted": .optional(.bool), "source": .optional(title),
                        "option": .optional(title), "volume_level": .optional(.number(0, 1, integer: false))
                    ])
                ]),
                "optimistic": array(object([
                    "entityId": providerEntity, "value": .text(160, blank: false),
                    "revertAfterSeconds": .number(0.1, 300, integer: false), "failsOnTimeout": .bool
                ]), 32)
            ])
        ])
    }()
    static func remoteUsesSpeakerTargets(_ value: JSONValue) -> Bool {
        switch value {
        case .object(let fields): fields["speakerdevice"] != nil || fields.values.contains(where: remoteUsesSpeakerTargets)
        case .array(let values): values.contains(where: remoteUsesSpeakerTargets)
        default: false
        }
    }
    static let remoteAction: Shape = {
        .variant("type", [
            "command": object(["type": fixed("command"), "command": remoteCommand]),
            "state": object(["type": fixed("state"), "entityId": .optional(providerEntity),
                             "cases": array(object(["states": providerStates, "command": remoteCommand]), 32),
                             "otherwise": remoteCommand])
        ])
    }()
    static let remoteButton: Shape = {
        object(["label": title, "icon": .text(80, blank: true), "iconRotationDegrees": .number(-360, 360, integer: false),
                "action": remoteAction, "semantics": .optional(remoteSemantics),
                "iconColorRule": .optional(object([
                    "entityIds": array(providerEntity, 32, minimum: 1), "inactiveStates": providerStates,
                    "inactiveStatesByEntity": .dictionary(providerEntity, providerStates, 32)
                ]))])
    }()
    static let remoteDevice: Shape = {
        object(["title": title, "entityId": providerEntity, "icon": .text(80, blank: false),
                "action": .optional(remoteAction), "activeHoldSeconds": .optional(.number(0, 300, integer: false)),
                "activeHoldResetEntityIds": array(providerEntity, 32), "activeStates": providerStates,
                "semantics": .optional(remoteSemantics), "stateEntityIds": .optional(array(providerEntity, 32, minimum: 1)),
                "stateLabels": .dictionary(.text(160, blank: false), title, 64),
                "stateResolver": .optional(object(["configuredConsole": object([
                    "cloudEntityId": providerEntity, "hdmiEntityId": providerEntity, "tvEntityId": providerEntity,
                    "powerEntityId": providerEntity, "inputEntityId": providerEntity, "activeStates": providerStates,
                    "inputSuffix": label, "linkedState": label
                ])]))])
    }()
    static let remoteConfiguration: Shape = {
        var fields: [String: Shape] = [
            "id": id, "title": title, "roomTitle": title, "remoteTitle": title,
            "mediaEntityId": providerEntity, "controlEntityId": providerEntity,
            "volumeTitle": title, "volumeEntityId": providerEntity,
            "showVolumeWhenOff": .bool, "hideKeyboardWhenOff": .bool, "appSectionTitle": title,
            "optimisticEntityIds": array(providerEntity, 64), "liveChangeEntityIds": array(providerEntity, 64),
            "apps": array(object([
                "title": title, "action": remoteAction, "imagePath": .optional(.pattern("^/local/[A-Za-z0-9_./ -]+$", 512)),
                "icon": .optional(.text(80, blank: false)), "whiteBackground": .bool,
                "stateEntityId": .optional(providerEntity), "activeStates": providerStates, "semantics": .optional(remoteSemantics)
            ]), 64),
            "devices": array(remoteDevice, 64),
            "cards": array(object(["key": id, "configuration": remoteDevice]), 64),
            "lightSync": .optional(object([
                "powerEntityId": providerEntity, "lightSyncEntityId": providerEntity,
                "syncModeEntityId": providerEntity, "intensityEntityId": providerEntity,
                "brightnessEntityId": providerEntity, "hdmiInputEntityId": providerEntity,
                "hdmiStatusEntityIds": array(providerEntity, 4)
            ]))
        ]
        for key in ["power", "up", "left", "select", "right", "down", "back", "home", "pause", "play",
                    "volumeDown", "volumeMute", "volumeUp"] { fields[key] = remoteButton }
        fields["keyboard"] = .optional(remoteButton)
        return object(fields)
    }()
    // MARK: - Bedroom, lights and sprinklers

    static let bedroomConfiguration: Shape = {
        var bed: [String: Shape] = ["id": id, "title": title, "side": .choice(["left", "right"]), "owner": id,
            "stageLevelEntityIds": object(["bedtime": providerEntity, "asleep": providerEntity, "dawn": providerEntity])]
        for key in ["climateEntityId", "targetLevelEntityId", "schedulePhaseEntityId",
                    "alarmStateEntityId", "alarmSnoozeButtonEntityId", "alarmStopButtonEntityId", "hotFlashActiveEntityId",
                    "hotFlashButtonEntityId", "hotFlashCancelButtonEntityId", "hotFlashRestoreAtEntityId", "hotFlashTimerEntityId",
                    "heartRateEntityId", "breathingRateEntityId", "hrvEntityId", "pumpClogEntityId", "pumpStallEntityId",
                    "pumpLoopTemperatureEntityId", "pumpRpmEntityId"] { bed[key] = providerEntity }
        let wake = object(["id": id, "title": title, "roomTitle": title, "statusEntityId": providerEntity,
            "sources": array(object(["id": .text(160, blank: false), "side": .choice(["left", "right"]),
                                    "alarmLabel": title, "alarmsLabel": title, "bedId": id]), 2)])
        return object([
            "wakeProviderId": id, "beds": array(object(["providerId": id, "configuration": object(bed)]), 2, minimum: 1),
            "environment": object(["scheduleEntityId": providerEntity, "householdAwayEntityId": providerEntity, "wakeLight": wake])
        ])
    }()
    static let customLightsConfiguration: Shape = {
        object(["sectionTitle": title, "manualTitle": title, "modeTitle": title,
                "manualEntityId": providerEntity, "modeEntityId": providerEntity, "groupEntityId": providerEntity,
                "customMode": title, "fallbackModes": array(title, 64, minimum: 1),
                "palettes": array(object(["mode": title, "colors": array(object([
                    "red": .number(0, 255, integer: true), "green": .number(0, 255, integer: true),
                    "blue": .number(0, 255, integer: true)]), 64)]), 64),
                "lights": array(object(["title": title, "entityId": providerEntity]), 100, minimum: 1),
                "resetKelvin": .number(1000, 10000, integer: true), "resetBrightness": .number(1, 255, integer: true),
                "resetTransition": .number(0, 3600, integer: true)])
    }()
    static let sprinklerConfiguration: Shape = {
        var controller: [String: Shape] = ["id": id, "title": title,
            "zones": array(object(["historyEntityId": providerEntity, "programEntityId": providerEntity,
                                  "valveEntityId": providerEntity]), 32, minimum: 1)]
        for key in ["batteryEntityId", "faultEntityId", "hubConnectedEntityId", "modeEntityId", "nextWateringEntityId",
                    "rainDelayEntityId", "smartWateringEntityId", "stateEntityId"] { controller[key] = providerEntity }
        return object(["controller": object(controller), "lowBatteryPercent": .number(0, 100, integer: false),
                       "defaultStartTime": .pattern("^([01][0-9]|2[0-3]):[0-5][0-9]$", 5)])
    }()
}
