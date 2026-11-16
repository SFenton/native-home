import Foundation

/// Explicit targets and appearance for a custom-light group; injected settings never consult the house configuration.
public struct CustomLightsSettings: Equatable, Sendable {
    /// The authored validation error choices.
    public enum ValidationError: Error, Equatable, Sendable {
        case invalidTarget
        case invalidCopy
        case invalidModes
        case invalidLights
        case invalidReset
        case invalidSelection
    }

    public let sectionTitle: String
    public let manualTitle: String
    public let modeTitle: String
    public let manualEntityId: String
    public let modeEntityId: String
    public let groupEntityId: String
    public let customMode: String
    public let fallbackModes: [String]
    public let modeSwatches: [String: [CustomLightsConfig.RGB]]
    public let lights: [CustomLightsConfig.Light]
    public let resetKelvin: Int
    public let resetBrightness: Int
    public let resetTransition: Int

    /// Validates injected configuration before it can be used to address Home Assistant.
    public init(sectionTitle: String, manualTitle: String, modeTitle: String,
                manualEntityId: String, modeEntityId: String, groupEntityId: String,
                customMode: String, fallbackModes: [String], modeSwatches: [String: [CustomLightsConfig.RGB]],
                lights: [CustomLightsConfig.Light], resetKelvin: Int, resetBrightness: Int,
                resetTransition: Int) throws {
        guard Self.validTarget(manualEntityId, domains: ["input_boolean", "switch"]),
              Self.validTarget(modeEntityId, domains: ["input_select", "select"]),
              Self.validTarget(groupEntityId, domains: ["light"]) else { throw ValidationError.invalidTarget }
        guard [sectionTitle, manualTitle, modeTitle, customMode].allSatisfy(Self.nonblank) else { throw ValidationError.invalidCopy }
        guard (1...64).contains(fallbackModes.count), fallbackModes.allSatisfy(Self.nonblank),
              Set(fallbackModes).count == fallbackModes.count, fallbackModes.contains(customMode),
              modeSwatches.keys.allSatisfy({ fallbackModes.contains($0) && $0 != customMode }),
              modeSwatches.values.allSatisfy({ $0.count <= 64 }),
              modeSwatches.values.flatMap({ $0 }).allSatisfy({ (0...255).contains($0.red) && (0...255).contains($0.green) && (0...255).contains($0.blue) })
        else { throw ValidationError.invalidModes }
        guard (1...100).contains(lights.count),
              lights.allSatisfy({ Self.validTarget($0.entityId, domains: ["light"]) && Self.nonblank($0.title) }),
              Set(lights.map(\.entityId)).count == lights.count else { throw ValidationError.invalidLights }
        guard (1000...10000).contains(resetKelvin), (1...255).contains(resetBrightness),
              (0...3600).contains(resetTransition) else { throw ValidationError.invalidReset }
        self.init(uncheckedSectionTitle: sectionTitle, manualTitle: manualTitle, modeTitle: modeTitle,
                  manualEntityId: manualEntityId, modeEntityId: modeEntityId, groupEntityId: groupEntityId,
                  customMode: customMode, fallbackModes: fallbackModes, modeSwatches: modeSwatches,
                  lights: lights, resetKelvin: resetKelvin, resetBrightness: resetBrightness, resetTransition: resetTransition)
    }

    private init(uncheckedSectionTitle sectionTitle: String, manualTitle: String, modeTitle: String,
                 manualEntityId: String, modeEntityId: String, groupEntityId: String,
                 customMode: String, fallbackModes: [String], modeSwatches: [String: [CustomLightsConfig.RGB]],
                 lights: [CustomLightsConfig.Light], resetKelvin: Int, resetBrightness: Int, resetTransition: Int) {
        self.sectionTitle = sectionTitle
        self.manualTitle = manualTitle
        self.modeTitle = modeTitle
        self.manualEntityId = manualEntityId
        self.modeEntityId = modeEntityId
        self.groupEntityId = groupEntityId
        self.customMode = customMode
        self.fallbackModes = fallbackModes
        self.modeSwatches = modeSwatches
        self.lights = lights
        self.resetKelvin = resetKelvin
        self.resetBrightness = resetBrightness
        self.resetTransition = resetTransition
    }

    /// The legacy feature wrapper's house snapshot. It may be incomplete while house configuration loads;
    /// it is not validated and must never be treated as an accepted ServerUI source.
    public static func legacyHouseSnapshot(manualTitle: String) -> Self {
        let modes = CustomLightsConfig.fallbackModes
        let swatches = Dictionary(Set(modes).filter { $0 != CustomLightsConfig.customMode }.map {
            ($0, CustomLightsConfig.swatch(for: $0, custom: []))
        }, uniquingKeysWith: { first, _ in first })
        return Self(uncheckedSectionTitle: CustomLightsConfig.frontYardTitle, manualTitle: manualTitle,
                    modeTitle: CustomLightsConfig.lightingModeTitle,
                    manualEntityId: CustomLightsConfig.manualControlEntityId, modeEntityId: CustomLightsConfig.modeEntityId,
                    groupEntityId: CustomLightsConfig.groupEntityId, customMode: CustomLightsConfig.customMode,
                    fallbackModes: modes, modeSwatches: swatches, lights: CustomLightsConfig.lights,
                    resetKelvin: 2000, resetBrightness: 255, resetTransition: 1)
    }

    /// Home Assistant options take precedence over the configured fallback order.
    public func modes(_ entity: EntityState?) -> [String] {
        let options = entity?.attributes["options"]?.array?.compactMap(\.string) ?? []
        return options.isEmpty ? fallbackModes : options
    }

    /// Custom colors are projected from live entities; other colors are authored.
    public func swatch(for mode: String, custom: [CustomLightsConfig.RGB]) -> [CustomLightsConfig.RGB] {
        mode == customMode ? CustomLightsConfig.customGradient(custom) : modeSwatches[mode] ?? []
    }

    /// The service call that switches the manual light override on or off.
    public func setManual(on: Bool) -> ServiceCall {
        ServiceCall(String(manualEntityId.prefix { $0 != "." }), on ? "turn_on" : "turn_off", target: manualEntityId)
    }

    /// Builds a mode command only while its configured source still offers that option.
    public func selectMode(_ mode: String, offeredBy entity: EntityState?) throws -> ServiceCall {
        guard let entity, entity.entityId == modeEntityId, !entity.isUnavailable, modes(entity).contains(mode) else {
            throw ValidationError.invalidSelection
        }
        return ServiceCall(String(modeEntityId.prefix { $0 != "." }), "select_option", target: modeEntityId, data: ["option": .string(mode)])
    }

    /// The group's reset target is fixed by the validated settings.
    public func resetGroup() -> ServiceCall {
        reset(groupEntityId)
    }

    /// Only a member of this group can be addressed by its per-light reset.
    public func resetLight(_ light: CustomLightsConfig.Light) throws -> ServiceCall {
        guard lights.contains(light) else { throw ValidationError.invalidTarget }
        return reset(light.entityId)
    }

    private func reset(_ target: String) -> ServiceCall {
        ServiceCall("light", "turn_on", target: target, data: [
            "color_temp_kelvin": .number(Double(resetKelvin)), "brightness": .number(Double(resetBrightness)),
            "transition": .number(Double(resetTransition)),
        ])
    }

    private static func nonblank(_ value: String) -> Bool {
        value.utf16.count <= 240 && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func validTarget(_ value: String, domains: Set<String>) -> Bool {
        guard value.utf16.count <= 160,
              value.range(of: "^[a-z][a-z0-9_]*\\.[a-z0-9_]+$", options: .regularExpression) == value.startIndex..<value.endIndex
        else { return false }
        return domains.contains(String(value.prefix { $0 != "." }))
    }
}
