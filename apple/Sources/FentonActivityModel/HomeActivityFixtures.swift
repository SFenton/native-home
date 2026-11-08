import Foundation

/// One fixture card: the attributes and content an activity would hold.
public struct ActivityFixture: Equatable, Sendable, Identifiable {
    /// The fixture's name (`fan`, `problem-navigation-stuck`).
    public var name: String
    /// The static attributes.
    public var attributes: HomeActivityAttributes
    /// The content.
    public var state: HomeActivityState
    /// Past its stale date (the pending-stale scenario).
    public var isStale: Bool

    public var id: String { name }

    /// Creates a fixture.
    public init(name: String, attributes: HomeActivityAttributes, state: HomeActivityState, isStale: Bool = false) {
        self.name = name
        self.attributes = attributes
        self.state = state
        self.isStale = isStale
    }

    /// The card, with times counted from `now`.
    public func card(now: Date = Date()) -> ActivityCard {
        ActivityCard(attributes: attributes, state: state, isStale: isStale, now: now)
    }
}

/// Fixture content for the debug gallery, the debug launch hook and tests: every card on the canvas
/// (`.agents/platforms/apple/live-activities-per-job.md` §11), in the shapes the relay sends, with times relative to
/// `now` so a countdown is always ticking when it is drawn.
public enum HomeActivityFixtures {
    // MARK: - Names

    /// Fan timers, dishwasher and laundry, running.
    public static let jobNames = ["fan", "fan-long", "fan-xlong", "dishwasher", "dishwasher-long", "dishwasher-percent", "dishwasher-paused",
                                  "dishwasher-waiting", "dryer", "dryer-estimated", "washer"]
    /// Finished jobs: **Complete**.
    public static let completeNames = ["dishwasher-complete", "dryer-complete", "washer-complete", "hotflash-complete"]
    /// Vacuum rooms.
    public static let vacuumNames = ["vacuum", "vacuum-mopping", "vacuum-cleaning", "vacuum-drawn", "vacuum-paused", "vacuum-long"]
    /// Hot flash.
    public static let hotFlashNames = ["hotflash-cooling", "hotflash-holding", "hotflash-bysam", "hotflash-wholebed", "hotflash-byhome",
                                       "hotflash-alex-bysam"]
    /// A press waiting, unconfirmed, and failed.
    public static let stateNames = ["fan-pending", "fan-pending-stale", "fan-notice", "problem-completing"]
    /// Four jobs: the cap.
    public static let stackNames = ["fan", "dishwasher-percent", "washer", "dryer"]
    /// Every problem row of the spec's §5 table, as the table has it.
    public static let problemNames = problemRows.map { "problem-" + $0.slug }
    /// The same rows with Done flipped: added to a row that has no task, taken off one that has.
    public static let problemFlippedNames = problemRows.map { "problem-" + $0.slug + ($0.hasTask ? "-nodone" : "-done") }

    /// Named groups the gallery shows together.
    public static let groups: [String: [String]] = [
        "jobs": jobNames, "complete": completeNames, "vacuums": vacuumNames, "hotflash": hotFlashNames,
        "states": stateNames, "stack": stackNames, "problems": problemNames, "problems-flipped": problemFlippedNames,
    ]

    /// Every fixture name, once.
    public static var allNames: [String] {
        var seen = Set<String>()
        return (jobNames + completeNames + vacuumNames + hotFlashNames + stateNames + problemNames + problemFlippedNames)
            .filter { seen.insert($0).inserted }
    }

    // MARK: - Lookup

    /// The fixture for a name, or nil.
    public static func fixture(_ name: String, now: Date = Date()) -> ActivityFixture? {
        let t = now.timeIntervalSince1970
        switch name {
        case "fan": return job(name, fan(t, end: 282))
        case "fan-long": return job(name, fan(t, end: 3_882, room: "master", title: "Bedroom 1 Closet Fan"))
        case "fan-xlong": return job(name, fan(t, end: 282, room: "master", title: "Bedroom 1 Closet Exhaust Fan"))
        case "fan-pending":
            let base = fan(t, end: 282)
            return ActivityFixture(name: name, attributes: base.0, state: base.1.awaiting(control: "stop", now: now))
        case "fan-pending-stale":
            let base = fan(t, end: 282)
            return ActivityFixture(name: name, attributes: base.0, state: base.1.awaiting(control: "stop", now: now), isStale: true)
        case "fan-notice":
            let base = fan(t, end: 282)
            return ActivityFixture(name: name, attributes: base.0, state: base.1.failing(notice: "Couldn't reach Home"))
        case "dishwasher": return job(name, dishwasher(t))
        case "dishwasher-long":
            // An H:MM:SS countdown (1:04:42): the compact island's time takes the wider template.
            let (attributes, initial) = dishwasher(t)
            var state = initial
            state.value = ActivityValue(kind: .countdown, startTs: t - 600, endTs: t + 3_882)
            return ActivityFixture(name: name, attributes: attributes, state: state)
        case "dishwasher-percent":
            let (attributes, initial) = dishwasher(t)
            var state = initial
            state.value = .percent
            state.progress = 0.62
            return ActivityFixture(name: name, attributes: attributes, state: state)
        case "dishwasher-paused":
            let (attributes, initial) = dishwasher(t)
            var state = initial
            state.phase = .paused
            state.value = .text("Paused")
            state.controls = [ActivityControl(id: "resume", title: "Resume"), ActivityControl(id: "stop", title: "Stop")]
            return ActivityFixture(name: name, attributes: attributes, state: state)
        case "dishwasher-waiting":
            let (attributes, initial) = dishwasher(t)
            var state = initial
            state.phase = .waiting
            state.value = .text("Starts 5:10 PM")
            state.controls = []
            return ActivityFixture(name: name, attributes: attributes, state: state)
        case "dishwasher-complete": return job(name, complete(dishwasher(t)))
        case "dryer": return job(name, laundry("dryer", title: "Dryer", symbol: "dryer", start: t - 1_930))
        case "dryer-estimated":
            let (attributes, initial) = laundry("dryer", title: "Dryer", symbol: "dryer", start: t - 600)
            var state = initial
            state.value = .countdown(end: Date(timeIntervalSince1970: t + 1_200), estimated: true)
            return ActivityFixture(name: name, attributes: attributes, state: state)
        case "dryer-complete": return job(name, complete(laundry("dryer", title: "Dryer", symbol: "dryer", start: t - 1_930)))
        case "washer": return job(name, laundry("washer", title: "Washing Machine", symbol: "washer", start: t - 372))
        case "washer-complete": return job(name, complete(laundry("washer", title: "Washing Machine", symbol: "washer", start: t - 372)))
        case "vacuum": return job(name, vacuum(headline: "Vacuuming Kitchen", short: "Kitchen", tint: "cleaning"))
        case "vacuum-mopping": return job(name, vacuum(headline: "Mopping Kitchen", short: "Kitchen", tint: "water"))
        case "vacuum-cleaning": return job(name, vacuum(headline: "Cleaning Living Room", short: "Living Rm", tint: "cleaning"))
        case "vacuum-drawn": return job(name, vacuum(headline: "Cleaning Main Floor area", short: "Area", tint: "cleaning"))
        case "vacuum-long": return job(name, vacuum(headline: "Vacuuming Bedroom 1 Closet", short: "Closet", tint: "cleaning"))
        case "vacuum-paused":
            // Paused is the word and the Resume button; nothing dims.
            let (attributes, initial) = vacuum(headline: "Paused in Kitchen", short: "Paused", tint: "cleaning")
            var state = initial
            state.phase = .paused
            state.controls = [ActivityControl(id: "resume", title: "Resume"), ActivityControl(id: "dock", title: "Dock", role: .secondary)]
            return ActivityFixture(name: name, attributes: attributes, state: state)
        case "hotflash-cooling":
            let (attributes, initial) = hotFlash(t, line: "Your side")
            var state = initial
            state.value = .text("Cooling")
            state.progress = 0.45
            return ActivityFixture(name: name, attributes: attributes, state: state)
        case "hotflash-holding": return job(name, hotFlash(t, line: "Your side"))
        case "hotflash-alex-bysam": return job(name, hotFlash(t, line: "Alex's side · by Sam"))
        case "hotflash-bysam": return job(name, hotFlash(t, line: "Your side · by Sam"))
        case "hotflash-byhome": return job(name, hotFlash(t, line: "Your side · by Home"))
        case "hotflash-wholebed": return job(name, hotFlash(t, line: "Whole bed", remaining: 845))
        case "hotflash-complete": return job(name, complete(hotFlash(t, line: "Your side")))
        case "problem-completing":
            guard let row = problemRows.first else { return nil }
            var base = problem(row, hasTask: true, now: t)
            base.state = base.state.awaiting(control: "done", now: now)
            return ActivityFixture(name: name, attributes: base.attributes, state: base.state)
        default: break
        }
        guard name.hasPrefix("problem-") else { return nil }
        for row in problemRows {
            let base = "problem-" + row.slug
            if name == base { return named(name, problem(row, hasTask: row.hasTask, now: t)) }
            if name == base + (row.hasTask ? "-nodone" : "-done") { return named(name, problem(row, hasTask: !row.hasTask, now: t)) }
        }
        return nil
    }

    /// The fixtures a debug launch value names: a fixture name, a group name, or the base64 of a content-state JSON (which
    /// starts a generic activity). Empty when it names nothing.
    public static func fixtures(fromLaunchValue value: String, now: Date = Date()) -> [ActivityFixture] {
        if let one = fixture(value, now: now) { return [one] }
        if let names = groups[value] { return names.compactMap { fixture($0, now: now) } }
        guard let data = Data(base64Encoded: value), let state = try? HomeActivityState.decode(data) else { return [] }
        return [ActivityFixture(name: "custom", attributes: HomeActivityAttributes(tag: "job.custom", title: "Custom", kind: "generic"), state: state)]
    }

    // MARK: - Builders

    private typealias Base = (attributes: HomeActivityAttributes, state: HomeActivityState)

    private static func job(_ name: String, _ base: Base) -> ActivityFixture {
        ActivityFixture(name: name, attributes: base.attributes, state: base.state)
    }

    private static func named(_ name: String, _ base: Base) -> ActivityFixture {
        ActivityFixture(name: name, attributes: base.attributes, state: base.state)
    }

    private static func fan(_ t: TimeInterval, end: TimeInterval, room: String = "guest", title: String = "Guest Bath Fan") -> Base {
        (HomeActivityAttributes(tag: "job.fan.\(room)", title: title, kind: "fan", symbol: "fan", tint: "air"),
         HomeActivityState(value: ActivityValue(kind: .countdown, startTs: t - 300, endTs: t + end),
                           controls: [ActivityControl(id: "stop", title: "Stop")],
                           url: "/sfenton-react-dash/home?path=\(room)-bathroom"))
    }

    private static func dishwasher(_ t: TimeInterval) -> Base {
        (HomeActivityAttributes(tag: "job.dishwasher", title: "Dishwasher", kind: "dishwasher", symbol: "dishwasher", tint: "cleaning"),
         HomeActivityState(value: ActivityValue(kind: .countdown, startTs: t - 8_000, endTs: t + 2_520),
                           controls: [ActivityControl(id: "stop", title: "Stop")],
                           url: "/sfenton-react-dash/home?path=kitchen"))
    }

    private static func laundry(_ kind: String, title: String, symbol: String, start: TimeInterval) -> Base {
        (HomeActivityAttributes(tag: "job.\(kind)", title: title, kind: kind, symbol: symbol, tint: "cleaning"),
         HomeActivityState(value: ActivityValue(kind: .countup, startTs: start), url: "/sfenton-react-dash/home?path=laundry"))
    }

    /// A vacuum room as the engine sends it: no `value` and no `progress` (no time and no bar anywhere), the headline as the
    /// big line and `short` for the compact island.
    private static func vacuum(headline: String, short: String, tint: String) -> Base {
        (HomeActivityAttributes(tag: "job.vacuum.demo_vacuum_1", title: "Main Floor Vacuum", kind: "vacuum", symbol: "vacuum", tint: tint),
         HomeActivityState(headline: headline, short: short,
                           controls: [ActivityControl(id: "pause", title: "Pause"), ActivityControl(id: "dock", title: "Dock", role: .secondary)],
                           url: "/sfenton-react-dash/home?path=vacuums"))
    }

    private static func hotFlash(_ t: TimeInterval, line: String, remaining: TimeInterval = 760) -> Base {
        (HomeActivityAttributes(tag: "job.hot_flash", title: "Hot Flash", kind: "hot_flash", symbol: "hot_flash", tint: "cooling"),
         HomeActivityState(detail: line, value: ActivityValue(kind: .countdown, startTs: t - 140, endTs: t + remaining),
                           controls: [ActivityControl(id: "stop", title: "Stop")],
                           url: "/sfenton-react-dash/home?path=master-bedroom"))
    }

    private static func complete(_ base: Base) -> Base {
        var state = base.state
        state.phase = .done
        // The engine's Complete card: progress 1.0, no controls, value text "Complete".
        state.value = .text("Complete")
        state.progress = 1
        state.controls = []
        return (base.attributes, state)
    }

    // MARK: - Problems (spec §5)

    /// One row of the §5 table.
    struct ProblemRow {
        var code: String
        var severity: ActivityProblem.Severity
        var icon: String
        var problem: String
        var message: String
        var buttons: [(id: String, title: String)]
        var hasTask: Bool
        var chips: [String] = []
        var device = "Main Floor Vacuum"
        var tag = "job.vacuum.demo_vacuum_1"
        var kind = "vacuum"
        var symbol = "vacuum"

        /// `navigation-stuck`.
        var slug: String { code.replacingOccurrences(of: ".", with: "-") }
    }

    static let problemRows: [ProblemRow] = [
        ProblemRow(code: "navigation.stuck", severity: .critical, icon: "alert", problem: "Stuck in Kitchen",
                   message: "Move it somewhere flat, then tap Resume.", buttons: [("resume", "Resume"), ("dock", "Dock")], hasTask: true),
        ProblemRow(code: "navigation.target_unreachable", severity: .critical, icon: "door", problem: "Can't reach Office",
                   message: "A door may be closed. Open it, then tap Resume.", buttons: [("resume", "Resume"), ("dock", "Dock")], hasTask: true),
        ProblemRow(code: "navigation.dock_unreachable", severity: .critical, icon: "dock", problem: "Can't get back to the dock",
                   message: "Clear the way to the dock or carry it there.", buttons: [("try_again", "Try Again")], hasTask: true),
        ProblemRow(code: "navigation.ramp_hazard", severity: .critical, icon: "edge", problem: "Stopped at a drop or ramp",
                   message: "Move it away from the edge, then tap Resume.", buttons: [("resume", "Resume"), ("dock", "Dock")], hasTask: true),
        ProblemRow(code: "maintenance.main_brush_jammed", severity: .critical, icon: "brush", problem: "Main brush jammed",
                   message: "Turn it over, clear the brush, then tap Resume.", buttons: [("resume", "Resume"), ("dock", "Dock")], hasTask: true),
        ProblemRow(code: "maintenance.side_brush_jammed", severity: .critical, icon: "brush", problem: "Side brush jammed",
                   message: "Untangle the side brush, then tap Resume.", buttons: [("resume", "Resume"), ("dock", "Dock")], hasTask: true),
        ProblemRow(code: "power.critical_battery", severity: .critical, icon: "battery", problem: "Battery critically low",
                   message: "Carry it to the dock to charge.", buttons: [], hasTask: false),
        ProblemRow(code: "power.low_battery", severity: .warning, icon: "battery", problem: "Battery low",
                   message: "Heading to the dock. It finishes Kitchen after charging.", buttons: [], hasTask: false),
        ProblemRow(code: "mop.clean_water_empty", severity: .warning, icon: "water", problem: "Clean water tank empty",
                   message: "Refill the clean water tank on the dock, then tap Resume.", buttons: [("resume", "Resume")], hasTask: true),
        ProblemRow(code: "mop.dirty_water_unavailable", severity: .warning, icon: "waste", problem: "Wastewater tank full or missing",
                   message: "Empty the wastewater tank and seat it firmly.", buttons: [("resume", "Resume")], hasTask: true),
        ProblemRow(code: "mop.attachment_missing", severity: .warning, icon: "mop", problem: "Mop pads missing",
                   message: "Attach the mop pads, or it vacuums only.", buttons: [("vacuum_only", "Vacuum Only")], hasTask: true),
        ProblemRow(code: "mop.vacuum_only_fallback", severity: .warning, icon: "mop", problem: "Vacuuming only",
                   message: "Mopping isn't available. Check the mop attachment, water tanks and pads.", buttons: [], hasTask: false,
                   device: "Music Room Vacuum", tag: "job.vacuum.demo_vacuum_2"),
        ProblemRow(code: "dock.cover_open", severity: .warning, icon: "bag", problem: "Dock cover open",
                   message: "Check the dust bag is in, then close the cover.", buttons: [], hasTask: true),
        ProblemRow(code: "dock.dustbag_blocked", severity: .warning, icon: "bag", problem: "Dust bag full",
                   message: "Replace the dust bag in the dock.", buttons: [], hasTask: true),
        ProblemRow(code: "vendor.unknown_error_88", severity: .critical, icon: "question", problem: "Stopped with an error",
                   message: "Check the robot, then tap Resume.", buttons: [("resume", "Resume"), ("dock", "Dock")], hasTask: false, chips: ["Error 88"]),
        ProblemRow(code: "unmapped.wheel_suspended", severity: .critical, icon: "question", problem: "Stopped with an error",
                   message: "The robot says “Wheel suspended”. Check it, then tap Resume.", buttons: [("resume", "Resume"), ("dock", "Dock")], hasTask: false),
        ProblemRow(code: "dishwasher.actionrequired", severity: .warning, icon: "door_dish", problem: "Needs attention",
                   message: "Check the dishwasher's display.", buttons: [], hasTask: false,
                   device: "Dishwasher", tag: "job.dishwasher", kind: "dishwasher", symbol: "dishwasher"),
        ProblemRow(code: "dishwasher.error", severity: .critical, icon: "question", problem: "Stopped with an error",
                   message: "Check the dishwasher's display.", buttons: [], hasTask: false,
                   device: "Dishwasher", tag: "job.dishwasher", kind: "dishwasher", symbol: "dishwasher"),
        ProblemRow(code: "dishwasher.rinse_aid", severity: .warning, icon: "water", problem: "Rinse aid low",
                   message: "Refill the rinse aid.", buttons: [], hasTask: true,
                   device: "Dishwasher", tag: "job.dishwasher", kind: "dishwasher", symbol: "dishwasher"),
    ]

    private static func problem(_ row: ProblemRow, hasTask: Bool, now: TimeInterval) -> Base {
        // As the engine sends them: the first control carries no role (primary), the others say `secondary`.
        var controls = row.buttons.map { ActivityControl(id: $0.id, title: $0.title) }
        if hasTask { controls.append(ActivityControl(id: "done", title: "Done")) }
        let content = ActivityProblem(severity: row.severity, code: row.code, icon: row.icon, problem: row.problem, message: row.message,
                                      chips: row.chips, taskId: hasTask ? "task-1042" : nil)
        return (HomeActivityAttributes(tag: row.tag, title: row.device, kind: row.kind, symbol: row.symbol, tint: "cleaning"),
                HomeActivityState(phase: .problem, value: .text(row.severity == .critical ? "Needs help" : "Attention"),
                                controls: controls, problem: content, url: "/sfenton-react-dash/home?path=vacuums"))
    }
}
