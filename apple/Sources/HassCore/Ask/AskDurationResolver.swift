import Foundation

// MARK: - Duration resolver

/// How long an entity has been in its current state, without trusting a `lastChanged` that a restart reset.
///
/// Order: an annotator that survives restarts (a "real last changed" sensor named in the configuration), then `lastChanged`
/// when it sits outside the restart cluster, then one history call walked back over unavailable and unknown gaps. When the
/// call cannot answer, the result is an honest lower bound ("at least"), never a confident number.
public struct AskDurationResolver: Sendable {
    /// The index the resolver reads.
    public let index: AskableIndex
    /// Where history comes from.
    public let dataSource: AskDataSource

    /// Creates a resolver.
    public init(index: AskableIndex, dataSource: AskDataSource) {
        self.index = index
        self.dataSource = dataSource
    }

    /// How long `entry` has been in its current state.
    public func resolve(_ entry: AskEntry) async -> AskDuration {
        let now = index.now
        let cfg = index.configuration
        // 1. An annotator with a real timestamp.
        for hit in index.annotators[entry.id] ?? [] where hit.rule.role == .since {
            if let date = Self.parse(hit.state.state), date <= now {
                return AskDuration(seconds: now.timeIntervalSince(date), since: date, atLeast: false, source: .annotator)
            }
        }
        let changed = entry.state.lastChanged
        guard changed > .distantPast else { return AskDuration(seconds: 0, since: now, atLeast: true, source: .restartBound) }
        guard AskRestartGuard.isRestartReset(entry.state, restart: index.restartTime, configuration: cfg) else {
            return AskDuration(seconds: now.timeIntervalSince(changed), since: changed, atLeast: false, source: .lastChanged)
        }
        // 2. Restart-reset: one history call.
        let from = now.addingTimeInterval(-cfg.durationWindowDays * 86_400)
        let source = dataSource
        let id = entry.id
        let points = try? await AskDeadline.run(seconds: cfg.callDeadlineSeconds) { try await source.history(entityId: id, from: from, to: now) }
        let bound = AskDuration(seconds: now.timeIntervalSince(changed), since: changed, atLeast: true, source: .restartBound)
        guard let points, !points.isEmpty else { return bound }
        return Self.walkBack(points, current: entry.state.state, from: from, now: now) ?? bound
    }

    /// Walks the periods back from the newest while they hold the current state (or an unavailable gap).
    static func walkBack(_ points: [AskHistoryPoint], current: String, from: Date, now: Date) -> AskDuration? {
        let sorted = points.sorted { $0.at < $1.at }
        guard let last = sorted.last, last.state == current || ["unavailable", "unknown"].contains(last.state) else { return nil }
        var startIndex = sorted.count - 1
        var ix = sorted.count - 1
        while ix >= 0 {
            let s = sorted[ix].state
            if s == current { startIndex = ix } else if !["unavailable", "unknown"].contains(s) { break }
            ix -= 1
        }
        guard sorted[startIndex].state == current else { return nil }
        // The first point is the window's baseline (the state at its start), not a change, when it sits at the window start.
        let reachedWindowStart = startIndex == 0 && sorted[0].at <= from.addingTimeInterval(60)
        let begin = reachedWindowStart ? from : sorted[startIndex].at
        return AskDuration(seconds: now.timeIntervalSince(begin), since: begin, atLeast: reachedWindowStart, source: .history)
    }

    /// Parses an ISO 8601 timestamp state, with or without fractional seconds.
    static func parse(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
}
