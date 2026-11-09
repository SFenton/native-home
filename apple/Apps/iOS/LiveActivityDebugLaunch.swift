#if DEBUG
import FentonActivityModel
import Foundation
import HassCore

/// Debug launch hooks for the Live Activity journeys (`.agents/platforms/apple/live-activities-per-job.md` §12).
///
/// - `FENTON_LIVE_ACTIVITY_FIXTURE=<fixture | group | base64 content-state>` starts real activities locally with fixture
///   content, one per card, so a journey can lock the simulator and read the Lock Screen without Home Assistant or Apple's
///   servers. Names are `HomeActivityFixtures` (`fan`, `vacuum-paused`, `problem-navigation-stuck`) and groups are
///   `stack` (the four-card cap), `jobs`, `vacuum` and so on.
/// - `FENTON_LIVE_ACTIVITY_UPDATE=<fixture>` updates the first activity just started (after two seconds), and
///   `FENTON_LIVE_ACTIVITY_END=1` ends them after four: the same start, update and end a push would do.
enum LiveActivityDebugLaunch {
    static func startIfRequested(client: SystemLiveActivityClient,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let value = environment["FENTON_LIVE_ACTIVITY_FIXTURE"], !value.isEmpty else { return }
        let fixtures = HomeActivityFixtures.fixtures(fromLaunchValue: value)
        guard !fixtures.isEmpty else { return }
        let update = environment["FENTON_LIVE_ACTIVITY_UPDATE"].flatMap { HomeActivityFixtures.fixture($0) }
        let end = environment["FENTON_LIVE_ACTIVITY_END"] == "1"
        Task {
            // Replace any activity a previous launch left, so each run starts clean.
            for record in await client.current() { await client.end(id: record.id, state: nil, dismissal: .immediate) }
            var started: [LiveActivityRecord] = []
            for fixture in fixtures {
                guard let record = try? await client.request(attributes: fixture.attributes, state: fixture.state, staleDate: nil) else {
                    NSLog("FENTON_LIVE_ACTIVITY: the system refused %@", fixture.name)
                    continue
                }
                started.append(record)
                NSLog("FENTON_LIVE_ACTIVITY: started %@ %@", fixture.name, record.id)
            }
            if let update, let first = started.first {
                try? await Task.sleep(for: .seconds(2))
                await client.update(id: first.id, state: update.state, staleDate: nil, relevanceScore: 0,
                                    timestamp: ActivityClock.wholeSecond(Date()))
                NSLog("FENTON_LIVE_ACTIVITY: updated %@", first.id)
            }
            if end {
                try? await Task.sleep(for: .seconds(2))
                for record in started { await client.end(id: record.id, state: nil, dismissal: .immediate) }
                NSLog("FENTON_LIVE_ACTIVITY: ended %d", started.count)
            }
        }
    }
}
#endif
