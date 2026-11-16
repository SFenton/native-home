import Foundation
import Testing
@testable import HassCore

// MARK: - Custom-light settings

/// Validation of the authored group and the values it derives: modes, swatches and the transport calls.
struct CustomLightsSettingsShapeTests {
    private func settings(title: String = "Garden", modes: [String] = ["Normal", "Personal"]) throws -> CustomLightsSettings {
        try CustomLightsSettings(
            sectionTitle: title, manualTitle: "Manual", modeTitle: "Scene",
            manualEntityId: "input_boolean.demo_manual", modeEntityId: "input_select.demo_mode", groupEntityId: "light.demo_group",
            customMode: "Personal", fallbackModes: modes, modeSwatches: ["Normal": [.init(3, 5, 7)]],
            lights: [.init(entityId: "light.demo_one", title: "One")], resetKelvin: 2300, resetBrightness: 200, resetTransition: 2)
    }

    @Test func blankCopyIsRefused() {
        #expect(throws: CustomLightsSettings.ValidationError.invalidCopy) { try settings(title: "  ") }
        #expect(throws: CustomLightsSettings.ValidationError.self) { try settings(modes: ["Normal"]) }
    }

    @Test func homeAssistantOptionsOutrankTheFallbackOrder() throws {
        let value = try settings()
        #expect(value.modes(nil) == ["Normal", "Personal"])
        let entity = EntityState(entityId: "input_select.demo_mode", state: "Normal",
                                 attributes: ["options": .array([.string("Personal"), .string("Normal")])])
        #expect(value.modes(entity) == ["Personal", "Normal"])
        #expect(value.swatch(for: "Normal", custom: []) == [.init(3, 5, 7)])
        #expect(value.swatch(for: "Unknown", custom: []).isEmpty)
        #expect(value.swatch(for: "Personal", custom: [.init(1, 2, 3)]) == CustomLightsConfig.customGradient([.init(1, 2, 3)]))
    }

    @Test func theLegacySnapshotIsBuiltWithoutValidationAndKeepsTheGivenManualTitle() {
        let snapshot = CustomLightsSettings.legacyHouseSnapshot(manualTitle: "Manual lights")
        #expect(snapshot.manualTitle == "Manual lights")
        #expect(snapshot.customMode == CustomLightsConfig.customMode)
        #expect(snapshot.fallbackModes == CustomLightsConfig.fallbackModes)
        #expect(snapshot.resetKelvin == 2000 && snapshot.resetBrightness == 255 && snapshot.resetTransition == 1)
    }
}
