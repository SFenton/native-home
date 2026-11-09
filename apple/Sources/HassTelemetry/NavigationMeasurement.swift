import Foundation

/// One navigation transition being timed (design: `.agents/design/motion.md` §10; pattern: `.agents/patterns/motion.md`).
///
/// It records, under the surface's signpost name and the destination's page:
/// - the **first frame** (``Telemetry/Phase/firstFrame``): the intent until the destination is on screen;
/// - **settled** (``Telemetry/Phase/settled``): the intent until the transition completes. This is also the signpost interval
///   Instruments and `XCTOSSignpostMetric` read;
/// - the transition's main-thread cost (``MainThreadCostMeter``): the 95th percentile and the longest run-loop turn.
///
/// The cost meter and the log run only while ``Telemetry/isEnabled``; the signposts are always emitted. Main actor only.
@MainActor
public final class NavigationMeasurement {
    /// The kinds of transition (each is a ``Telemetry/Name``).
    public enum Surface: String, CaseIterable, Sendable {
        case tabSwitch, push, pop, sheetPresent, sheetDismiss, zoomOpen, zoomClose

        /// The signpost and log name.
        public var name: StaticString {
            switch self {
            case .tabSwitch: Telemetry.Name.tabSwitch
            case .push: Telemetry.Name.push
            case .pop: Telemetry.Name.pop
            case .sheetPresent: Telemetry.Name.sheetPresent
            case .sheetDismiss: Telemetry.Name.sheetDismiss
            case .zoomOpen: Telemetry.Name.zoomOpen
            case .zoomClose: Telemetry.Name.zoomClose
            }
        }

        /// The name as the log stores it (`"Push"`).
        public var kind: String { "\(name)" }

        /// The name for people, in Settings → Performance.
        public var title: String {
            switch self {
            case .tabSwitch: "Tab switch"
            case .push: "Push"
            case .pop: "Pop"
            case .sheetPresent: "Sheet opens"
            case .sheetDismiss: "Sheet closes"
            case .zoomOpen: "Zoom opens"
            case .zoomClose: "Zoom closes"
            }
        }
    }

    /// The transition being timed.
    public let surface: Surface
    /// The destination (a tab or page name).
    public let page: String
    private let interval: Telemetry.Interval
    private var meter: MainThreadCostMeter?
    private var hasFirstFrame = false
    private var isFinished = false

    private init(surface: Surface, page: String, measuresCost: Bool) {
        self.surface = surface
        self.page = page
        interval = Telemetry.begin(surface.name, page: page)
        if measuresCost {
            let meter = MainThreadCostMeter()
            meter.begin()
            self.meter = meter
        }
    }

    /// Starts timing at the intent.
    /// - Parameters:
    ///   - surface: The kind of transition.
    ///   - page: The destination's name.
    ///   - measuresCost: Whether to meter the main thread too; defaults to whether the in-app log records.
    public static func begin(_ surface: Surface, page: String, measuresCost: Bool = Telemetry.isEnabled) -> NavigationMeasurement {
        NavigationMeasurement(surface: surface, page: page, measuresCost: measuresCost)
    }

    /// The destination is on screen. Call it on the first display tick after it appeared; later calls do nothing.
    public func firstFrame() {
        guard !hasFirstFrame, !isFinished else { return }
        hasFirstFrame = true
        Telemetry.lap(interval, phase: .firstFrame)
    }

    /// The transition has completed. Records the first frame too if nothing did, ends the interval and the cost meter.
    public func settled() {
        guard !isFinished else { return }
        firstFrame()
        isFinished = true
        Telemetry.end(interval, detail: Telemetry.Phase.settled.rawValue)
        if let meter {
            let report = meter.finish()
            self.meter = nil
            Telemetry.record(surface.name, page: page, phase: .p95Turn, value: report.p95TurnMs)
            Telemetry.record(surface.name, page: page, phase: .worstTurn, value: report.worstTurnMs)
        }
    }

    /// The transition never completed (the destination went away first): ends the interval without recording a result.
    public func cancel() {
        guard !isFinished else { return }
        isFinished = true
        Telemetry.signposter.endInterval(surface.name, interval.state, "cancelled")
        if let meter {
            _ = meter.finish()
            self.meter = nil
        }
    }
}
