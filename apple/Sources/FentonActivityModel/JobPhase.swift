import Foundation

/// Where a job is (`phase` on the wire, `.agents/platforms/apple/live-activities-per-job.md` §3).
public enum JobPhase: String, Codable, Hashable, Sendable, CaseIterable {
    /// Doing its work now.
    case running
    /// Paused by the person or the device. The time stops.
    case paused
    /// Scheduled to start (a delayed start); the value reads "Starts 5:10 PM".
    case waiting
    /// A device problem. The card turns into a problem card (`problem` is present).
    case problem
    /// Finished. The card reads **Complete** until its linger passes (five minutes) and the engine ends it.
    case done

    /// A phase this build does not know reads as ``running`` so a newer engine never breaks an older app.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobPhase(rawValue: raw) ?? .running
    }
}
