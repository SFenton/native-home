import Foundation

// MARK: - Kind

/// What an entity is, in the words people use: the class a question names ("lights", "windows", "vents").
///
/// Aggregates, scopes and plural questions work on kinds, never on entity ids.
public enum AskKind: String, Codable, Sendable, CaseIterable {
    case light, window, door, garage, lock, alarm, camera, vent, motion, occupancy
    case temperature, humidity, airQuality, battery, power
    case mediaPlayer, fan, climate, vacuum, person, automation, script, scene, weather, valve, switchDevice, other

    /// The kind of an entity from its domain, device class and name words.
    static func of(domain: String, deviceClass: String?, nameWords: Set<String>) -> AskKind {
        switch domain {
        case "light": return .light
        case "lock": return .lock
        case "alarm_control_panel": return .alarm
        case "camera": return .camera
        case "media_player": return .mediaPlayer
        case "fan": return nameWords.contains("vent") ? .vent : .fan
        case "climate": return .climate
        case "vacuum": return .vacuum
        case "person": return .person
        case "automation": return .automation
        case "script": return .script
        case "scene": return .scene
        case "weather": return .weather
        case "valve": return .valve
        case "cover":
            if deviceClass == "garage" || nameWords.contains("garage") { return .garage }
            if nameWords.contains("vent") { return .vent }
            if deviceClass == "door" { return .door }
            if deviceClass == "window" { return .window }
            return .other
        case "binary_sensor":
            switch deviceClass {
            case "door", "garage_door": return nameWords.contains("garage") ? .garage : .door
            case "window": return .window
            case "opening": return nameWords.contains("window") ? .window : (nameWords.contains("door") ? .door : .other)
            case "motion": return .motion
            case "occupancy", "presence": return .occupancy
            default: return .other
            }
        case "sensor":
            switch deviceClass {
            case "temperature": return .temperature
            case "humidity": return .humidity
            case "aqi", "pm25", "pm10", "co2": return .airQuality
            case "battery": return .battery
            case "power", "energy": return .power
            default: return .other
            }
        case "switch", "input_boolean": return .switchDevice
        default: return .other
        }
    }

    /// The nouns that name this kind in a question (stemmed).
    var nouns: [String] {
        switch self {
        case .light: ["light"]
        case .window: ["window"]
        case .door: ["door"]
        case .garage: ["garage"]
        case .lock: ["lock"]
        case .alarm: ["alarm"]
        case .camera: ["camera"]
        case .vent: ["vent"]
        case .motion: ["motion"]
        case .occupancy: ["occupancy", "presence"]
        case .temperature: ["temperature"]
        case .humidity: ["humidity"]
        case .airQuality: ["air", "aqi", "pm25"]
        case .battery: ["battery"]
        case .power: ["power"]
        case .mediaPlayer: ["player", "tv", "speaker"]
        case .fan: ["fan", "purifier"]
        case .climate: ["thermostat", "climate"]
        case .vacuum: ["vacuum"]
        case .person: ["person"]
        case .automation: ["automation"]
        case .script: ["script"]
        case .scene: ["scene"]
        case .weather: ["weather"]
        case .valve: ["valve", "sprinkler"]
        case .switchDevice: ["switch", "plug"]
        case .other: []
        }
    }
}
