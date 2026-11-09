import Foundation

public extension HouseConfig {
    /// The Home Assistant domains an entity id may start with. A string in the document counts as an entity id only when it
    /// is `domain.object_id` with one of these domains, so an SF Symbol such as `house.fill` or a file name never does.
    static let entityDomains: Set<String> = [
        "alarm_control_panel", "automation", "binary_sensor", "button", "calendar", "camera", "climate", "counter", "cover", "date",
        "datetime", "device_tracker", "event", "fan", "group", "humidifier", "image", "input_boolean", "input_button",
        "input_datetime", "input_number", "input_select", "input_text", "lawn_mower", "light", "lock", "media_player", "number",
        "person", "remote", "scene", "script", "select", "sensor", "siren", "sun", "switch", "text", "time", "timer", "todo",
        "update", "vacuum", "valve", "water_heater", "weather", "zone",
    ]

    /// Every entity id the document names, in any section. Found by walking the encoded JSON, so a section added later is
    /// covered without a list to keep in step. Costs one encode: call it when a screen needs it (the Home Assistant modal's
    /// House Layout row), never per frame.
    var referencedEntityIds: Set<String> {
        guard let data = try? encoded(), let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found: Set<String> = []
        Self.collectEntityIds(in: object, into: &found)
        return found
    }

    /// The entity ids the document names that Home Assistant did not report, sorted.
    ///
    /// - Parameters:
    ///   - hasReceivedFirstState: False until the first state set (or the saved snapshot) landed: nothing is missing before
    ///     then, because a tile with no state yet pulses like any pending value.
    ///   - state: Looks up an entity's current state (`EntityStore.value`).
    /// - Returns: The ids with no state, or an empty list before the first state set.
    func missingEntityIds(hasReceivedFirstState: Bool, state: (String) -> EntityState?) -> [String] {
        guard hasReceivedFirstState else { return [] }
        return referencedEntityIds.filter { state($0) == nil }.sorted()
    }

    private static func collectEntityIds(in node: Any, into found: inout Set<String>) {
        switch node {
        case let text as String:
            if isEntityId(text) { found.insert(text) }
        case let list as [Any]:
            for item in list { collectEntityIds(in: item, into: &found) }
        case let object as [String: Any]:
            for (key, value) in object {
                if isEntityId(key) { found.insert(key) }
                collectEntityIds(in: value, into: &found)
            }
        default:
            break
        }
    }

    /// Whether a string reads as `domain.object_id` for a known domain.
    static func isEntityId(_ text: String) -> Bool {
        guard let dot = text.firstIndex(of: "."), dot != text.startIndex else { return false }
        let domain = String(text[..<dot]), object = text[text.index(after: dot)...]
        guard entityDomains.contains(domain), !object.isEmpty else { return false }
        return object.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "_") }
    }
}
