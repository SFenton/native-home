import Foundation
import Testing
@testable import HassCore

// MARK: - The edge operands

/// `sh.entity-time@1`, `sh.countdown@1`, `sh.duration-format@1` and `sh.math-truncate@1`: the parser, the evaluator, the duration drawings, the
/// instant text and the entity-box read. The evaluation corpus holds the shared answers; these tests hold the edges the corpus does not name.
@Suite(.timeLimit(.minutes(1)))
struct ServerUIEdgeOperandTests {
    /// A reader over fixed answers.
    private struct Reader: ServerUIReading {
        var changed: ServerUIReadResult = .unavailable
        var clock: ServerUIClock?
        var secondClock: ServerUIClock?
        var isFlow = false
        var viewer: ServerUIViewer?
        var raw: ServerUIReadResult = .unavailable
        var params: [String: JSONValue] = [:]
        var controlValue: JSONValue?
        var locale: Locale?
        var person: ServerUIReadResult = .unavailable
        func readRaw(sourceId: String) -> ServerUIReadResult { raw }
        func parameter(_ name: String) -> JSONValue? { params[name] }
        func read(sourceId: String, path: [String]) -> ServerUIReadResult { .unavailable }
        func readChanged(sourceId: String) -> ServerUIReadResult { changed }
        func viewerPersonState() -> ServerUIReadResult { person }
    }

    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    private func parse(_ text: String, flow: Bool = false) throws -> (operand: ServerUIOperand?, issues: [ServerUICompositionError], needs: Set<String>) {
        var parser = ServerUIExpressionParser(flow: flow)
        let operand = parser.operand(try json(text), at: "/x")
        return (operand, parser.issues, parser.needs)
    }

    // MARK: Parsing and needs

    @Test func eachOperandNamesItsCapability() throws {
        let cases: [(String, String)] = [
            (#"{"type":"last-changed","sourceId":"s"}"#, "entity-time"),
            (#"{"type":"clock","part":"now-second"}"#, "countdown"),
            (#"{"type":"date","op":"seconds-between","from":{"type":"clock","part":"now-second"},"to":{"type":"literal","value":"2026-01-01T00:00:00"}}"#, "countdown"),
            (#"{"type":"math","op":"truncate","args":[{"type":"literal","value":1.99}]}"#, "math-truncate"),
        ]
        for (text, need) in cases {
            let result = try parse(text)
            #expect(result.operand != nil && result.needs.contains(need), "\(need)")
        }
        let format = try parse(#"{"type":"format","pattern":"{s}","args":{"s":{"type":"literal","value":5}},"formats":{"s":{"duration":{"style":"clock"}}}}"#)
        #expect(format.issues.isEmpty && format.needs.contains("duration-format"))
    }

    @Test func aFlowRefusesTheTwoReadsOfTheLiveWorld() throws {
        for text in [#"{"type":"last-changed","sourceId":"s"}"#, #"{"type":"clock","part":"now-second"}"#] {
            let result = try parse(text, flow: true)
            #expect(result.issues.first?.code == .invalidCombination, "\(text)")
        }
    }

    @Test func aDurationFormatRefusesWhatItCannotDraw() throws {
        func formats(_ spec: String, arg: String = #"{"type":"literal","value":5}"#) throws -> [ServerUICompositionError] {
            try parse(#"{"type":"format","pattern":"{s}","args":{"s":\#(arg)},"formats":{"s":\#(spec)}}"#).issues
        }
        #expect(try formats(#"{"duration":{"style":"weeks"}}"#).first?.code == .unknownVariant)
        #expect(try formats(#"{"duration":{"style":"compact","unit":"hours"}}"#).first?.code == .unknownVariant)
        let unit = try formats(#"{"duration":{"style":"clock","unit":"minutes"}}"#).first
        #expect(unit?.code == .invalidCombination && unit?.pointer.hasSuffix("/duration/unit") == true)
        let text = try formats(#"{"duration":{"style":"clock"}}"#, arg: #"{"type":"literal","value":"x"}"#).first
        #expect(text?.code == .bindingType)
        #expect(try formats(#"{"duration":{"style":"compact","unit":"minutes"}}"#).isEmpty)
    }

    @Test func truncateTakesOneOrTwoArguments() throws {
        let none = try parse(#"{"type":"math","op":"truncate","args":[]}"#)
        let three = try parse(#"{"type":"math","op":"truncate","args":[{"type":"literal","value":1},{"type":"literal","value":1},{"type":"literal","value":1}]}"#)
        #expect(!none.issues.isEmpty && !three.issues.isEmpty)
    }

    // MARK: Evaluating

    @Test func lastChangedGivesTheBoxTextAndNothingElse() {
        let operand = ServerUIOperand.lastChanged(sourceId: "s")
        #expect(operand.evaluate(Reader(changed: .value(.string("2026-11-15T21:30:00.000Z")))) == .value(.string("2026-11-15T21:30:00.000Z")))
        #expect(operand.evaluate(Reader(changed: .value(.number(3)))) == .unavailable)
        #expect(operand.evaluate(Reader(changed: .loading)) == .loading)
        #expect(operand.evaluate(Reader()) == .unavailable)
        #expect(operand.evaluate(Reader(changed: .value(.string("2026-11-15T21:30:00.000Z")), isFlow: true)) == .value(.null))
    }

    @Test func nowSecondReadsTheSecondClockNotTheMinuteClock() {
        let minute = ServerUIClock(now: "2026-11-15T09:30:00", utcOffsetMinutes: 0)
        let second = ServerUIClock(now: "2026-11-15T09:30:41", utcOffsetMinutes: 0)
        let operand = ServerUIOperand.clock(.nowSecond)
        #expect(operand.evaluate(Reader(clock: minute, secondClock: second)) == .value(.string("2026-11-15T09:30:41")))
        #expect(operand.evaluate(Reader()) == .unavailable)
        #expect(ServerUIOperand.clock(.now).evaluate(Reader(clock: minute, secondClock: second)) == .value(.string("2026-11-15T09:30:00")))
    }

    @Test func theSecondClockDefaultsToTheClock() {
        let clock = ServerUIClock(now: "2026-11-15T09:30:00", utcOffsetMinutes: 0)
        struct Plain: ServerUIReading {
            var clock: ServerUIClock?
            var viewer: ServerUIViewer? { nil }
            func read(sourceId: String, path: [String]) -> ServerUIReadResult { .unavailable }
            func viewerPersonState() -> ServerUIReadResult { .unavailable }
        }
        #expect(Plain(clock: clock).secondClock == clock)
        #expect(Plain().readChanged(sourceId: "s") == .unavailable)
    }

    @Test func secondsBetweenCountsOnTheClocksWall() {
        #expect(ServerUIDates.secondsBetween("2026-11-15T09:30:00", "2026-11-15T09:35:00", utcOffsetMinutes: 0) == 300)
        #expect(ServerUIDates.secondsBetween("2026-11-15T09:35:00", "2026-11-15T09:30:00", utcOffsetMinutes: 0) == -300)
        #expect(ServerUIDates.secondsBetween("2026-11-15T09:30:00.900", "2026-11-15T09:30:01", utcOffsetMinutes: 0) == 1)
        #expect(ServerUIDates.secondsBetween("nonsense", "2026-11-15", utcOffsetMinutes: 0) == nil)
    }

    @Test func truncateGoesTowardZeroAndNeverGivesNegativeZero() {
        func run(_ args: [Double]) -> ServerUIReadResult {
            ServerUIOperand.math(.truncate, args.map { .literal(.number($0)) }).evaluate(Reader())
        }
        #expect(run([71.99, 1]) == .value(.number(71.9)))
        #expect(run([-71.99, 1]) == .value(.number(-71.9)))
        #expect(run([-0.4]) == .value(.number(0)))
        if case .value(.number(let zero)) = run([-0.4]) { #expect(zero.sign == .plus) }
        #expect(run([2.5]) == .value(.number(2)))
    }

    // MARK: Drawing a duration

    @Test func compactRoundsAsTheShippedCodeDid() {
        let seconds = ServerUIDurationFormat(style: .compact), minutes = ServerUIDurationFormat(style: .compact, unit: .minutes)
        #expect(seconds.text(1) == "1m" && seconds.text(61) == "2m" && seconds.text(3_600) == "1h" && seconds.text(5_400) == "1h 30m")
        #expect(seconds.text(0) == nil && seconds.text(-5) == nil)
        #expect(minutes.text(30) == "30m" && minutes.text(90) == "1h 30m" && minutes.text(0.4) == nil && minutes.text(0.5) == "1m")
    }

    @Test func clockMinutesSecondsAndSpanDrawTheirOwnWay() {
        let clock = ServerUIDurationFormat(style: .clock), mmss = ServerUIDurationFormat(style: .minutesSeconds), span = ServerUIDurationFormat(style: .span)
        #expect(clock.text(300) == "05:00" && clock.text(3_600) == "01:00:00" && clock.text(59.9) == "00:59" && clock.text(-4) == "00:00")
        #expect(mmss.text(270) == "4:30" && mmss.text(4_500) == "75:00" && mmss.text(0.2) == "0:01" && mmss.text(-1) == "0:00")
        #expect(span.text(3_600) == "1 hour" && span.text(7_200) == "2 hours" && span.text(3 * 86_400) == "3 days")
        #expect(span.text(21 * 86_400) == "3 weeks" && span.text(90 * 86_400) == "3 months" && span.text(10) == "1 hour" && span.text(-3_600) == "1 hour")
    }

    @Test func aNumberThatIsNotADurationHasNoText() {
        for style in ServerUIDurationFormat.Style.allCases {
            let format = ServerUIDurationFormat(style: style)
            #expect(format.text(.nan) == nil && format.text(.infinity) == nil && format.text(1e13) == nil && format.text(-1e13) == nil)
        }
        #expect(ServerUIDurationFormat.Unit.allCases.map(\.rawValue) == ["seconds", "minutes"])
        #expect(ServerUIDurationFormat.Style(rawValue: "minutes-seconds") == .minutesSeconds)
    }

    // MARK: The entity box

    @Test func theBoxReadGivesLoadingUnavailableOrTheInstant() {
        let entity = EntityState(entityId: "fan.demo_bath_fan", state: "on", lastChanged: Date(timeIntervalSince1970: 1_794_951_000.5))
        #expect(ServerUIReadResult.lastChanged(of: entity, statesLoaded: false) == .loading)
        #expect(ServerUIReadResult.lastChanged(of: nil, statesLoaded: true) == .unavailable)
        #expect(ServerUIReadResult.lastChanged(of: EntityState(entityId: "fan.demo_bath_fan", state: "on", lastChanged: .distantPast), statesLoaded: true) == .unavailable)
        #expect(ServerUIReadResult.lastChanged(of: entity, statesLoaded: true) == .value(.string("2026-11-17T21:30:00.500Z")))
    }

    @Test func instantTextPadsAndFloorsBeforeTheEpoch() {
        #expect(ServerUIDates.instantText(Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z")
        #expect(ServerUIDates.instantText(Date(timeIntervalSince1970: 0.007)) == "1970-01-01T00:00:00.007Z")
        #expect(ServerUIDates.instantText(Date(timeIntervalSince1970: 0.05)) == "1970-01-01T00:00:00.050Z")
        #expect(ServerUIDates.instantText(Date(timeIntervalSince1970: -0.5)) == "1969-12-31T23:59:59.500Z")
    }

    // MARK: Capabilities and the tick

    @Test func theFourIdsAreShipped() {
        for id in ServerUIIngestedCapabilities.edgeOperands {
            #expect(ServerUIIngestedCapabilities.all.contains(id) && ServerUICompositionPublication.supportedCapabilities.contains(id), "\(id)")
        }
        #expect(ServerUIIngestedCapabilities.edgeOperands.count == 4)
    }

    /// The second tick is the minute tick's rule at 1 Hz: no read, no timer; the first read starts it; one tick without a read stops it.
    @Test func theSecondTickRunsOnlyWhileSomethingReads() {
        var tick = ServerUIMinuteTick()
        #expect(!tick.isRunning)
        let started = tick.noteRead()
        #expect(started && tick.isRunning)
        let kept = tick.fire()
        #expect(kept && tick.isRunning)
        let stopped = !tick.fire()
        #expect(stopped && !tick.isRunning)
        let restarted = tick.noteRead()
        #expect(restarted)
    }

    /// The 1 Hz path's work per tick, measured: the second clock text plus one countdown evaluation, in microseconds each.
    @Test func oneSecondOfCountdownWorkIsCheap() throws {
        let operand = try #require(try parse(#"{"type":"format","pattern":"Off in {s}","args":{"s":{"type":"date","op":"seconds-between","from":{"type":"clock","part":"now-second"},"to":{"type":"literal","value":"2099-01-01T00:00:00"}}},"formats":{"s":{"duration":{"style":"clock"}}}}"#).operand)
        let start = ContinuousClock.now
        var last: ServerUIReadResult = .unavailable
        for _ in 0..<2_000 {
            last = operand.evaluate(Reader(secondClock: ServerUIAppState.clock(at: Date())))
        }
        let microseconds = (ContinuousClock.now - start) / .microseconds(1) / 2_000
        guard case .value(.string(let text)) = last else { Issue.record("no text: \(last)"); return }
        #expect(text.hasPrefix("Off in "))
        #expect(microseconds < 500, "\(microseconds) us per tick")
    }

    // MARK: Walks over the tree

    private let filler = ServerUIOperand.literal(.number(1))

    @Test func aFlowListsTheSourcesASecondsBetweenReads() {
        let operand = ServerUIOperand.secondsBetween(from: .read(sourceId: "a", path: ["state"], as: .string), to: .read(sourceId: "b", path: ["state"], as: .string))
        #expect(Set(operand.flowReads.map(\.sourceId)) == ["a", "b"])
    }

    @Test func aChartRecordReadsTheEdgeOperandsThroughItsReader() {
        let reader = Reader(changed: .value(.string("2026-11-15T21:30:00.000Z")), secondClock: ServerUIClock(now: "2026-11-15T09:30:00", utcOffsetMinutes: 0))
        let value = ServerUIOperand.secondsBetween(from: .clock(.nowSecond), to: .literal(.string("2026-11-15T09:40:00")))
        let points = ServerUIChart.sourcePoints(limit: 2, label: .lastChanged(sourceId: "s"), value: value, records: [.null, .null], in: reader)
        #expect(points.map(\.label) == ["2026-11-15T21:30:00.000Z", "2026-11-15T21:30:00.000Z"])
        #expect(points.map(\.value) == [600, 600])
    }

    @Test func aChartRecordForwardsEveryReadOfItsReader() {
        let reader = Reader(clock: ServerUIClock(now: "2026-11-15T09:30:00", utcOffsetMinutes: 0), viewer: ServerUIViewer(userId: "u", isAdmin: true, personEntityId: "person.demo_resident"),
                            raw: .value(.string("on")), params: ["p": .string("param")], controlValue: .string("control"), locale: Locale(identifier: "en_US"),
                            person: .value(.string("home")))
        let labels: [ServerUIOperand] = [.rawState(sourceId: "s"), .param(name: "p"), .control, .viewer(.userId), .clock(.now), .item(path: [])]
        let texts = labels.map { ServerUIChart.sourcePoints(limit: 1, label: $0, value: .literal(.number(1)), records: [.string("item")], in: reader)[0].label }
        #expect(texts == ["on", "param", "control", "u", "2026-11-15T09:30:00", "item"])
        var flow = reader
        flow.isFlow = true
        #expect(ServerUIChart.sourcePoints(limit: 1, label: .rawState(sourceId: "s"), value: .literal(.number(1)), records: [.null], in: flow)[0].label == "")
    }

    // MARK: Parsing the corners

    @Test func aMalformedLastChangedOrDurationIsRefused() throws {
        #expect(try !parse(#"{"type":"last-changed","sourceId":7}"#).issues.isEmpty)
        #expect(try !parse(#"{"type":"last-changed"}"#).issues.isEmpty)
        let missing = try parse(#"{"type":"format","pattern":"{s}","args":{"s":{"type":"literal","value":5}},"formats":{"s":{"duration":{}}}}"#)
        #expect(!missing.issues.isEmpty)
    }

    // MARK: Typing in a flow

    private func typed(_ operand: ServerUIOperand) -> (shape: ServerUIFlowShape, facts: ServerUIFlowTyping.Facts) {
        var facts = ServerUIFlowTyping.Facts()
        var budget = ServerUIFlowTyping.Budget()
        let scope = ServerUIFlowTyping.Scope(item: nil, parameters: [:], allowsRead: false, allowsViewer: false)
        let shape = ServerUIFlowTyping.type(operand, scope, at: "/x", &facts, budget: &budget)
        return (shape, facts)
    }

    @Test func aFlowTypesTheEdgeOperandsAndRefusesTheLiveOnes() {
        let start = ServerUIOperand.literal(.string("2026-11-15T09:30:00")), end = ServerUIOperand.literal(.string("2026-11-15T09:40:00"))
        let between = typed(.secondsBetween(from: .clock(.now), to: .clock(.today)))
        #expect(typed(.secondsBetween(from: start, to: end)).shape == ServerUIFlowShape.integer.orNull)
        #expect(between.facts.edge == ["countdown"] && between.facts.issues.isEmpty)
        #expect(between.shape == .integer)
        #expect(typed(.secondsBetween(from: .param(name: "p"), to: end)).shape == ServerUIFlowShape.integer.orNull)
        #expect(typed(.clock(.nowSecond)).facts.issues.first?.code == .invalidCombination)
        #expect(typed(.lastChanged(sourceId: "s")).facts.issues.first?.code == .invalidCombination)
        #expect(typed(.math(.truncate, [filler])).facts.edge == ["math-truncate"])
        func formatted(_ spec: ServerUIFormatSpec) -> ServerUIFlowTyping.Facts {
            typed(.format(pattern: "{a}", args: ["a": filler], formats: ["a": spec])).facts
        }
        let clockUnit = formatted(.duration(ServerUIDurationFormat(style: .clock, unit: .minutes)))
        #expect(clockUnit.edge == ["duration-format"] && clockUnit.issues.first?.code == .invalidCombination)
        #expect(formatted(.duration(ServerUIDurationFormat(style: .compact, unit: .minutes))).issues.isEmpty)
    }
}
