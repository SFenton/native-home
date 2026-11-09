import Foundation

/// Light power and brightness commands (web `LightBrightnessCard.tsx`).
///
/// Power is always an explicit `turn_on` / `turn_off` chosen from the shown state, never `toggle`:
/// Presence Based Lighting's Presence Lock (SFenton/presence-based-lighting) reverts light changes in
/// empty rooms and only honors an exact `turn_on` from an app user as a manual-on hold.
public enum LightControl {
    // MARK: - Commands

    /// One service call, kept as plain values so it can be tested without a connection.
    public struct Command: Equatable, Sendable {
        /// e.g. `light`.
        public var domain: String
        /// `turn_on` or `turn_off`.
        public var service: String
        /// The target entity.
        public var entityId: String
        /// `brightness_pct`, sent only when setting a level.
        public var brightnessPercent: Int?

        /// Service data for ``HassConnection/callService(_:_:data:)``.
        public var serviceData: [String: any Sendable] {
            var data: [String: any Sendable] = ["entity_id": entityId]
            if let brightnessPercent { data["brightness_pct"] = brightnessPercent }
            return data
        }
    }

    /// Domains whose own `turn_on` / `turn_off` services exist; anything else goes through `homeassistant`.
    static let powerDomains: Set<String> = ["light", "switch", "fan", "input_boolean"]

    /// Turns the entity on or off. A bare `turn_on` (no brightness) is what PBL treats as a manual on.
    public static func power(_ entityId: String, on: Bool) -> Command {
        let domain = String(entityId.prefix { $0 != "." })
        return Command(
            domain: powerDomains.contains(domain) ? domain : "homeassistant",
            service: on ? "turn_on" : "turn_off",
            entityId: entityId
        )
    }

    /// The command that flips what the tile currently shows.
    public static func flip(_ entityId: String, shownOn: Bool) -> Command {
        power(entityId, on: !shownOn)
    }

    /// Sets brightness in percent; 0 turns the light off (web `setBrightness`).
    public static func brightness(_ entityId: String, percent: Double) -> Command {
        let value = clampedPercent(percent)
        guard value > 0 else { return power(entityId, on: false) }
        return Command(domain: "light", service: "turn_on", entityId: entityId, brightnessPercent: value)
    }

    // MARK: - Reading state

    /// Shown brightness in percent: 0 when off, 100 when on without a reported level (web `liveDisplayPct`).
    public static func percent(of entity: EntityState?) -> Int {
        guard let entity, !entity.isUnavailable, entity.state == "on" else { return 0 }
        guard let brightness = entity.attributes["brightness"]?.number else { return 100 }
        let pct = Int((brightness / 255 * 100).rounded())
        return pct > 0 ? pct : 100
    }

    /// Whether the entity takes a brightness level: a light with any color mode beyond `onoff`, or one
    /// reporting `brightness`. Switches and on/off-only lights get a plain power tile.
    public static func isDimmable(_ entity: EntityState?) -> Bool {
        guard let entity, entity.domain == "light" else { return false }
        if entity.attributes["brightness"]?.number != nil { return true }
        let modes = entity.attributes["supported_color_modes"]?.array?.compactMap(\.string) ?? []
        return modes.contains { $0 != "onoff" }
    }

    /// The light's `rgb_color` as 0...1 components, used to tint the brightness fill.
    public static func rgb(of entity: EntityState?) -> (red: Double, green: Double, blue: Double)? {
        guard let values = entity?.attributes["rgb_color"]?.array?.compactMap(\.number), values.count == 3 else { return nil }
        return (values[0] / 255, values[1] / 255, values[2] / 255)
    }

    /// Rounds and clamps a percent to 0...100.
    public static func clampedPercent(_ percent: Double) -> Int {
        guard percent.isFinite else { return 0 }
        return min(100, max(0, Int(percent.rounded())))
    }
}
