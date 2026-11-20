import Foundation

// MARK: - Restart guard

/// Finds the Home Assistant restart in the states, so "how long" is never answered from a `lastChanged` the restart reset.
///
/// After a restart most entities report `lastChanged` as the restart moment: the value says "since the restart", not
/// "since the state began". The guard marks that moment and the entities that sit on it.
public enum AskRestartGuard {
    /// The restart moment, or nil when no cluster of at least ``AskConfiguration/restartClusterMinimum`` states shares one
    /// ``AskConfiguration/restartClusterSeconds`` window.
    ///
    /// The result is the start of the densest window (the earliest change in it), so every state of the cluster is at or after it.
    public static func detect(states: [EntityState], configuration: AskConfiguration) -> Date? {
        let times = states.map(\.lastChanged).filter { $0 > .distantPast }.sorted()
        guard times.count >= configuration.restartClusterMinimum else { return nil }
        var best = 0, bestStart = 0, lo = 0
        for hi in times.indices {
            while times[hi].timeIntervalSince(times[lo]) > configuration.restartClusterSeconds { lo += 1 }
            if hi - lo + 1 > best { best = hi - lo + 1; bestStart = lo }
        }
        guard best >= configuration.restartClusterMinimum else { return nil }
        return times[bestStart]
    }

    /// Whether `state`'s `lastChanged` sits inside the restart cluster, so it says nothing about when the state began.
    ///
    /// An unavailable or unknown state is never restart-reset: its own start is real.
    public static func isRestartReset(_ state: EntityState, restart: Date?, configuration: AskConfiguration) -> Bool {
        guard let restart, state.state != "unavailable", state.state != "unknown" else { return false }
        return state.lastChanged >= restart.addingTimeInterval(-60)
            && state.lastChanged <= restart.addingTimeInterval(configuration.restartClusterSeconds + 60)
    }
}
