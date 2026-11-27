import Foundation

// MARK: - Duration

/// How long an entity has been in its state, and how sure the answer is.
public struct AskDuration: Sendable, Equatable {
    /// Where the start came from.
    public enum Source: String, Sendable {
        /// An annotator that survives restarts and blips (a "real last changed" sensor).
        case annotator
        /// The entity's own `lastChanged`.
        case lastChanged
        /// One history call, walked back over unavailable and unknown gaps.
        case history
        /// `lastChanged`, but the restart reset it and history did not answer: a lower bound only.
        case restartBound
    }

    /// Elapsed seconds from the start to now.
    public var seconds: TimeInterval
    /// The start of the state, or the earliest known moment when ``atLeast``.
    public var since: Date
    /// True when the state is at least this old (the window or the restart capped what could be seen).
    public var atLeast: Bool
    /// Where the start came from.
    public var source: Source

    /// Creates a duration.
    public init(seconds: TimeInterval, since: Date, atLeast: Bool, source: Source) {
        self.seconds = max(0, seconds)
        self.since = since
        self.atLeast = atLeast
        self.source = source
    }

    /// The span as people say it: seconds under 90 s, minutes under 90 min, hours under 48 h, days beyond.
    public static func phrase(seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        func num(_ v: Double, _ unit: String, decimals: Bool) -> String {
            let rounded = decimals && v < 10 ? (v * 10).rounded() / 10 : v.rounded()
            let text = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
            return "\(text) \(unit)\(rounded == 1 ? "" : "s")"
        }
        if s < 90 { return num(s, "second", decimals: false) }
        if s < 90 * 60 { return num(s / 60, "minute", decimals: false) }
        if s < 48 * 3600 { return num(s / 3600, "hour", decimals: true) }
        return num(s / 86_400, "day", decimals: true)
    }

    /// "for 5 hours" or "for at least 7 days".
    public var spoken: String { (atLeast ? "at least " : "") + Self.phrase(seconds: seconds) }
}
