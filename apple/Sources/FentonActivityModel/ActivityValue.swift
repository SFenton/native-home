import Foundation

/// The big figure on a card (`value` on the wire, `.agents/platforms/apple/live-activities-per-job.md` §3).
///
/// Times are **Unix seconds as numbers**. ActivityKit decodes push content with a default `JSONDecoder`, so a `Date`
/// field would read the number as seconds since 2001 and land 31 years early; the wire keeps doubles and ``startDate`` /
/// ``endDate`` convert.
public struct ActivityValue: Codable, Hashable, Sendable {
    /// What the figure is.
    public enum Kind: String, Codable, Hashable, Sendable {
        /// Counts down to ``endTs`` (``startTs`` starts the ring).
        case countdown
        /// Counts up from ``startTs``; ``pausedElapsedS`` freezes it.
        case countup
        /// The state's `progress`, as a percentage.
        case percent
        /// ``text``, at most ``ActivityValue/maxTextLength`` characters.
        case text

        /// An unknown kind reads as ``text`` (which shows nothing without text).
        public init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .text
        }
    }

    /// `value.text` at most.
    public static let maxTextLength = 16

    /// The kind.
    public var kind: Kind
    /// When it started, Unix seconds.
    public var startTs: Double?
    /// When it ends, Unix seconds.
    public var endTs: Double?
    /// A paused count-up shows this many seconds, frozen.
    public var pausedElapsedS: Double?
    /// The end is a guess (the dryer's learned ETA). It still counts down; VoiceOver says "about".
    public var estimated: Bool
    /// The text of a ``Kind/text`` value ("Cooling", "Starts 5:10 PM").
    public var text: String?

    /// Creates a value.
    public init(kind: Kind, startTs: Double? = nil, endTs: Double? = nil, pausedElapsedS: Double? = nil,
                estimated: Bool = false, text: String? = nil) {
        self.kind = kind
        self.startTs = startTs
        self.endTs = endTs
        self.pausedElapsedS = pausedElapsedS
        self.estimated = estimated
        self.text = text
    }

    /// A countdown to `end`.
    public static func countdown(start: Date? = nil, end: Date, estimated: Bool = false) -> ActivityValue {
        ActivityValue(kind: .countdown, startTs: start?.timeIntervalSince1970, endTs: end.timeIntervalSince1970, estimated: estimated)
    }

    /// A count-up from `start`, frozen at `pausedElapsed` seconds while paused.
    public static func countup(start: Date, pausedElapsed: Double? = nil) -> ActivityValue {
        ActivityValue(kind: .countup, startTs: start.timeIntervalSince1970, pausedElapsedS: pausedElapsed)
    }

    /// The state's `progress` as a percentage.
    public static let percent = ActivityValue(kind: .percent)

    /// A word or two.
    public static func text(_ text: String) -> ActivityValue {
        ActivityValue(kind: .text, text: text)
    }

    private enum CodingKeys: String, CodingKey {
        case kind, estimated, text
        case startTs = "start_ts"
        case endTs = "end_ts"
        case pausedElapsedS = "paused_elapsed_s"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
        startTs = try container.decodeIfPresent(Double.self, forKey: .startTs)
        endTs = try container.decodeIfPresent(Double.self, forKey: .endTs)
        pausedElapsedS = try container.decodeIfPresent(Double.self, forKey: .pausedElapsedS)
        estimated = try container.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(startTs, forKey: .startTs)
        try container.encodeIfPresent(endTs, forKey: .endTs)
        try container.encodeIfPresent(pausedElapsedS, forKey: .pausedElapsedS)
        if estimated { try container.encode(true, forKey: .estimated) }
        try container.encodeIfPresent(text, forKey: .text)
    }

    // MARK: - Dates

    /// ``startTs`` as a date.
    public var startDate: Date? { startTs.map { Date(timeIntervalSince1970: $0) } }
    /// ``endTs`` as a date.
    public var endDate: Date? { endTs.map { Date(timeIntervalSince1970: $0) } }

    /// The range a `Text(timerInterval:)` or `ProgressView(timerInterval:)` counts through for a countdown. Without a
    /// start (a countdown that has no ring) the range begins when the end is, so the text still counts to zero; nil
    /// without an end.
    public func countdownRange(now: Date) -> ClosedRange<Date>? {
        guard kind == .countdown, let end = endDate else { return nil }
        let start = min(startDate ?? now, end)
        return min(start, now)...end
    }

    /// The range the ring fills through; nil without both ends or when the end is not after the start.
    public var ringRange: ClosedRange<Date>? {
        guard kind == .countdown, let start = startDate, let end = endDate, end > start else { return nil }
        return start...end
    }
}
