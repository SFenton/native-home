import Foundation

/// One telemetry sample.
public struct TelemetryRecord: Codable, Equatable, Sendable {
    /// When it was recorded.
    public var date: Date
    /// What it measures: a ``Telemetry/Name`` value or a counter name.
    public var kind: String
    /// The page it belongs to, when known.
    public var page: String?
    /// Duration in milliseconds, for intervals.
    public var durationMs: Double?
    /// A number that goes with it (entities changed, hitch milliseconds, bytes).
    public var value: Double?
    /// A short note (`hit`, `304`, an entity id).
    public var detail: String?

    /// Creates a record.
    public init(date: Date = .now, kind: String, page: String? = nil, durationMs: Double? = nil, value: Double? = nil, detail: String? = nil) {
        self.date = date
        self.kind = kind
        self.page = page
        self.durationMs = durationMs
        self.value = value
        self.detail = detail
    }
}

/// Summary statistics for one kind of record.
public struct TelemetryStats: Codable, Equatable, Sendable {
    /// How many samples.
    public var count: Int
    /// Mean duration (or value, for point events) in milliseconds.
    public var mean: Double
    /// 50th percentile.
    public var p50: Double
    /// 95th percentile.
    public var p95: Double
    /// Largest sample.
    public var max: Double

    /// Summarizes `samples`; `nil` when empty.
    public init?(_ samples: [Double]) {
        guard !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        count = sorted.count
        mean = sorted.reduce(0, +) / Double(sorted.count)
        p50 = Self.percentile(sorted, 0.5)
        p95 = Self.percentile(sorted, 0.95)
        max = sorted[sorted.count - 1]
    }

    /// Nearest-rank percentile of an ascending array.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[Swift.max(0, Swift.min(sorted.count - 1, rank - 1))]
    }
}

/// Scroll smoothness for one page: frames drawn while scrolling and how many missed their deadline.
public struct ScrollStats: Codable, Equatable, Sendable {
    /// Seconds spent scrolling.
    public var scrollSeconds: Double = 0
    /// Frames drawn while scrolling.
    public var frames: Int = 0
    /// Frames that missed their deadline.
    public var hitches: Int = 0
    /// Total time past deadlines, in milliseconds.
    public var hitchMs: Double = 0
    /// The longest frame, in milliseconds.
    public var worstFrameMs: Double = 0

    /// Milliseconds of hitch per second of scrolling, Apple's hitch-time ratio (under 5 is good, over 10 is
    /// noticeable).
    public var hitchRatio: Double { scrollSeconds > 0 ? hitchMs / scrollSeconds : 0 }

    /// Creates empty stats.
    public init() {}
}

/// The exported telemetry file.
public struct TelemetryExport: Codable, Sendable {
    /// When it was exported.
    public var exportedAt: Date
    /// Build and device facts.
    public var environment: [String: String]
    /// Counter totals.
    public var counters: [String: Int]
    /// Stats per record kind, and per kind and page as `kind@page`.
    public var stats: [String: TelemetryStats]
    /// Navigation phases (`Push.settled`, `TabSwitch.firstFrame@Home`, `Push.worstTurn`): see ``TelemetryLog/phaseStats``.
    public var phases: [String: TelemetryStats]
    /// Scroll smoothness per page.
    public var scroll: [String: ScrollStats]
    /// The most recent samples, oldest first.
    public var records: [TelemetryRecord]
}
