import Foundation

// MARK: - Line formatter

/// Writes one compact line per entity for a slice: `Name (Room): state for 5 hours; extras`. No ids, no noise.
///
/// A list or object attribute never appears; neither does anything the sensitivity rules name (location, user ids, tokens).
public struct AskLineFormatter: Sendable {
    /// The index lines read names and rooms from.
    public let index: AskableIndex

    /// Creates a formatter.
    public init(index: AskableIndex) { self.index = index }

    /// The name with its room: `Table Light (Kitchen)`.
    public func label(_ e: AskEntry) -> String {
        if let title = index.roomTitle(e.roomKey), !e.shortName.isEmpty, e.shortName != e.displayName { return "\(e.shortName) (\(title))" }
        if let title = index.roomTitle(e.roomKey) { return "\(e.displayName) (\(title))" }
        return e.displayName
    }

    /// One line for `e`. `duration` replaces `lastChanged` when the caller resolved it.
    public func line(_ e: AskEntry, duration: AskDuration? = nil) -> String {
        let word = AskStateWords.word(for: e)
        let since = duration ?? AskDuration(seconds: index.now.timeIntervalSince(e.state.lastChanged), since: e.state.lastChanged, atLeast: AskRestartGuard.isRestartReset(e.state, restart: index.restartTime, configuration: index.configuration), source: .lastChanged)
        let dur = e.state.lastChanged > .distantPast || duration != nil ? " for \(since.spoken)" : ""
        let a = e.state.attributes
        switch e.domain {
        case "light":
            var t = "\(label(e)): \(word)\(dur)"
            if e.state.state == "on", let b = a["brightness"]?.finiteNumber { t += "; \(Int((b / 255 * 100).rounded()))%" }
            return t
        case "climate":
            var t = "\(label(e)): \(word)"
            if let action = a["hvac_action"]?.string { t += ", \(action)" }
            if let cur = a["current_temperature"]?.finiteNumber { t += "; now \(Self.number(cur))°" }
            if let target = a["temperature"]?.finiteNumber { t += ", target \(Self.number(target))" }
            else if let lo = a["target_temp_low"]?.finiteNumber, let hi = a["target_temp_high"]?.finiteNumber { t += ", target \(Self.number(lo))-\(Self.number(hi))" }
            return t
        case "cover":
            var t = "\(label(e)): \(word)"
            if let p = a["current_position"]?.finiteNumber { t += " \(Int(p))%" }
            return t + dur
        case "sensor":
            return "\(label(e)): \(Self.reading(e))"
        case "media_player":
            var t = "\(label(e)): \(word)"
            if e.state.state == "playing", let title = a["media_title"]?.string {
                t += "; \"\(title)\""
                if let artist = a["media_artist"]?.string { t += " by \(artist)" }
            }
            if let v = a["volume_level"]?.finiteNumber, e.state.state != "off" { t += ", vol \(Int((v * 100).rounded()))%" }
            return t
        case "person", "lock", "alarm_control_panel":
            return "\(e.displayName): \(word)\(dur)"
        case "automation", "script":
            var t = "\(e.displayName): \(e.state.state)"
            if let last = a["last_triggered"]?.string, let d = AskDurationResolver.parse(last) { t += "; last ran \(AskDuration.phrase(seconds: index.now.timeIntervalSince(d))) ago" }
            return t
        case "weather":
            return "\(e.displayName): \(word), \(a["temperature"]?.finiteNumber.map(Self.number) ?? "?")°"
        case "vacuum":
            var t = "\(e.displayName): \(word)\(dur)"
            if let b = a["battery_level"]?.finiteNumber { t += "; battery \(Int(b))%" }
            return t
        default:
            return "\(label(e)): \(word)\(dur)"
        }
    }

    /// A numeric reading with its unit, trimmed.
    static func reading(_ e: AskEntry) -> String {
        guard let v = Double(e.state.state) else { return e.state.state }
        let unit = e.state.attributes["unit_of_measurement"]?.string ?? ""
        let spaced = ["%", "°F", "°C", "°"].contains(unit) || unit.isEmpty ? "" : " "
        return number(v) + spaced + unit
    }

    /// A number with at most one decimal and no trailing zero.
    static func number(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
}
