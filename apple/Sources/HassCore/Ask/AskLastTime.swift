import Foundation

// MARK: - Last time

/// When an entity was last in a state.
public enum AskLastTime: Sendable, Equatable {
    /// It is in that state now, since this duration.
    case current(AskDuration)
    /// It entered that state this long ago, per history.
    case past(seconds: TimeInterval, windowDays: Double)
    /// An automation or script last ran this long ago.
    case ran(seconds: TimeInterval)
    /// An automation or script has no recorded run.
    case neverRan
    /// No row in the window shows it.
    case notRecorded(windowDays: Double)
}

/// Finds when an entity was last in a state: its current period, else history narrow first and widened once.
public struct AskLastTimeResolver: Sendable {
    /// The index the resolver reads.
    public let index: AskableIndex
    /// Where history comes from.
    public let dataSource: AskDataSource
    let durations: AskDurationResolver

    /// Creates a resolver.
    public init(index: AskableIndex, dataSource: AskDataSource) {
        self.index = index
        self.dataSource = dataSource
        durations = AskDurationResolver(index: index, dataSource: dataSource)
    }

    /// When `entry` was last in the state `predicate` names.
    public func resolve(_ entry: AskEntry, predicate: AskPredicate?) async -> AskLastTime {
        let cfg = index.configuration
        if entry.domain == "automation" || entry.domain == "script" {
            guard let text = entry.state.attributes["last_triggered"]?.string, let date = AskDurationResolver.parse(text) else { return .neverRan }
            return .ran(seconds: max(0, index.now.timeIntervalSince(date)))
        }
        let p = predicate ?? AskStateWords.defaultPredicate(for: entry.kind)
        if AskStateWords.matches(entry, p) == true { return .current(await durations.resolve(entry)) }
        let now = index.now
        let source = dataSource
        let id = entry.id
        for window in [cfg.lastTimeNarrowHours / 24, cfg.lastTimeWideDays] {
            let from = now.addingTimeInterval(-window * 86_400)
            let points = try? await AskDeadline.run(seconds: cfg.callDeadlineSeconds) { try await source.history(entityId: id, from: from, to: now) }
            if let points, let hit = points.sorted(by: { $0.at > $1.at }).first(where: { Self.matches(entry, p, state: $0.state) && $0.at >= from }) {
                return .past(seconds: max(0, now.timeIntervalSince(hit.at)), windowDays: window)
            }
        }
        return .notRecorded(windowDays: cfg.lastTimeWideDays)
    }

    static func matches(_ entry: AskEntry, _ p: AskPredicate, state: String) -> Bool {
        var probe = entry
        probe.state = EntityState(entityId: entry.id, state: state, attributes: entry.state.attributes, lastChanged: entry.state.lastChanged)
        return AskStateWords.matches(probe, p) == true
    }
}
