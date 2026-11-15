import Foundation

/// Read-only scalar projections of the canonical sprinkler snapshot.
public enum ServerUISprinklerState {
    /// Reads only explicitly configured entities; absent data stays unavailable.
    public static func value(_ field: String, configuration: ServerUICompositionDocument.SprinklerState,
                             entity: (String) -> EntityState?) -> JSONValue? {
        let snapshot = SprinklerSnapshot(config: configuration.controller,
                                         lowBatteryPercent: configuration.lowBatteryPercent, entity: entity)
        switch field {
        case "status":
            switch snapshot.status {
            case .unavailable: return .string("unavailable")
            case .fault: return .string("fault")
            case .watering: return .string("watering")
            case .ready: return .string("ready")
            }
        case "available": return .bool(snapshot.available)
        case "batteryPercent": return snapshot.batteryPercent.map(JSONValue.number)
        case "batteryLow": return snapshot.batteryPercent.map { _ in .bool(snapshot.batteryLow) }
        default: break
        }
        guard snapshot.available else { return nil }
        let config = configuration.controller
        switch field {
        case "mode": return .string(snapshot.mode)
        case "fault": return entity(config.faultEntityId).flatMap { $0.isUnavailable ? nil : .bool(snapshot.fault) }
        case "hubConnected": return entity(config.hubConnectedEntityId).flatMap { $0.isUnavailable ? nil : .bool(snapshot.hubConnected) }
        case "watering": return .bool(snapshot.watering)
        case "rainDelay": return entity(config.rainDelayEntityId).flatMap { $0.isUnavailable ? nil : .bool(snapshot.rainDelay) }
        case "smartWatering": return entity(config.smartWateringEntityId).flatMap { $0.isUnavailable ? nil : .bool(snapshot.smartWatering) }
        default: return nil
        }
    }
}
