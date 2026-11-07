import HassCore
import HassDesign

/// Maps the humidifier onto the shared dial (web `HumidifierHero`, `TargetHumidityDial` and the schedule editor's
/// dials over `SingleValueCircularDial`).
@MainActor
enum HumidifierDials {
    /// Comfort (40–50%) and condensation-risk (60–80%) bands on target humidity dials.
    static let humidityTrails = [
        DialTrail(id: "comfort", from: 40, to: 50, tint: RoomDeviceStyle.comfortTrail),
        DialTrail(id: "high", from: 60, to: 80, tint: RoomDeviceStyle.highTrail),
    ]

    /// The hero mist dial: 0 (off) to 9; `Off` or `Sleep` replace the number; read-only in Sleep or with a fault.
    static func mist(_ humidifier: HumidifierController) -> ThermostatDialConfiguration {
        let powerOn = humidifier.powerOn
        let readout: String? = humidifier.isSleep ? "Sleep" : powerOn ? nil : "Off"
        let current = powerOn && !humidifier.isBlocked ? humidifier.currentMistLevel : nil
        let humidity = "\(humidifier.humidityText) current"
        let caption: ThermostatDialConfiguration.TargetCaption
        if !powerOn {
            caption = .hidden
        } else if let level = humidifier.currentMistLevel {
            caption = .custom("Level \(level) • \(humidity)")
        } else {
            caption = .custom(humidity)
        }
        var spokenReadout = "Humidifier mist level \(readout ?? String(humidifier.mistLevel))"
        if powerOn, let current { spokenReadout += ", output level \(current)" }
        return ThermostatDialConfiguration(
            title: humidifier.config.title,
            min: Double(HumidifierController.mistRange.lowerBound), max: Double(HumidifierController.mistRange.upperBound), step: 1,
            current: current.map(Double.init),
            targets: .single(Double(powerOn ? humidifier.mistLevel : 0)),
            action: "idle", unit: "",
            isUnavailable: humidifier.isUnavailable, isOff: !powerOn, isInteractive: humidifier.canSetLevel,
            actionTextOverride: "Mist Level", primaryValueOverride: readout, primaryUnitOverride: .some(nil),
            targetCaption: caption, inactiveOverride: !powerOn || humidifier.isSleep,
            valueStyle: DialValueStyle(
                tint: RoomDeviceStyle.humidifierTint, handleLabel: "Mist level",
                readoutLabel: spokenReadout
            )
        )
    }

    /// The Auto Humidity target: 40–80% in 5% steps with the current humidity marked.
    static func target(_ humidifier: HumidifierController) -> ThermostatDialConfiguration {
        targetDial(title: humidifier.config.title, value: humidifier.targetHumidity,
                   current: humidifier.isBlocked ? nil : humidifier.currentHumidity,
                   caption: "\(humidifier.humidityText) current", isInteractive: !humidifier.isBlocked,
                   handleLabel: "Target humidity",
                   readoutLabel: "Target humidity \(humidifier.targetHumidity)%, \(humidifier.humidityText) current")
    }

    /// A schedule editor's target humidity.
    static func scheduledTarget(_ value: Int) -> ThermostatDialConfiguration {
        targetDial(title: "Scheduled activity", value: value, current: nil, caption: nil, isInteractive: true,
                   handleLabel: "Scheduled target humidity", readoutLabel: "Scheduled target humidity \(value)%")
    }

    /// A schedule editor's mist level, 1–9.
    static func scheduledMist(_ value: Int) -> ThermostatDialConfiguration {
        ThermostatDialConfiguration(
            title: "Scheduled activity", min: 1, max: 9, step: 1, current: nil, targets: .single(Double(value)),
            action: "idle", unit: "", actionTextOverride: "Mist Level", primaryUnitOverride: .some(nil), targetCaption: .hidden,
            valueStyle: DialValueStyle(tint: RoomDeviceStyle.humidifierTint, handleLabel: "Scheduled mist level",
                                       readoutLabel: "Scheduled mist level \(value)")
        )
    }

    private static func targetDial(title: String, value: Int, current: Double?, caption: String?, isInteractive: Bool,
                                   handleLabel: String, readoutLabel: String) -> ThermostatDialConfiguration {
        ThermostatDialConfiguration(
            title: title,
            min: Double(HumidifierController.targetRange.lowerBound), max: Double(HumidifierController.targetRange.upperBound),
            step: Double(HumidifierController.targetStep),
            current: current, targets: .single(Double(value)), action: "idle", unit: "%",
            isInteractive: isInteractive,
            actionTextOverride: "Target Humidity",
            targetCaption: caption.map { .custom($0) } ?? .hidden,
            valueStyle: DialValueStyle(tint: RoomDeviceStyle.humidifierTint, handleLabel: handleLabel, spokenUnit: "percent",
                                       readoutLabel: readoutLabel, trails: humidityTrails)
        )
    }
}
