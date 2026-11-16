@testable import HassCore
import Testing

@Suite struct CustomLightsSettingsTests {
    private func settings(manual: String = "input_boolean.demo_manual",
                          mode: String = "input_select.demo_mode",
                          group: String = "light.demo_group",
                          modes: [String] = ["Normal", "Personal"],
                          lights: [CustomLightsConfig.Light] = [.init(entityId: "light.demo_one", title: "One")],
                          kelvin: Int = 2300) throws -> CustomLightsSettings {
        try .init(sectionTitle: "Garden", manualTitle: "Manual", modeTitle: "Scene",
                  manualEntityId: manual, modeEntityId: mode, groupEntityId: group,
                  customMode: "Personal", fallbackModes: modes,
                  modeSwatches: ["Normal": [.init(3, 5, 7)]], lights: lights,
                  resetKelvin: kelvin, resetBrightness: 200, resetTransition: 2)
    }

    @Test func configuredCommandsKeepTheirTargetsAndResetPayload() throws {
        let value = try settings()
        #expect(value.setManual(on: true) == ServiceCall("input_boolean", "turn_on", target: "input_boolean.demo_manual"))
        let mode = EntityState(entityId: "input_select.demo_mode", state: "Normal")
        #expect(try value.selectMode("Personal", offeredBy: mode) == ServiceCall("input_select", "select_option", target: "input_select.demo_mode",
                                                                                  data: ["option": .string("Personal")]))
        #expect(throws: CustomLightsSettings.ValidationError.invalidSelection) {
            try value.selectMode("Other", offeredBy: mode)
        }
        #expect(throws: CustomLightsSettings.ValidationError.invalidSelection) {
            try value.selectMode("Personal", offeredBy: EntityState(entityId: "input_select.demo_mode", state: "unavailable"))
        }
        #expect(value.resetGroup() == ServiceCall("light", "turn_on", target: "light.demo_group",
                                                   data: ["color_temp_kelvin": .number(2300), "brightness": .number(200), "transition": .number(2)]))
        #expect(try value.resetLight(value.lights[0]).target == "light.demo_one")
        #expect(throws: CustomLightsSettings.ValidationError.invalidTarget) {
            try value.resetLight(.init(entityId: "light.demo_other", title: "Other"))
        }
    }

    @Test func configuredModeOrderAndColorsAreNotHouseDefaults() throws {
        let value = try settings()
        #expect(value.modes(nil) == ["Normal", "Personal"])
        let live = EntityState(entityId: "input_select.demo_mode", state: "Normal",
                               attributes: ["options": .array([.string("Personal"), .string("Normal")])])
        #expect(value.modes(live) == ["Personal", "Normal"])
        #expect(value.swatch(for: "Normal", custom: []) == [.init(3, 5, 7)])
        #expect(value.swatch(for: "Personal", custom: [.init(200, 200, 200), .init(0, 0, 0), .init(200, 200, 200)])
                == [.init(0, 0, 0), .init(200, 200, 200)])
    }

    @Test func invalidTargetsModesAndResetAreRejected() {
        #expect(throws: CustomLightsSettings.ValidationError.invalidTarget) { try settings(group: "switch.demo_group") }
        #expect(throws: CustomLightsSettings.ValidationError.invalidTarget) { try settings(manual: "input_boolean.demo_manual\n") }
        #expect(throws: CustomLightsSettings.ValidationError.invalidTarget) { try settings(mode: "script.demo_run") }
        #expect(throws: CustomLightsSettings.ValidationError.invalidModes) { try settings(modes: ["Normal", "Normal"]) }
        #expect(throws: CustomLightsSettings.ValidationError.invalidLights) {
            try settings(lights: [.init(entityId: "light.demo_one", title: "One"), .init(entityId: "light.demo_one", title: "Again")])
        }
        #expect(throws: CustomLightsSettings.ValidationError.invalidReset) { try settings(kelvin: 0) }
    }
}
