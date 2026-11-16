import Foundation

// MARK: - Closed bedroom shape

extension ServerUICompositionShape {
    static let bedroomSource: Shape = {
        object([
            "id": id, "kind": fixed("model"), "model": fixed("bedroom-provider@1"),
            "inputs": object([
                "providerId": id,
                "kind": .choice(ServerUIBedroomControl.ProviderKind.allCases.map(\.rawValue))
            ])
        ])
    }()

    static let bedroomControl: Shape = {
        .variant("control", Dictionary(uniqueKeysWithValues: ServerUIBedroomControl.Kind.allCases.map { kind in
            var fields: [String: Shape] = [
                "control": fixed(kind.rawValue), "sourceId": id, "label": title, "unavailableText": title
            ]
            if kind == .stage { fields["parameter"] = .choice(SchedulePhase.allCases.map(\.rawValue)) }
            if kind == .bedTarget { fields["parameter"] = .choice(["left", "right"]) }
            if kind == .wakeHold { fields["showsExplanation"] = .optional(.bool) }
            if kind == .name || kind == .alarmKind { fields["showsHeading"] = .optional(.bool) }
            if kind == .feedback { fields["parameter"] = .choice(["error", "problems"]) }
            if kind == .wakeStop {
                fields["episode"] = .optional(object([
                    "heading": title, "detail": .text(2_000, blank: true), "pendingLabel": title
                ]))
            }
            if kind.usesNavigation { fields["action"] = navigationAction }
            if kind == .reading { fields["parameter"] = .choice(ServerUIBedroomControl.readings) }
            if kind == .mode || kind == .power { fields["activeLabel"] = title }
            if kind == .mode {
                fields["icon"] = symbol
                fields["family"] = .choice(["neutral", "lights", "cooling", "heating"])
                fields["inactiveLabel"] = title
                fields["countdownSuffix"] = title
            }
            if kind == .reading {
                fields["activeLabel"] = .optional(title)
                fields["inactiveLabel"] = .optional(title)
            }
            if kind.usesOptions {
                var option: [String: Shape] = [
                    "value": .choice(ServerUIBedroomControl.allowedOptions(kind)), "label": title
                ]
                if kind == .weekdays { option["accessibilityLabel"] = .optional(title) }
                fields["options"] = array(object(option), 16, minimum: 1)
            }
            if kind.usesConfirmation {
                var question: [String: Shape] = [
                    "title": title, "message": .text(2_000, blank: true),
                    "confirmLabel": title, "cancelLabel": title
                ]
                if kind == .delete { question["messageFormat"] = .optional(.choice(["wake-alarm"])) }
                fields["confirmation"] = object(question)
            }
            if kind.usesScope {
                fields["scope"] = object([
                    "title": title, "message": .text(2_000, blank: true),
                    "tonightLabel": title, "allNightsLabel": title, "cancelLabel": title
                ])
            }
            return (kind.rawValue, object(fields))
        }))
    }()
}
