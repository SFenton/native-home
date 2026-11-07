import Foundation
@testable import FentonActivityModel
import Testing

/// Shared by the model tests: a fixed "now" (2026-10-17 15:00:00 UTC) so countdowns are deterministic.
enum ActivityFixtures {
    static let now = Date(timeIntervalSince1970: 1_792_249_200)
    static var t: TimeInterval { now.timeIntervalSince1970 }

    static func json(_ text: String) throws -> HomeActivityState {
        try HomeActivityState.decode(Data(text.utf8))
    }
}

struct ActivityValueTests {
    private let now = ActivityFixtures.now

    @Test func everyKindDecodesWithSnakeCaseKeysAndUnixSeconds() throws {
        let state = try ActivityFixtures.json("""
        {"v":2,"phase":"running","value":{"kind":"countup","start_ts":1792248440,"paused_elapsed_s":760,"estimated":true,"text":"x"}}
        """)
        let value = try #require(state.value)
        #expect(value.kind == .countup && value.pausedElapsedS == 760 && value.estimated && value.text == "x")
        let start = try #require(value.startDate)
        #expect(Calendar(identifier: .gregorian).component(.year, from: start) == 2026, "a Date read from 2001 would land in 1995")
        for (raw, kind) in [("countdown", ActivityValue.Kind.countdown), ("percent", .percent), ("text", .text), ("countup", .countup), ("surprise", .text)] {
            let decoded = try ActivityFixtures.json(#"{"v":2,"value":{"kind":"\#(raw)"}}"#)
            #expect(decoded.value?.kind == kind, Comment(rawValue: raw))
        }
        #expect(try ActivityFixtures.json(#"{"v":2,"value":{}}"#).value?.kind == .text, "a value with no kind is text")
    }

    @Test func aCountdownRangeNeedsAnEndAndStartsAtMostNow() {
        let end = now.addingTimeInterval(600)
        #expect(ActivityValue.countdown(end: end).countdownRange(now: now) == now...end, "no start: begins now so the text still counts to zero")
        let started = ActivityValue.countdown(start: now.addingTimeInterval(-300), end: end)
        #expect(started.countdownRange(now: now) == now.addingTimeInterval(-300)...end)
        #expect(ActivityValue.countdown(start: now.addingTimeInterval(60), end: end).countdownRange(now: now) == now...end, "a start in the future is no earlier than now")
        #expect(ActivityValue(kind: .countdown).countdownRange(now: now) == nil)
        #expect(ActivityValue.percent.countdownRange(now: now) == nil)
        // An end already past still yields a valid range (the text shows zero).
        let past = ActivityValue.countdown(start: now.addingTimeInterval(-900), end: now.addingTimeInterval(-60))
        #expect(past.countdownRange(now: now) != nil)
    }

    @Test func theRingRangeNeedsBothEndsInOrder() {
        let end = now.addingTimeInterval(600)
        #expect(ActivityValue.countdown(start: now, end: end).ringRange == now...end)
        #expect(ActivityValue.countdown(end: end).ringRange == nil)
        #expect(ActivityValue.countdown(start: end, end: now).ringRange == nil)
        #expect(ActivityValue.countup(start: now).ringRange == nil)
    }

    @Test func aValueRoundTripsAndOmitsWhatIsEmpty() throws {
        let value = ActivityValue(kind: .countdown, startTs: 1_792_248_900, endTs: 1_792_249_482, estimated: true)
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ActivityValue.self, from: data) == value)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ActivityValue.text("Cooling"))) as? [String: Any]
        #expect(plain?.keys.sorted() == ["kind", "text"])
    }
}

struct ActivityControlAndGlyphTests {
    @Test func rolesDecodeAndUnknownOnesAreSecondary() throws {
        let controls = try JSONDecoder().decode([ActivityControl].self, from: Data("""
        [{"id":"a","title":"A","role":"primary"},{"id":"b","title":"B","role":"secondary"},{"id":"c","title":"C","role":"destructive"},{"id":"d","title":"D"}]
        """.utf8))
        #expect(controls.map(\.role) == [.primary, .secondary, .secondary, .secondary])
        #expect(controls[0].id == "a" && controls[0].title == "A")
    }

    @Test func glyphIdsResolveAndUnknownOnesAreGeneric() {
        for glyph in ActivityGlyph.allCases { #expect(ActivityGlyph(wire: glyph.rawValue) == glyph) }
        #expect(ActivityGlyph(wire: "mystery") == .generic && ActivityGlyph(wire: nil) == .generic)
        #expect(ActivityGlyph(symbol: "vacuum", kind: "x") == .vacuum)
        #expect(ActivityGlyph(symbol: "", kind: "dryer") == .dryer, "no symbol falls back to the kind")
        #expect(ActivityGlyph(symbol: "drop.fill", kind: "bathroom_fan") == .fan, "an SF Symbol name from Phase 1 is not a glyph id")
        #expect(ActivityGlyph(symbol: "", kind: "problem") == .alert)
        #expect(ActivityGlyph(symbol: "", kind: "home") == .generic)
        #expect(Set(ActivityGlyph.problemSet + ActivityGlyph.jobSet) == Set(ActivityGlyph.allCases), "every glyph is a job or a problem glyph")
    }

    @Test func phasesDecodeAndUnknownOnesRun() throws {
        for phase in JobPhase.allCases {
            let state = try ActivityFixtures.json(#"{"v":2,"phase":"\#(phase.rawValue)"}"#)
            #expect(state.phase == phase)
        }
        #expect(try ActivityFixtures.json(#"{"v":2,"phase":"hovering"}"#).phase == .running)
    }
}

struct ActivityProblemTests {
    @Test func aProblemDecodesEveryField() throws {
        let state = try ActivityFixtures.json("""
        {"v":2,"phase":"problem","problem":{"severity":"critical","code":"vendor.unknown_error_88","icon":"question","problem":"Stopped with an error","message":"Check it.","chips":["Error 88"],"task_id":"1042"}}
        """)
        let problem = try #require(state.problem)
        #expect(problem.severity == .critical && problem.code == "vendor.unknown_error_88" && problem.glyph == .question)
        #expect(problem.chips == ["Error 88"] && problem.taskId == "1042" && problem.hasTask)
        #expect(problem.severity.islandLabel == "Needs help" && problem.severity.spokenPhrase == "needs help")
        #expect(ActivityProblem.Severity.warning.islandLabel == "Attention" && ActivityProblem.Severity.warning.spokenPhrase == "needs attention")
    }

    @Test func missingFieldsAndUnknownSeveritiesAreSafe() throws {
        let bare = try ActivityFixtures.json(#"{"v":2,"phase":"problem","problem":{"severity":"dire"}}"#)
        let problem = try #require(bare.problem)
        #expect(problem.severity == .warning, "an unknown severity never alarms")
        #expect(problem.code.isEmpty && problem.message.isEmpty && problem.chips.isEmpty && problem.taskId == nil && !problem.hasTask)
        #expect(problem.glyph == .generic)
        #expect(!ActivityProblem(severity: .warning, code: "", icon: "", problem: "", message: "", taskId: "").hasTask)
    }

    @Test func aTaskIdMayBeAStringOrAJsonInteger() throws {
        func problem(_ id: String) throws -> ActivityProblem? {
            try ActivityFixtures.json(#"{"v":2,"phase":"problem","problem":{"severity":"critical","task_id":\#(id)}}"#).problem
        }
        #expect(try problem(#""1042""#)?.taskId == "1042")
        #expect(try problem("4217")?.taskId == "4217", "a numeric id must not fail the whole card")
        #expect(try problem("null")?.taskId == nil)
        #expect(try problem("true")?.taskId == nil, "an id of the wrong type is no id")
    }

    @Test func aProblemRoundTrips() throws {
        let problem = ActivityProblem(severity: .critical, code: "navigation.stuck", icon: "alert", problem: "Stuck in Kitchen",
                                      message: "Move it.", chips: ["Error 1"], taskId: "9")
        let data = try JSONEncoder().encode(problem)
        #expect(try JSONDecoder().decode(ActivityProblem.self, from: data) == problem)
        let quiet = ActivityProblem(severity: .warning, code: "c", icon: "i", problem: "p", message: "m")
        let keys = try (JSONSerialization.jsonObject(with: JSONEncoder().encode(quiet)) as? [String: Any])?.keys.sorted()
        #expect(keys == ["code", "icon", "message", "problem", "severity"])
    }

    @Test func theCompactLabelIsOneWordForKnownCodesAndASeverityWordOtherwise() {
        func label(_ code: String, _ severity: ActivityProblem.Severity = .critical) -> String {
            ActivityProblem(severity: severity, code: code, icon: "alert", problem: "", message: "").compactLabel
        }
        #expect(label("navigation.stuck") == "Stuck")
        #expect(label("mop.clean_water_empty", .warning) == "Refill water")
        for code in ["navigation.target_unreachable", "navigation.dock_unreachable", "navigation.ramp_hazard", "maintenance.main_brush_jammed",
                     "maintenance.side_brush_jammed", "power.critical_battery", "power.low_battery", "mop.dirty_water_unavailable",
                     "mop.attachment_missing", "dock.cover_open", "dock.dustbag_blocked"] {
            #expect(!label(code).isEmpty && label(code).split(separator: " ").count <= 2, Comment(rawValue: code))
        }
        #expect(label("vendor.unknown_error_9") == "Help" && label("unmapped.x", .warning) == "Check")
    }
}

struct ActivityPendingAndClockTests {
    @Test func everyControlHasItsWords() {
        #expect(ActivityPending.label(forControl: "stop") == "Stopping…")
        #expect(ActivityPending.label(forControl: "cancel_timer") == "Stopping…")
        #expect(ActivityPending.label(forControl: "pause") == "Pausing…")
        #expect(ActivityPending.label(forControl: "resume") == "Resuming…")
        #expect(ActivityPending.label(forControl: "dock") == "Docking…")
        #expect(ActivityPending.label(forControl: "done") == "Completing…")
        #expect(ActivityPending.label(forControl: "try_again") == "Trying again…")
        #expect(ActivityPending.label(forControl: "vacuum_only") == "Working…")
    }

    @Test func theTimestampFloorsToAWholeSecondNeverInTheFuture() {
        let date = Date(timeIntervalSince1970: 1_792_249_200.987)
        let floored = ActivityClock.wholeSecond(date)
        #expect(floored.timeIntervalSince1970 == 1_792_249_200)
        #expect(floored <= date)
        #expect(ActivityClock.wholeSecond(floored) == floored)
        #expect(ActivityClock.pendingStaleDate(from: date).timeIntervalSince1970 == 1_792_249_220, "now + 20 s, from the floored second")
    }

    @Test func aPressWritesPendingWithTheFlooredSecondAndClearsAnyNotice() {
        let base = HomeActivityState(controls: [ActivityControl(id: "stop", title: "Stop")], notice: "Couldn't reach Home")
        let now = Date(timeIntervalSince1970: 1_792_249_200.6)
        let pending = base.awaiting(control: "stop", now: now)
        #expect(pending.pending == ActivityPending(control: "stop", label: "Stopping…", sinceTs: 1_792_249_200))
        #expect(pending.notice == nil && pending.controls == base.controls, "the controls stay; the views hide them")
        #expect(base.offers(control: "stop") && !base.offers(control: "pause"))
    }

    @Test func aFailureRestoresTheContentWithANoticeAndNoPending() {
        let pending = HomeActivityState(controls: [ActivityControl(id: "stop", title: "Stop")]).awaiting(control: "stop", now: ActivityFixtures.now)
        let failed = pending.failing(notice: "Couldn't reach Home")
        #expect(failed.pending == nil && failed.notice == "Couldn't reach Home" && failed.offers(control: "stop"))
    }

    @Test func pendingRoundTripsOnTheWire() throws {
        let state = HomeActivityState(pending: ActivityPending(control: "stop", label: "Stopping…", sinceTs: 1_792_249_200), notice: "n")
        let decoded = try HomeActivityState.decode(state.encoded())
        #expect(decoded == state)
        let object = try #require(JSONSerialization.jsonObject(with: state.encoded()) as? [String: Any])
        #expect((object["pending"] as? [String: Any])?["since_ts"] as? Double == 1_792_249_200)
    }
}

struct HomeActivityStateTests {
    @Test func aV2StateDecodesEveryKey() throws {
        let state = try ActivityFixtures.json("""
        {"v":2,"phase":"paused","headline":"Paused in Kitchen","short":"Paused","detail":"Your side","value":{"kind":"countup","start_ts":1792248440},
         "progress":0.5,"controls":[{"id":"resume","title":"Resume","role":"primary"}],"notice":"n","url":"/p"}
        """)
        #expect(state.version == 2 && state.phase == .paused && state.headline == "Paused in Kitchen" && state.detail == "Your side")
        #expect(state.progress == 0.5 && state.controls.count == 1 && state.notice == "n" && state.url == "/p")
        #expect(state.problem == nil && state.pending == nil && state.short == "Paused")
    }

    @Test func shortIsOptionalOnTheWireAndRoundTrips() throws {
        let bare = try ActivityFixtures.json(#"{"v":2,"headline":"Vacuuming Kitchen"}"#)
        #expect(bare.short == nil, "a push from before `short` still decodes")
        let kitchen = HomeActivityState(headline: "Vacuuming Kitchen", short: "Kitchen")
        let object = try #require(JSONSerialization.jsonObject(with: kitchen.encoded()) as? [String: Any])
        #expect(object["short"] as? String == "Kitchen", "snake_case key `short`")
        #expect(try HomeActivityState.decode(kitchen.encoded()) == kitchen)
        #expect(try JSONSerialization.jsonObject(with: HomeActivityState().encoded()) is [String: Any])
        let none = try #require(JSONSerialization.jsonObject(with: HomeActivityState().encoded()) as? [String: Any])
        #expect(none["short"] == nil, "null keys are omitted")
    }

    @Test func aBareStateHasDefaults() throws {
        let state = try ActivityFixtures.json(#"{}"#)
        #expect(state.version == 2 && state.phase == .running && state.controls.isEmpty && state.value == nil && state.short == nil)
        #expect(try ActivityFixtures.json(#"{"v":2,"controls":null}"#).controls.isEmpty)
    }

    @Test func aStateRoundTripsThroughTheWire() throws {
        for fixture in HomeActivityFixtures.allNames.compactMap({ HomeActivityFixtures.fixture($0, now: ActivityFixtures.now) }) {
            let decoded = try HomeActivityState.decode(fixture.state.encoded())
            #expect(decoded == fixture.state, Comment(rawValue: fixture.name))
        }
    }

    @Test func capsTrimEveryStringAndControlList() {
        let long = String(repeating: "x", count: 200)
        let problem = ActivityProblem(severity: .critical, code: "c", icon: "alert", problem: long, message: long, chips: [long, long])
        let controls = (0..<5).map { ActivityControl(id: "c\($0)", title: "C") }
        let state = HomeActivityState(phase: .problem, headline: long, detail: long, value: .text(long), controls: controls, problem: problem).fitted()
        #expect(state.headline?.count == HomeActivityState.maxHeadlineLength && state.headline?.hasSuffix("…") == true)
        #expect(state.detail?.count == HomeActivityState.maxDetailLength)
        #expect(state.value?.text?.count == ActivityValue.maxTextLength)
        #expect(state.problem?.problem.count == ActivityProblem.maxProblemLength)
        #expect(state.problem?.message.count == ActivityProblem.maxMessageLength)
        #expect(state.problem?.chips.count == 1 && state.problem?.chips.first?.count == ActivityProblem.maxChipLength)
        #expect(state.controls.count == HomeActivityState.maxProblemControls, "a problem card keeps three")
        #expect(HomeActivityState(notice: long).fitted().notice?.count == HomeActivityState.maxNoticeLength)
        let job = HomeActivityState(controls: controls).fitted()
        #expect(job.controls.count == HomeActivityState.maxControls, "a job card keeps two")
        #expect(HomeActivityState(headline: "short").fitted().headline == "short")
        #expect(HomeActivityState(short: "Living Room Closet").fitted().short?.count == HomeActivityState.maxShortLength)
        #expect(HomeActivityState(short: "Kitchen").fitted().short == "Kitchen")
        #expect(HomeActivityState.truncated("abc", to: 1) == "abc", "a limit of one cannot hold an ellipsis")
        #expect(HomeActivityAttributes(title: long).fitted().title.count == HomeActivityAttributes.maxTitleLength)
    }

    @Test func fixturesFitTheWireBudgetAfterCaps() throws {
        for fixture in HomeActivityFixtures.allNames.compactMap({ HomeActivityFixtures.fixture($0, now: ActivityFixtures.now) }) {
            #expect(fixture.state == fixture.state.fitted(), "\(fixture.name) is within the caps")
            #expect(try fixture.state.encoded().count < HomeActivityState.maxPayloadBytes / 2, Comment(rawValue: fixture.name))
        }
    }
}

struct LegacyStateTests {
    private let v1 = """
    {"v":1,"focus":"fan.demo_master","url":"/p","jobs":[
      {"id":"dishwasher","kind":"dishwasher","title":"Dishwasher","status":"Eco","phase":"running","start_ts":1792241200,"end_ts":1792251720,"progress":0.62,
       "controls":[{"id":"stop","title":"Stop","role":"destructive"}]},
      {"id":"fan.demo_master","kind":"bathroom_fan","title":"Master Bath Fan","status":"Off in","phase":"running","start_ts":1792248900,"end_ts":1792250700,
       "controls":[{"id":"cancel_timer","title":"Cancel Timer"}]}]}
    """

    @Test func aV1PayloadTakesItsFocusJob() throws {
        let state = try ActivityFixtures.json(v1)
        #expect(state.version == 2 && state.headline == "Master Bath Fan" && state.url == "/p")
        #expect(state.value?.kind == .countdown && state.value?.startTs == 1_792_248_900 && state.value?.endTs == 1_792_250_700)
        #expect(state.controls.map(\.id) == ["cancel_timer"])
    }

    @Test func aMissingOrUnlistedFocusTakesTheFirstJob() throws {
        let unfocused = try ActivityFixtures.json(v1.replacingOccurrences(of: #""focus":"fan.demo_master","#, with: ""))
        #expect(unfocused.headline == "Dishwasher", "no version-less detection needed: `v` is 1")
        #expect(unfocused.progress == 0.62)
        let unlisted = try ActivityFixtures.json(v1.replacingOccurrences(of: "fan.demo_master\",\"url", with: "gone\",\"url"))
        #expect(unlisted.headline == "Dishwasher")
    }

    @Test func aPayloadWithJobsAndNoVersionIsV1() throws {
        let state = try ActivityFixtures.json(#"{"jobs":[{"id":"a","title":"A","phase":"paused"}]}"#)
        #expect(state.phase == .paused && state.headline == "A")
    }

    @Test func anEmptyJobListIsAnEndedCard() throws {
        let state = try ActivityFixtures.json(#"{"v":1,"jobs":[],"url":"/p"}"#)
        #expect(state.phase == .done && state.url == "/p" && state.headline == nil)
        #expect(try ActivityFixtures.json(#"{"v":1}"#).phase == .done)
    }

    @Test func eachV1PhaseMapsToAV2Phase() throws {
        func state(_ phase: String, extra: String = "") throws -> HomeActivityState {
            try ActivityFixtures.json(#"{"v":1,"jobs":[{"id":"a","title":"A","phase":"\#(phase)"\#(extra)}]}"#)
        }
        #expect(try state("running").phase == .running)
        #expect(try state("paused").phase == .paused)
        #expect(try state("waiting").phase == .waiting)
        #expect(try state("done").phase == .done)
        #expect(try state("what").phase == .running)
        let attention = try state("attention", extra: #","status":"Door open""#)
        #expect(attention.phase == .problem && attention.problem?.problem == "Needs attention" && attention.problem?.message == "Door open")
        #expect(attention.problem?.severity == .warning)
        let stopping = try state("stopping")
        #expect(stopping.pending?.control == "stop" && stopping.phase == .running)
    }

    @Test func v1ValuesBecomeCountdownsPercentsAndEstimates() throws {
        func value(_ extra: String) throws -> ActivityValue? {
            try ActivityFixtures.json(#"{"v":1,"jobs":[{"id":"a","title":"A"\#(extra)}]}"#).value
        }
        #expect(try value(#","start_ts":10,"end_ts":20,"estimated":true"#) == ActivityValue(kind: .countdown, startTs: 10, endTs: 20, estimated: true))
        #expect(try value(#","end_ts":20,"estimated":true"#) == ActivityValue(kind: .countdown, endTs: 20, estimated: true), "the dryer's estimate has no start")
        #expect(try value(#","progress":0.4"#) == .percent)
        #expect(try value(#","start_ts":20,"end_ts":10"#) == nil, "an end before the start shows nothing")
        #expect(try value("") == nil)
    }
}

struct AttributesTests {
    @Test func theTagsAndIdsAndDefaults() throws {
        let attributes = try JSONDecoder().decode(HomeActivityAttributes.self, from: Data(#"{"tag":"job.vacuum.demo_main_floor","title":"Main Floor Vacuum","kind":"vacuum","symbol":"vacuum","tint":"cleaning"}"#.utf8))
        #expect(attributes.jobID == "vacuum.demo_main_floor" && attributes.glyph == .vacuum && attributes.tint == "cleaning")
        let phase1 = try JSONDecoder().decode(HomeActivityAttributes.self, from: Data(#"{"tag":"fenton-home","title":"Home","kind":"home"}"#.utf8))
        #expect(phase1.symbol.isEmpty && phase1.tint == "neutral" && phase1.glyph == .generic && phase1.jobID == "fenton-home")
        let empty = try JSONDecoder().decode(HomeActivityAttributes.self, from: Data("{}".utf8))
        #expect(empty == HomeActivityAttributes())
        #expect(HomeActivityAttributes.jobID(forTag: "job.fan.demo_guest") == "fan.demo_guest" && HomeActivityAttributes.jobID(forTag: "other") == "other")
        let data = try JSONEncoder().encode(attributes)
        #expect(try JSONDecoder().decode(HomeActivityAttributes.self, from: data) == attributes)
        #expect(HomeActivityAttributes.wireName == "HomeActivityAttributes", "renaming the type orphans the push-to-start token")
    }
}

struct AppIconStoreTests {
    @Test func theChoiceIsStoredAndFallsBackToNavySky() throws {
        let suite = "test.appicon.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ActivityAppIconStore(defaults: defaults)
        #expect(store.choice == "navySky", "nothing written yet")
        store.write("plumLilac")
        #expect(store.choice == "plumLilac" && defaults.string(forKey: "appIconChoice") == "plumLilac")
        store.write("")
        #expect(store.choice == "navySky", "an empty value reads as the fallback")
        #expect(ActivityAppIconStore(defaults: nil).choice == "navySky")
        ActivityAppIconStore(defaults: nil).write("tealMint")
        #expect(ActivityAppIconStore.appGroup == "group.com.sfenton.home" && ActivityAppIconStore.key == "appIconChoice")
        _ = ActivityAppIconStore.shared.choice
    }
}
