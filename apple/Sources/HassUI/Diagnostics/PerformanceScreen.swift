import HassDesign
import HassTelemetry
import SwiftUI

/// Settings → Performance: what the telemetry has measured on this device, and an export for sharing
/// (pattern: `.agents/patterns/telemetry.md`).
///
/// HIG: [Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) (grouped
/// list of labeled values) and [Activity views](https://developer.apple.com/design/human-interface-guidelines/activity-views)
/// (the export goes through the system share sheet).
public struct PerformanceScreen {

    /// Creates the screen.
    public init() {}


    /// The headline: the median time to settle (or to the first frame when the transition has no end of its own).
    static func navigationValue(_ row: NavigationTelemetry.Row) -> String {
        let headline = row.settled ?? row.firstFrame
        return headline.map { "\(Self.number($0.p50)) ms" } ?? "-"
    }

    /// p50 and p95 for each phase, and the main thread's worst turn.
    static func navigationDetail(_ row: NavigationTelemetry.Row) -> String {
        func pair(_ label: String, _ stats: TelemetryStats?) -> String? {
            stats.map { "\(label) p50 \(Self.number($0.p50)) · p95 \(Self.number($0.p95)) ms" }
        }
        var parts = [pair("first frame", row.firstFrame), pair("settled", row.settled)].compactMap { $0 }
        if let worst = row.turnWorst { parts.append("worst turn \(Self.number(worst.max)) ms") }
        parts.append("\(row.count) samples")
        return parts.joined(separator: " · ")
    }

    /// A turn over a 120 Hz frame (8 ms) at the 95th percentile is a dropped frame during the transition.
    static func navigationTone(_ row: NavigationTelemetry.Row) -> PerformanceRow.Tone {
        guard let p95 = row.turnP95?.p95 else { return .neutral }
        return p95 <= 8 ? .good : p95 <= 16 ? .warning : .bad
    }

    /// A measurement with a fixed number of decimals and no grouping, in the user's locale.
    static func number(_ value: Double, fraction: Int = 0) -> String {
        value.formatted(.number.precision(.fractionLength(fraction)).grouping(.never))
    }

}
