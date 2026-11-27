import Foundation

// MARK: - State words

/// Plain-English words for an entity's state, and whether a state matches what a yes/no question asks.
enum AskStateWords {
    /// The word to say for the entity's current state ("open", "locked", "home", "idle").
    static func word(for e: AskEntry) -> String {
        let s = e.state.state
        if s == "unavailable" { return "unavailable" }
        if s == "unknown" { return "unknown" }
        switch e.domain {
        case "binary_sensor":
            switch e.deviceClass {
            case "door", "window", "garage_door", "opening": return s == "on" ? "open" : "closed"
            case "motion", "vibration", "moving": return s == "on" ? "motion detected" : "clear"
            case "occupancy", "presence": return s == "on" ? "occupied" : "clear"
            case "problem", "tamper", "smoke", "gas", "carbon_monoxide", "moisture": return s == "on" ? "triggered" : "clear"
            case "running": return s == "on" ? "running" : "not running"
            default: return s
            }
        case "person": return s == "home" ? "home" : (s == "not_home" ? "away" : "at \(s.replacingOccurrences(of: "_", with: " "))")
        case "lock", "cover", "valve", "media_player", "camera", "vacuum", "alarm_control_panel", "weather", "climate":
            return s.replacingOccurrences(of: "_", with: " ")
        case "automation": return s == "on" ? "enabled" : "disabled"
        default: return s.replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Whether the entity's state is the one `predicate` asks about; nil when the predicate does not apply to this entity.
    static func matches(_ e: AskEntry, _ p: AskPredicate) -> Bool? {
        let s = e.state.state
        let binaryContact = e.domain == "binary_sensor" && ["door", "window", "garage_door", "opening"].contains(e.deviceClass ?? "")
        switch p {
        case .on:
            if e.domain == "media_player" { return !["off", "standby", "unavailable", "unknown"].contains(s) }
            if e.domain == "climate" { return s != "off" }
            return s == "on" || s == "open" || s == "playing" || s == "home" || s == "cleaning" || s == "recording" || s == "streaming" || s == "unlocked"
        case .off:
            if e.domain == "media_player" { return ["off", "standby"].contains(s) }
            return s == "off" || s == "closed" || s == "locked" || s == "idle" || s == "docked" || s == "not_home"
        case .open: return binaryContact ? s == "on" : ["open", "opening", "on"].contains(s)
        case .closed: return binaryContact ? s == "off" : ["closed", "closing", "off"].contains(s)
        case .locked: return e.domain == "lock" ? s == "locked" : nil
        case .unlocked: return e.domain == "lock" ? ["unlocked", "open", "unlocking"].contains(s) : nil
        case .home: return e.domain == "person" ? s == "home" : nil
        case .away: return e.domain == "person" ? s != "home" : nil
        case .playing: return e.domain == "media_player" ? s == "playing" : nil
        case .notPlaying: return e.domain == "media_player" ? s != "playing" : nil
        case .occupied, .detected: return e.domain == "binary_sensor" ? s == "on" : nil
        case .clear: return e.domain == "binary_sensor" ? s == "off" : nil
        case .running: return ["on", "open", "cleaning", "running", "recording"].contains(s)
        case .recording: return e.domain == "camera" ? ["recording", "streaming"].contains(s) : nil
        case .enabled: return e.domain == "automation" ? s == "on" : nil
        case .disabled: return e.domain == "automation" ? s == "off" : nil
        }
    }

    /// The default "active" state a count or list is about when the question names none ("how many lights are on").
    static func defaultPredicate(for kind: AskKind) -> AskPredicate {
        switch kind {
        case .door, .window, .garage, .vent: .open
        case .lock: .unlocked
        case .camera: .recording
        case .motion: .detected
        case .occupancy: .occupied
        case .mediaPlayer: .playing
        case .person: .home
        case .valve: .running
        default: .on
        }
    }

    /// The phrase for the entities that match a predicate, plural-agnostic ("on", "open", "unlocked").
    static func label(_ p: AskPredicate) -> String {
        switch p {
        case .on: "on"
        case .off: "off"
        case .open: "open"
        case .closed: "closed"
        case .locked: "locked"
        case .unlocked: "unlocked"
        case .home: "home"
        case .away: "away"
        case .playing: "playing"
        case .notPlaying: "not playing"
        case .occupied: "occupied"
        case .clear: "clear"
        case .running: "running"
        case .recording: "recording"
        case .detected: "showing motion"
        case .enabled: "enabled"
        case .disabled: "disabled"
        }
    }

    /// The opposite state word, for the "none are X" sentence.
    static func opposite(_ p: AskPredicate, kind: AskKind) -> String {
        switch p {
        case .on: "off"
        case .off: "on"
        case .open: kind == .lock ? "locked" : "closed"
        case .closed: "open"
        case .locked: "unlocked"
        case .unlocked: "locked"
        case .home: "away"
        case .away: "home"
        case .playing: "not playing"
        case .notPlaying: "playing"
        case .occupied, .detected: "clear"
        case .clear: "occupied"
        case .running: "not running"
        case .recording: "not recording"
        case .enabled: "disabled"
        case .disabled: "enabled"
        }
    }
}
