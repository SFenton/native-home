import Foundation

/// A control was pressed and Home Assistant has not confirmed it (`pending` on the wire).
///
/// Written **only by the app** (`HomeActivityActionHandler`), never by the engine, so any push from Home Assistant
/// clears it (`.agents/platforms/apple/live-activities-per-job.md` §7).
public struct ActivityPending: Codable, Hashable, Sendable {
    /// The control that was pressed (`stop`).
    public var control: String
    /// What the card says in place of the buttons ("Stopping…").
    public var label: String
    /// When the press happened, whole Unix seconds.
    public var sinceTs: Double

    /// Creates a pending state.
    public init(control: String, label: String, sinceTs: Double) {
        self.control = control
        self.label = label
        self.sinceTs = sinceTs
    }

    private enum CodingKeys: String, CodingKey {
        case control, label
        case sinceTs = "since_ts"
    }

    /// The words for a control: "Stopping…", "Pausing…", "Resuming…", "Docking…", "Completing…".
    public static func label(forControl control: String) -> String {
        switch control {
        case "stop", "cancel", "cancel_timer": "Stopping…"
        case "pause": "Pausing…"
        case "resume": "Resuming…"
        case "dock": "Docking…"
        case "done": "Completing…"
        case "try_again": "Trying again…"
        default: "Working…"
        }
    }
}

/// The clock rules for the app's own writes.
///
/// ActivityKit drops an update whose timestamp is older than the content it already holds, and the relay stamps a
/// push `max(ceil(now), last + 1)`. The app therefore stamps **whole seconds, never in the future**, so the engine's
/// confirmation is always newer (§7.5).
public enum ActivityClock {
    /// How long a pending state lasts before the views give the buttons back (§7.1).
    public static let pendingStaleInterval: TimeInterval = 20

    /// `date` rounded down to a whole second.
    public static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// The stale date for a pending write made at `now`.
    public static func pendingStaleDate(from now: Date) -> Date {
        wholeSecond(now).addingTimeInterval(pendingStaleInterval)
    }
}
