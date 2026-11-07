import Foundation

/// A room's Presence Based Lighting mode, as the Admin page's override grid shows it
/// (web `src/components/hass/presenceOverrideState.ts` and `PresenceOverrideCard.tsx`).
public enum PresenceOverrideState: String, CaseIterable, Sendable, Hashable, Identifiable {
    case enabled, off, paused, quieted, unavailable

    public var id: String { rawValue }

    /// The four modes a room can be set to, in the web's order (`PRESENCE_OVERRIDE_STATES`).
    public static let choices: [PresenceOverrideState] = [.enabled, .off, .paused, .quieted]

    // MARK: - Resolving

    /// Resolves the shown mode from the room's `…_presence_allowed` switch.
    ///
    /// No entity, `unavailable` or `unknown` → unavailable; `off` → off (Disabled); an `automation_state` of
    /// `paused` or a truthy `automation_paused` → paused; `quieted` likewise → quieted; `on` → enabled.
    public init(entity: EntityState?) {
        guard let entity else { self = .unavailable; return }
        let state = Self.normalized(.string(entity.state))
        if state == "off" { self = .off; return }
        if state == "unavailable" || state == "unknown" { self = .unavailable; return }
        let automation = Self.normalized(entity.attributes["automation_state"])
        if automation == "paused" || Self.isTrue(entity.attributes["automation_paused"]) { self = .paused; return }
        if automation == "quieted" || Self.isTrue(entity.attributes["automation_quieted"]) { self = .quieted; return }
        self = state == "on" ? .enabled : .unavailable
    }

    private static func normalized(_ value: JSONValue?) -> String {
        value?.string?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
    }

    private static func isTrue(_ value: JSONValue?) -> Bool {
        if value?.bool == true { return true }
        let text = normalized(value)
        return text == "true" || text == "on"
    }

    // MARK: - Commands

    /// `presence_based_lighting.set_automation_state` for `entityId`; enabled is sent as `active`.
    /// - Returns: `nil` for ``unavailable``, which is not a mode.
    public func command(for entityId: String) -> ServiceCall? {
        guard self != .unavailable else { return nil }
        let value = self == .enabled ? "active" : rawValue
        return ServiceCall("presence_based_lighting", "set_automation_state", target: entityId, data: ["state": .string(value)])
    }

    // MARK: - Presentation

    /// The option label in the room's detail list.
    public var label: String {
        switch self {
        case .enabled: "Enable Presence-Based Lighting"
        case .off: "Disable Presence-Based Lighting"
        case .paused: "Paused"
        case .quieted: "Quieted"
        case .unavailable: "Unavailable"
        }
    }

    /// The room tile's subtitle.
    public var summary: String {
        switch self {
        case .enabled: "Enabled"
        case .off: "Disabled"
        case .paused: "Paused"
        case .quieted: "Quieted"
        case .unavailable: "Unavailable"
        }
    }

    /// What the mode does.
    public var detail: String {
        switch self {
        case .enabled: "Presence and occupancy can control the lights."
        case .off: "Presence-Based Lighting is disabled for this room."
        case .paused: "Lights stay in their current state until explicitly resumed."
        case .quieted: "Stay dark, then rearm after the room clears."
        case .unavailable: "Home Assistant state is unavailable."
        }
    }

    /// Web MDI icon.
    public var icon: String {
        switch self {
        case .enabled: "mdi:lightbulb-auto"
        case .off: "mdi:lightbulb-off"
        case .paused: "mdi:pause-circle"
        case .quieted: "mdi:volume-mute"
        case .unavailable: "mdi:alert-circle"
        }
    }

    /// The web card color, 0...255 per channel.
    public var rgb: (red: Int, green: Int, blue: Int) {
        switch self {
        case .enabled: (67, 160, 71)
        case .off, .unavailable: (84, 110, 122)
        case .paused: (230, 154, 37)
        case .quieted: (117, 91, 180)
        }
    }
}
