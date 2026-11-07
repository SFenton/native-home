import Foundation

/// A job in a Phase 1 (`"v": 1`) content state, which listed every running job and a `focus`. Contract v2 carries one
/// job per activity, so a v1 payload decodes by taking its focused job (`.agents/platforms/apple/live-activities-per-job.md`
/// §3, "A `1` payload decodes by taking its focus job, for one release").
struct LegacyJob: Decodable {
    var id: String
    var title: String
    var status: String
    var phase: String
    var startTs: Double?
    var endTs: Double?
    var estimated: Bool
    var progress: Double?
    var controls: [ActivityControl]

    private enum CodingKeys: String, CodingKey {
        case id, title, status, phase, estimated, progress, controls
        case startTs = "start_ts"
        case endTs = "end_ts"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ""
        phase = try container.decodeIfPresent(String.self, forKey: .phase) ?? "running"
        startTs = try container.decodeIfPresent(Double.self, forKey: .startTs)
        endTs = try container.decodeIfPresent(Double.self, forKey: .endTs)
        estimated = try container.decodeIfPresent(Bool.self, forKey: .estimated) ?? false
        progress = try container.decodeIfPresent(Double.self, forKey: .progress)
        controls = try container.decodeIfPresent([ActivityControl].self, forKey: .controls) ?? []
    }

    /// The v2 state for the job `focus` names (else the first); an empty list is a finished, empty card (an `end`).
    static func state(focusing focus: String?, in jobs: [LegacyJob], url: String?) -> HomeActivityState {
        guard let job = jobs.first(where: { $0.id == focus }) ?? jobs.first else {
            return HomeActivityState(phase: .done, url: url)
        }
        return job.state(url: url)
    }

    private func state(url: String?) -> HomeActivityState {
        var state = HomeActivityState(version: HomeActivityState.currentVersion, headline: title, progress: progress,
                                      controls: controls, url: url)
        switch phase {
        case "paused": state.phase = .paused
        case "waiting": state.phase = .waiting
        case "done": state.phase = .done
        case "attention":
            state.phase = .problem
            state.problem = ActivityProblem(severity: .warning, code: "legacy.attention", icon: "alert",
                                            problem: "Needs attention", message: status)
        case "stopping":
            state.pending = ActivityPending(control: "stop", label: ActivityPending.label(forControl: "stop"), sinceTs: 0)
        default: state.phase = .running
        }
        if let end = endTs, let start = startTs, end > start {
            state.value = ActivityValue(kind: .countdown, startTs: start, endTs: end, estimated: estimated)
        } else if let end = endTs, estimated {
            state.value = ActivityValue(kind: .countdown, endTs: end, estimated: true)
        } else if progress != nil {
            state.value = .percent
        }
        return state
    }
}
