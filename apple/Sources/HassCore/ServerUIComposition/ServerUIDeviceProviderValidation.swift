import Foundation

// MARK: - Semantic provider checks

enum ServerUIDeviceProviderValidation {
    static func validate(_ descriptor: ServerUIDeviceProviderDescriptor, at path: String) -> [ServerUICompositionError] {
        var issues: [ServerUICompositionError] = []
        func invalid(_ field: String) { issues.append(.init(.invalidCombination, path + "/" + field)) }
        func unique(_ values: [String], _ field: String) {
            if Set(values).count != values.count { invalid(field) }
        }
        func domain(_ value: String, _ allowed: [String], _ field: String) {
            if !allowed.contains(String(value.prefix { $0 != "." })) { invalid(field) }
        }
        switch descriptor {
        case .remote(let descriptor):
            let config = descriptor.configuration
            unique(descriptor.cards.map(\.key) + config.devices.map(\.id), "cards")
            unique(config.apps.map(\.id), "apps")
            unique(config.devices.map(\.id), "devices")
            unique(config.optimisticEntityIds, "optimisticEntityIds")
            unique(config.liveChangeEntityIds, "liveChangeEntityIds")
            domain(config.mediaEntityId, ["media_player"], "mediaEntityId")
            domain(config.volumeEntityId, ["media_player"], "volumeEntityId")
            if !Set(config.liveChangeEntityIds).isSubset(of: Set(config.optimisticEntityIds)) { invalid("liveChangeEntityIds") }
            var commands = ServerUIServiceVocabulary.slotCalls(config)
            for (index, card) in descriptor.cards.enumerated() {
                guard let action = card.configuration.action else { continue }
                commands.append(.init(slot: .remoteDevice, field: "cards/\(index)/configuration",
                                      calls: ServerUIServiceVocabulary.calls(action)))
            }
            for group in commands where !group.calls.allSatisfy({ ServerUIServiceVocabulary.allows($0, in: group.slot) }) {
                invalid(group.field)
            }
            for (index, app) in config.apps.enumerated() {
                if app.imagePath?.split(separator: "/").contains("..") == true { invalid("apps/\(index)/imagePath") }
            }
            func validateDevice(_ device: MediaRemoteDevice, at field: String) {
                if case let .configuredConsole(cloud, hdmi, tv, power, input, _, _, _) = device.stateResolver,
                   !Set([cloud, hdmi, tv, power, input]).isSubset(of: Set(device.stateEntityIds ?? [device.entityId])) {
                    invalid(field + "/stateEntityIds")
                }
            }
            for (index, device) in config.devices.enumerated() { validateDevice(device, at: "devices/\(index)") }
            for (index, card) in descriptor.cards.enumerated() { validateDevice(card.configuration, at: "cards/\(index)/configuration") }
        case .bedroom(let room):
            unique(room.beds.map(\.providerId) + [room.wakeProviderId], "beds")
            unique(room.beds.map { $0.configuration.id }, "beds")
            unique(room.beds.map { $0.configuration.side.rawValue }, "beds")
            unique(room.environment.wakeLight.sources.map(\.id), "environment/wakeLight/sources")
            unique(room.environment.wakeLight.sources.map { $0.side.rawValue }, "environment/wakeLight/sources")
            for (index, source) in room.environment.wakeLight.sources.enumerated() {
                if !room.beds.contains(where: { $0.configuration.id == source.bedId && $0.configuration.side == source.side }) {
                    invalid("environment/wakeLight/sources/\(index)/bedId")
                }
            }
            for (index, bed) in room.beds.enumerated() {
                let c = bed.configuration
                domain(c.climateEntityId, ["climate"], "beds/\(index)/configuration/climateEntityId")
                for (phase, value) in c.stageLevelEntityIds {
                    domain(value, ["input_number"], "beds/\(index)/configuration/stageLevelEntityIds/\(phase.rawValue)")
                }
            }
            domain(room.environment.scheduleEntityId, ["sensor"], "environment/scheduleEntityId")
            domain(room.environment.wakeLight.statusEntityId, ["sensor"], "environment/wakeLight/statusEntityId")
        case .lights(let group):
            do { _ = try group.settings() } catch { invalid("lights") }
        case .sprinkler(let value):
            let c = value.controller
            unique(c.zones.map(\.valveEntityId), "controller/zones")
            unique(c.zones.map(\.programEntityId), "controller/zones")
            for (name, id, domains) in [
                ("batteryEntityId", c.batteryEntityId, ["sensor"]), ("faultEntityId", c.faultEntityId, ["binary_sensor"]),
                ("hubConnectedEntityId", c.hubConnectedEntityId, ["binary_sensor"]), ("modeEntityId", c.modeEntityId, ["select"]),
                ("nextWateringEntityId", c.nextWateringEntityId, ["sensor"]), ("stateEntityId", c.stateEntityId, ["sensor"]),
                ("rainDelayEntityId", c.rainDelayEntityId, ["switch"]), ("smartWateringEntityId", c.smartWateringEntityId, ["switch"])
            ] { domain(id, domains, "controller/" + name) }
            for (index, zone) in c.zones.enumerated() {
                domain(zone.valveEntityId, ["valve"], "controller/zones/\(index)/valveEntityId")
                domain(zone.programEntityId, ["switch"], "controller/zones/\(index)/programEntityId")
                domain(zone.historyEntityId, ["sensor"], "controller/zones/\(index)/historyEntityId")
            }
        }
        return issues
    }
}
