#if DEBUG
import Foundation
import HassCore

/// A synthetic house for tests, fixtures and the DEBUG gallery, so none of them needs the real house.
///
/// Lives in its own `HassDemoHouse` module so the app's DEBUG gallery and the test support share one copy. Everything is
/// behind `#if DEBUG`: a Release build links an empty module and the document never ships. Tests reach it through
/// `HassTestSupport`, which re-exports the module.
///
/// Every section of ``HouseConfig`` is populated with neutral values: people named Alex and Sam, generic rooms (Kitchen,
/// Living Room, Bedroom 1, Studio) and entity ids that all start `demo_` (`light.demo_kitchen`-style). The document keeps
/// the shapes and counts the app exercises (several garage doors, a bed per side, remotes with roles, vacuums,
/// sprinklers), so the code paths stay covered. It carries no brand, model, host, address or user id.
///
/// Use ``source`` to scope a test that reads a `*Config` facade:
///
/// ```swift
/// HouseConfigSource.$scoped.withValue(DemoHouse.source) { /* facades answer with the demo house */ }
/// ```
///
/// and ``states`` (or ``seed(_:)``) to give an ``EntityStore`` a matching state for every entity the document names.
public enum DemoHouse {
    /// The demo house, decoded through ``HouseConfig/decode(_:)`` so schema and required-role checks apply.
    public static let config: HouseConfig = {
        do {
            return try HouseConfig.decode(Data(documentJSON.utf8))
        } catch {
            preconditionFailure("DemoHouse document is invalid: \(error)")
        }
    }()

    /// A source that holds ``config``; pass it to `HouseConfigSource.$scoped.withValue`. It is never written after creation.
    public static let source: HouseConfigSource = {
        let source = HouseConfigSource()
        source.set(config)
        return source
    }()

    /// The size of the document as the server would store it, in bytes (must stay under ``HouseConfig/serverByteLimit``).
    public static var encodedByteCount: Int {
        (try? config.encoded().count) ?? .max
    }

    // MARK: - Entity states

    /// Every entity id the document names, as a dictionary key or a value (any string shaped `domain.demo_object`), sorted.
    public static var entityIds: [String] {
        guard let data = try? config.encoded(), let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found = Set<String>()
        collect(root, into: &found)
        return found.sorted()
    }

    /// One state per ``entityIds`` entry, with a plausible resting value for its domain (lights off, locks locked, sensors 0).
    public static var states: [EntityState] {
        entityIds.map { id in
            let domain = String(id.prefix { $0 != "." })
            let resting = restingStates[domain] ?? (state: "unknown", attributes: [:])
            return EntityState(
                entityId: id, state: resting.state,
                attributes: resting.attributes.merging(["friendly_name": .string(friendlyName(id))]) { current, _ in current },
                lastChanged: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
    }

    /// Loads ``states`` into a store as a full live set.
    /// - Parameter store: The store to fill.
    @MainActor
    public static func seed(_ store: EntityStore) {
        store.replaceAll(states)
    }

    // MARK: - Helpers

    private static let restingStates: [String: (state: String, attributes: [String: JSONValue])] = [
        "light": ("off", [:]), "switch": ("off", [:]), "fan": ("off", [:]), "input_boolean": ("off", [:]),
        "binary_sensor": ("off", [:]), "sensor": ("0", [:]), "number": ("0", [:]), "input_number": ("0", [:]),
        "lock": ("locked", [:]), "cover": ("closed", [:]), "alarm_control_panel": ("disarmed", [:]),
        "climate": ("off", ["current_temperature": .number(21), "temperature": .number(21)]),
        "vacuum": ("docked", [:]), "media_player": ("off", [:]), "person": ("home", [:]), "weather": ("sunny", [:]),
        "camera": ("idle", [:]), "script": ("off", [:]), "humidifier": ("off", [:]), "todo": ("0", [:]),
        "schedule": ("off", [:]), "select": ("unknown", [:]), "input_select": ("unknown", [:]), "device_tracker": ("home", [:]),
    ]

    private static func collect(_ node: Any, into found: inout Set<String>) {
        if let text = node as? String {
            if isEntityId(text) { found.insert(text) }
        } else if let list = node as? [Any] {
            for item in list { collect(item, into: &found) }
        } else if let object = node as? [String: Any] {
            for (key, value) in object {
                if isEntityId(key) { found.insert(key) }
                collect(value, into: &found)
            }
        }
    }

    /// Whether a string is a demo entity id: `domain.demo_object`.
    private static func isEntityId(_ text: String) -> Bool {
        text.range(of: #"^[a-z_]+\.demo_[a-z0-9_]+$"#, options: .regularExpression) != nil
    }

    private static func friendlyName(_ id: String) -> String {
        let object = id.drop { $0 != "." }.dropFirst().replacingOccurrences(of: "demo_", with: "", options: .anchored)
        return object.split(separator: "_").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
#endif
