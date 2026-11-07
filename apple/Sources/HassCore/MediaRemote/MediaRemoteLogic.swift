import Foundation

/// State helpers shared by the remote's controls (web `MediaRemoteModalContent.tsx:54-71`, `entityState.ts:48`).
public enum MediaRemoteState {
    /// Unavailable or `off`.
    public static func isOff(_ state: String?) -> Bool { EntityState.isUnavailable(state) || state == "off" }

    /// `formatMediaState`: the subtitle for a device or HDMI port.
    public static func format(_ state: String?) -> String {
        switch state {
        case nil, "unavailable": "Unavailable"
        case "unknown": "Unknown"
        case let state?: StateText.titleCase(state)
        }
    }

    /// `textInputCommand`: the `adb` command that types `text`, with each `'` written as `'\''`.
    public static func textInputCommand(_ text: String) -> String {
        "input text '\(text.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// `deviceStateIsActive`: in `activeStates` when given, else anything but off, unavailable or unknown.
    public static func isActive(_ state: String, activeStates: [String]) -> Bool {
        activeStates.isEmpty ? !isOff(state) : activeStates.contains(state)
    }

    /// Hue Sync modes in the web's order (music, video, game), others after them in their own order.
    public static func orderedSyncModes(_ options: [String]) -> [String] {
        let order = ["music", "video", "game"]
        func rank(_ option: String) -> Int { order.firstIndex(of: option.lowercased()) ?? order.count }
        return options.enumerated().sorted { lhs, rhs in
            let (left, right) = (rank(lhs.element), rank(rhs.element))
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)
    }

    /// The MDI icon for a Hue Sync mode.
    public static func syncModeIcon(_ mode: String) -> String {
        switch mode.lowercased() {
        case "game": "mdi:gamepad-variant"
        case "music": "mdi:music"
        case "video": "mdi:movie-open"
        default: "mdi:lightbulb-multiple"
        }
    }

    /// A number as JavaScript's `String(number)` writes it: `50`, not `50.0`.
    public static func numberString(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}

// MARK: - Action resolution

public extension MediaRemoteAction {
    /// Picks the command to run (web `resolveAction`).
    /// - Parameters:
    ///   - entityId: The control's own entity, used when the action names none.
    ///   - stateOverride: A state to decide on instead of the entity's (a device's resolved state).
    ///   - displayedState: Reads an entity's displayed (optimistic or live) state.
    func resolve(entityId: String? = nil, stateOverride: String? = nil, displayedState: (String) -> String?) -> MediaRemoteCommand {
        switch self {
        case let .command(command):
            return command
        case let .state(actionEntityId, cases, otherwise):
            let decidingEntity = actionEntityId ?? entityId
            let state = stateOverride ?? decidingEntity.flatMap(displayedState)
            guard let state else { return otherwise }
            return cases.first { $0.states.contains(state) }?.command ?? otherwise
        }
    }
}

public extension IconColorRule {
    /// Inactive only when every entity has a state and it is one of its inactive states (web `iconColorFromRule`).
    func tone(displayedState: (String) -> String?) -> IconTone {
        let inactive = entityIds.allSatisfy { entityId in
            guard let state = displayedState(entityId) else { return false }
            return (inactiveStatesByEntity[entityId] ?? inactiveStates).contains(state)
        }
        return inactive ? .inactive : .active
    }
}
