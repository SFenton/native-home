import Foundation
import HassTelemetry

/// A navigation transition to time, with its destination (`MotionPolicy.measure(.push("Living Room"))`).
public enum NavigationTransition: Equatable, Sendable {
    case tabSwitch(String)
    case push(String)
    case pop(String)
    case sheetPresent(String)
    case sheetDismiss(String)
    case zoomOpen(String)
    case zoomClose(String)

    /// The kind of transition.
    public var surface: NavigationMeasurement.Surface {
        switch self {
        case .tabSwitch: .tabSwitch
        case .push: .push
        case .pop: .pop
        case .sheetPresent: .sheetPresent
        case .sheetDismiss: .sheetDismiss
        case .zoomOpen: .zoomOpen
        case .zoomClose: .zoomClose
        }
    }

    /// The destination's name.
    public var page: String {
        switch self {
        case let .tabSwitch(page), let .push(page), let .pop(page), let .sheetPresent(page), let .sheetDismiss(page),
             let .zoomOpen(page), let .zoomClose(page): page
        }
    }
}

/// What the Performance screen and the export show about navigation: per surface, how long a tab switch, push, pop, sheet or zoom took
/// to reach its first frame and to settle, and what it cost the main thread
/// (design: `.agents/design/motion.md` §10; pattern: `.agents/patterns/telemetry.md`).
///
/// The measuring is `NavigationMeasurement` (HassTelemetry) and `MotionPolicy.measure(_:)`; this reads the log back.
public enum NavigationTelemetry {
    /// One surface's numbers.
    public struct Row: Identifiable, Equatable, Sendable {
        public var surface: NavigationMeasurement.Surface
        /// Intent to first frame.
        public var firstFrame: TelemetryStats?
        /// Intent to settled.
        public var settled: TelemetryStats?
        /// The 95th percentile main-thread turn during each transition.
        public var turnP95: TelemetryStats?
        /// The longest main-thread turn during each transition.
        public var turnWorst: TelemetryStats?

        public var id: String { surface.rawValue }
        /// How many transitions were timed.
        public var count: Int { settled?.count ?? firstFrame?.count ?? 0 }
    }

    /// The surfaces that have data, in the order of ``NavigationMeasurement/Surface``.
    /// - Parameter phases: ``TelemetryLog/phaseStats``.
    public static func rows(from phases: [String: TelemetryStats]) -> [Row] {
        NavigationMeasurement.Surface.allCases.compactMap { surface in
            func stats(_ phase: Telemetry.Phase) -> TelemetryStats? { phases["\(surface.kind).\(phase.rawValue)"] }
            let row = Row(surface: surface, firstFrame: stats(.firstFrame), settled: stats(.settled),
                          turnP95: stats(.p95Turn), turnWorst: stats(.worstTurn))
            return row.firstFrame == nil && row.settled == nil ? nil : row
        }
    }

    /// `key=value` pairs for every surface with data, for the perf probe's accessibility label and `tools/ios_navperf.sh`:
    /// `push.n`, `push.first.p50`, `push.first.p95`, `push.settled.p50`, `push.settled.p95`, `push.turn.p95` (the 95th
    /// percentile of the transitions' own 95th-percentile turns) and `push.turn.worst` (the longest turn of any transition),
    /// all in milliseconds. Keys use the surface's raw value (`tabSwitch`, `sheetPresent`).
    /// - Parameter phases: ``TelemetryLog/phaseStats``.
    public static func summary(from phases: [String: TelemetryStats]) -> String {
        func format(_ value: Double) -> String { String(format: "%.2f", value) }
        var pairs: [String] = []
        for row in rows(from: phases) {
            let key = row.surface.rawValue
            pairs.append("\(key).n=\(row.count)")
            if let stats = row.firstFrame { pairs += ["\(key).first.p50=\(format(stats.p50))", "\(key).first.p95=\(format(stats.p95))"] }
            if let stats = row.settled { pairs += ["\(key).settled.p50=\(format(stats.p50))", "\(key).settled.p95=\(format(stats.p95))"] }
            if let stats = row.turnP95 { pairs.append("\(key).turn.p95=\(format(stats.p95))") }
            if let stats = row.turnWorst { pairs.append("\(key).turn.worst=\(format(stats.max))") }
        }
        return pairs.isEmpty ? "none" : pairs.joined(separator: " ")
    }
}
