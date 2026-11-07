import Foundation

/// One sensor this phone reports through `mobile_app` (`register_sensor`, then `update_sensor_states`).
///
/// Names and unique ids mirror the official Home Assistant app's, so a template written against its entities only
/// needs the device prefix changed (`sensor.<device>_ssid` → `sensor.<device>_<app>_ssid`).
public struct MobileAppSensor: Equatable, Sendable, Identifiable {
    /// The entity domain Home Assistant creates.
    public enum Kind: String, Sendable {
        case sensor
        case binarySensor = "binary_sensor"
    }

    /// Where Home Assistant files the entity on the device page.
    public enum EntityCategory: String, Sendable {
        case diagnostic
        case config
    }

    /// Stable id within this registration (`battery_level`).
    public var uniqueID: String
    /// Display name; Home Assistant derives the entity id from the device name plus this.
    public var name: String
    /// Sensor or binary sensor.
    public var kind: Kind
    /// The current state.
    public var state: SensorValue
    /// A Material Design icon (`mdi:battery-80`).
    public var icon: String?
    /// Home Assistant device class (`battery`).
    public var deviceClass: String?
    /// Unit of measurement (`%`).
    public var unit: String?
    /// State class (`measurement`), so Home Assistant keeps statistics.
    public var stateClass: String?
    /// Diagnostic or config, or nil for a primary entity.
    public var entityCategory: EntityCategory?
    /// Extra attributes, keyed as the official app keys them ("Low Power Mode").
    public var attributes: [String: SensorValue]

    public var id: String { uniqueID }

    /// Creates a sensor.
    public init(uniqueID: String, name: String, kind: Kind = .sensor, state: SensorValue, icon: String? = nil,
                deviceClass: String? = nil, unit: String? = nil, stateClass: String? = nil,
                entityCategory: EntityCategory? = nil, attributes: [String: SensorValue] = [:]) {
        self.uniqueID = uniqueID
        self.name = name
        self.kind = kind
        self.state = state
        self.icon = icon
        self.deviceClass = deviceClass
        self.unit = unit
        self.stateClass = stateClass
        self.entityCategory = entityCategory
        self.attributes = attributes
    }

    // MARK: - Webhook bodies

    /// The `register_sensor` command for this sensor.
    public var registerBody: [String: Any] {
        var data: [String: Any] = [
            "unique_id": uniqueID,
            "name": name,
            "type": kind.rawValue,
            "state": state.jsonObject,
            "attributes": attributes.mapValues(\.jsonObject),
        ]
        data["icon"] = icon
        data["device_class"] = deviceClass
        data["unit_of_measurement"] = unit
        data["state_class"] = stateClass
        data["entity_category"] = entityCategory?.rawValue
        return ["type": "register_sensor", "data": data]
    }

    /// This sensor's entry in an `update_sensor_states` command: only what changes between updates.
    public var updateEntry: [String: Any] {
        var entry: [String: Any] = [
            "unique_id": uniqueID,
            "type": kind.rawValue,
            "state": state.jsonObject,
            "attributes": attributes.mapValues(\.jsonObject),
        ]
        entry["icon"] = icon
        return entry
    }

    /// One `update_sensor_states` command for `sensors`.
    public static func updateBody(_ sensors: [MobileAppSensor]) -> [String: Any] {
        ["type": "update_sensor_states", "data": sensors.map(\.updateEntry)]
    }
}

/// What Home Assistant answered to `update_sensor_states`, per sensor.
public struct SensorUpdateOutcome: Equatable, Sendable {
    /// Sensors Home Assistant does not know (`not_registered`): register them, then update again.
    public var notRegistered: Set<String>
    /// Sensors the user disabled in Home Assistant; stop sending them.
    public var disabled: Set<String>
    /// Other failures, unique id → Home Assistant's error code.
    public var failed: [String: String]

    /// Creates an outcome.
    public init(notRegistered: Set<String> = [], disabled: Set<String> = [], failed: [String: String] = [:]) {
        self.notRegistered = notRegistered
        self.disabled = disabled
        self.failed = failed
    }

    /// Reads the webhook's response body: `{"battery_level": {"success": true}, "ssid": {"success": false,
    /// "error": {"code": "not_registered"}}}`.
    /// - Returns: nil when the body is not that shape.
    public init?(json data: Data) {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        self.init()
        for (uniqueID, value) in object {
            guard let result = value as? [String: Any] else { return nil }
            if result["is_disabled"] as? Bool == true { disabled.insert(uniqueID) }
            guard result["success"] as? Bool == false else { continue }
            let code = (result["error"] as? [String: Any])?["code"] as? String ?? "unknown"
            if code == "not_registered" {
                notRegistered.insert(uniqueID)
            } else {
                failed[uniqueID] = code
            }
        }
    }
}
