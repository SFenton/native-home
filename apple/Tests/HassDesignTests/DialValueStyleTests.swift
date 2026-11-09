@testable import HassDesign
import SwiftUI
import Testing

/// The dial's single-value mode for humidity and mist level (web `SingleValueCircularDial`).
struct DialValueStyleTests {
    let style = DialValueStyle(tint: DialTint(red: 48, green: 190, blue: 151), handleLabel: "Target humidity",
                               spokenUnit: "percent", readoutLabel: "Target humidity 50%",
                               trails: [DialTrail(id: "comfort", from: 40, to: 50, tint: DialTint(red: 67, green: 160, blue: 71, opacity: 0.92))])

    func configuration(primary: String? = nil, unavailable: Bool = false, caption: ThermostatDialConfiguration.TargetCaption = .custom("41% current"),
                       style: DialValueStyle? = nil) -> ThermostatDialConfiguration {
        ThermostatDialConfiguration(title: "Humidifier", min: 40, max: 80, step: 5, current: 41, targets: .single(50), action: "idle",
                                    unit: "%", isUnavailable: unavailable, primaryValueOverride: primary, targetCaption: caption,
                                    valueStyle: style ?? self.style)
    }

    @Test func thePrimaryTextFollowsTheSetpoint() {
        let dial = configuration()
        #expect(dial.primaryText(for: .single(65)) == "65")
        #expect(dial.primaryText(for: nil) == "--")
        #expect(configuration(primary: "Off").primaryText(for: .single(65)) == "Off")
        #expect(configuration(unavailable: true).primaryText(for: .single(65)) == "--")
    }

    @Test func thermostatsKeepShowingTheCurrentTemperature() {
        let thermostat = ThermostatDialConfiguration(title: "Office", current: 71.5, targets: .single(72), action: "heating")
        #expect(thermostat.primaryText(for: .single(75)) == "71.5")
        #expect(thermostat.accessibilityLabel(for: .target) == "Office target temperature")
        #expect(thermostat.spokenValue(72) == "72 degrees")
        #expect(thermostat.readoutAccessibilityValue(for: .single(72)) == "set to 72.0°F")
    }

    @Test func voiceOverUsesTheStyleWording() {
        let dial = configuration()
        #expect(dial.accessibilityLabel(for: .target) == "Target humidity")
        #expect(dial.spokenValue(55) == "55 percent")
        #expect(dial.readoutAccessibilityLabel == "Target humidity 50%")
        #expect(dial.readoutAccessibilityValue(for: .single(55)) == "41% current")
        #expect(configuration(caption: .hidden).readoutAccessibilityValue(for: .single(55)) == "")
        let bare = DialValueStyle(tint: style.tint, handleLabel: "Mist level", readoutLabel: "Mist")
        #expect(configuration(style: bare).spokenValue(5) == "5")
    }

    @Test func tintsConvertFromWebComponents() {
        let tint = DialTint(red: 255, green: 0, blue: 0)
        #expect(tint.opacity == 1)
        #expect(Color(tint) == Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1))
        #expect(style.trails.first?.id == "comfort")
    }
}
