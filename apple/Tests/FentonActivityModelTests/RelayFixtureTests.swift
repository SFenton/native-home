import Foundation
@testable import FentonActivityModel
import Testing

/// The push fixtures in `tools/push_fixtures/live2-*.apns`: the app decodes what the relay writes, with the same default
/// `JSONDecoder` ActivityKit uses. The app lane hand-wrote these from the spec text (§3, "Fixtures"); review diffs them
/// against the relay lane's own set (`SFenton/ha-fenton-push` `tests/fixtures/live2-*.apns`).
struct RelayFixtureTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every fixture the spec names, plus the problem variants.
    private static let names = [
        "fan-start", "fan-end", "dishwasher-countdown", "dishwasher-percent", "dishwasher-waiting", "washer-countup", "dryer-countup",
        "complete-dishwasher", "complete-washer", "complete-dryer", "complete-hotflash",
        "hotflash-cooling", "hotflash-holding", "hotflash-bysam", "hotflash-wholebed",
        "vacuum-countup", "vacuum-paused", "vacuum-area", "vacuum-long-title", "dishwasher-hours", "fan-long-title", "hotflash-alex-bysam",
        "problem-critical", "problem-warning", "problem-no-task", "problem-unknown-error", "problem-unmapped", "v1-compat",
    ]

    private func object(_ name: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("tools/push_fixtures/live2-\(name).apns"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func aps(_ name: String) throws -> [String: Any] {
        try #require(object(name)["aps"] as? [String: Any])
    }

    private func state(_ name: String) throws -> HomeActivityState {
        let content = try #require(aps(name)["content-state"])
        return try HomeActivityState.decode(JSONSerialization.data(withJSONObject: content))
    }

    private func attributes(_ name: String) throws -> HomeActivityAttributes {
        let raw = try #require(aps(name)["attributes"])
        return try JSONDecoder().decode(HomeActivityAttributes.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    @Test func everyFixtureDecodesAndFitsApplesFourKilobytes() throws {
        for name in Self.names {
            let state = try state(name)
            #expect(state.version == 2, Comment(rawValue: name))
            let object = try object(name)
            let compact = try JSONSerialization.data(withJSONObject: object.filter { $0.key != "Simulator Target Bundle" })
            #expect(compact.count < HomeActivityState.maxPayloadBytes, Comment(rawValue: name))
            #expect(state == state.fitted(), "\(name) is within the string and control caps")
        }
    }

    @Test func aStartCarriesAttributesTheAppDecodes() throws {
        for name in ["fan-start", "washer-countup", "dryer-countup", "vacuum-countup", "hotflash-cooling", "vacuum-area"] {
            let aps = try aps(name)
            #expect(aps["event"] as? String == "start" && aps["attributes-type"] as? String == HomeActivityAttributes.wireName, Comment(rawValue: name))
            let attributes = try attributes(name)
            #expect(attributes.tag.hasPrefix("job.") && attributes.glyph != .generic && attributes.tint != "neutral", Comment(rawValue: name))
        }
        let fan = try attributes("fan-start")
        #expect(fan == HomeActivityAttributes(tag: "job.fan.guest", title: "Guest Bath Fan", kind: "fan", symbol: "fan", tint: "air"))
    }

    @Test func theFanCountsDownInto2026WithAStopButton() throws {
        let state = try state("fan-start")
        let value = try #require(state.value)
        #expect(value.kind == .countdown)
        let end = try #require(value.endDate)
        #expect(Calendar(identifier: .gregorian).component(.year, from: end) == 2026, "a Date read from 2001 would land in 1995")
        #expect(state.controls == [ActivityControl(id: "stop", title: "Stop")], "the first control carries no role: it is primary")
        let card = ActivityCard(attributes: try attributes("fan-start"), state: state, now: Date(timeIntervalSince1970: 1_792_249_200))
        #expect(card.buttons.map(\.accessibilityLabel) == ["Stop Guest Bath Fan"])
        let ended = try aps("fan-end")
        #expect(ended["event"] as? String == "end" && ended["dismissal-date"] as? Double == ended["timestamp"] as? Double, "ends now")
        let stub = try self.state("fan-end")
        #expect(stub.phase == .done && stub.value?.text == "Ended", "an end carries the engine's stub content")
    }

    @Test func theDishwasherShowsACountdownOrAPercentage() throws {
        #expect(try state("dishwasher-countdown").value?.kind == .countdown)
        let percent = try state("dishwasher-percent")
        #expect(percent.value?.kind == .percent && percent.progress == 0.62)
        let waiting = try state("dishwasher-waiting")
        #expect(waiting.phase == .waiting && waiting.value?.text == "Starts 5:10 PM")
    }

    @Test func laundryCountsUpAndHasNoButtons() throws {
        for name in ["washer-countup", "dryer-countup"] {
            let state = try state(name)
            #expect(state.value?.kind == .countup && state.value?.endTs == nil && state.controls.isEmpty, Comment(rawValue: name))
        }
    }

    @Test func finishedJobsAreComplete() throws {
        for name in ["complete-dishwasher", "complete-washer", "complete-dryer", "complete-hotflash"] {
            let state = try state(name)
            #expect(state.phase == .done && state.controls.isEmpty && state.progress == 1 && state.value?.text == "Complete", Comment(rawValue: name))
        }
    }

    @Test func hotFlashSaysWhoseSideItIs() throws {
        #expect(try state("hotflash-cooling").value?.text == "Cooling" && (try state("hotflash-cooling")).progress == 0.45)
        #expect(try state("hotflash-holding").value?.kind == .countdown)
        #expect(try state("hotflash-bysam").detail == "Your side · by Sam")
        #expect(try state("hotflash-wholebed").detail == "Whole bed")
        #expect(try attributes("hotflash-cooling").glyph == .hotFlash)
    }

    @Test func aVacuumRoomHasNoTimeAndNoBarJustAHeadlineAndAShortWord() throws {
        let now = Date(timeIntervalSince1970: 1_792_249_200)
        let running = try state("vacuum-countup")
        #expect(running.headline == "Vacuuming Kitchen" && running.short == "Kitchen" && running.controls.map(\.id) == ["pause", "dock"])
        #expect(running.value == nil && running.progress == nil, "the engine omits value and progress for a vacuum")
        let card = ActivityCard(attributes: try attributes("vacuum-countup"), state: running, now: now)
        #expect(card.bigLine == "Vacuuming Kitchen" && card.bar == nil && card.compactTrailing == .label("Kitchen"))
        #expect(card.buttons.map(\.icon) == [.pause, .dock])
        let paused = try state("vacuum-paused")
        #expect(paused.phase == .paused && paused.value == nil && paused.short == "Paused" && paused.controls.map(\.id) == ["resume", "dock"])
        let pausedCard = ActivityCard(attributes: try attributes("vacuum-countup"), state: paused, now: now)
        #expect(pausedCard.isPaused && pausedCard.bigLine == "Paused in Kitchen" && pausedCard.buttons.map(\.icon) == [.play, .dock])
        #expect(try state("vacuum-area").short == "Area" && (try state("vacuum-area")).headline == "Cleaning Main Floor area")
        #expect(try state("vacuum-long-title").headline == "Vacuuming Bedroom 1 Closet")
    }

    @Test func twoLineTitlesAndAnHoursDishwasherDecode() throws {
        #expect(try attributes("fan-long-title").title == "Bedroom 1 Closet Exhaust Fan")
        #expect(try state("hotflash-alex-bysam").detail == "Alex's side · by Sam")
        let dishwasher = HomeActivityAttributes(tag: "job.dishwasher", title: "Dishwasher", kind: "dishwasher", symbol: "dishwasher", tint: "cleaning")
        let hours = ActivityCard(attributes: dishwasher, state: try state("dishwasher-hours"), now: Date(timeIntervalSince1970: 1_792_249_200))
        #expect(hours.compactTrailing == .timer(template: "0:00:00"), "1:04:42 left takes the hours template")
    }

    @Test func problemCardsCarryTheirSeverityTaskAndButtons() throws {
        let critical = try state("problem-critical")
        #expect(critical.phase == .problem && critical.problem?.severity == .critical && critical.problem?.taskId == "1042")
        #expect(critical.controls.map(\.id) == ["resume", "dock", "done"], "Done is last")
        #expect(critical.controls.map(\.role) == [.secondary, .secondary, .secondary], "no role on the first, `secondary` on the rest")
        let attention = try self.state("problem-warning")
        #expect(critical.value?.text == "Needs help" && attention.value?.text == "Attention")
        let card = ActivityCard(attributes: try attributes("vacuum-countup"), state: critical, now: Date(timeIntervalSince1970: 1_792_249_200))
        #expect(card.problem?.severity.islandLabel == "Needs help")
        #expect(try aps("problem-critical")["alert"] != nil, "a critical update alerts")
        let warning = try state("problem-warning")
        #expect(warning.problem?.severity == .warning && warning.controls.last?.id == "done")
        #expect(try aps("problem-warning")["alert"] == nil, "a warning is silent")
        let none = try state("problem-no-task")
        #expect(none.problem?.hasTask == false && none.controls.isEmpty)
        let numbered = try state("problem-unknown-error")
        #expect(numbered.problem?.chips == ["Error 88"] && numbered.problem?.hasTask == false)
        let unmapped = try state("problem-unmapped")
        #expect(unmapped.problem?.chips.isEmpty == true && unmapped.problem?.message.contains("“Wheel suspended”") == true)
        for name in ["problem-critical", "problem-warning", "problem-no-task", "problem-unknown-error", "problem-unmapped"] {
            #expect(try state(name).problem?.glyph != .generic, Comment(rawValue: name))
        }
    }

    @Test func aPhaseOnePayloadStillDecodesByItsFocusJob() throws {
        let state = try state("v1-compat")
        #expect(state.headline == "Dishwasher" && state.controls.map(\.id) == ["stop"] && state.value?.kind == .countdown)
        let attributes = try attributes("v1-compat")
        #expect(attributes == HomeActivityAttributes(tag: "fenton-home", title: "Home", kind: "home", symbol: "", tint: "neutral"))
    }

    // MARK: The relay lane's own set (`tools/push_fixtures/relay/`, copied from the relay repo's branch)

    private static func relayNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("tools/push_fixtures/relay").path)
            .filter { $0.hasPrefix("live2-") && $0.hasSuffix(".apns") }.sorted()
    }

    private func relayObject(_ file: String) throws -> [String: Any] {
        let data = try Data(contentsOf: Self.root.appendingPathComponent("tools/push_fixtures/relay/\(file)"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func everyFixtureTheRelayGeneratesDecodesAndFits() throws {
        let files = try Self.relayNames()
        #expect(files.count >= 20, "the relay set is present")
        for file in files {
            let object = try relayObject(file)
            let aps = try #require(object["aps"] as? [String: Any], Comment(rawValue: file))
            let content = try #require(aps["content-state"], Comment(rawValue: file))
            let state = try HomeActivityState.decode(JSONSerialization.data(withJSONObject: content))
            #expect(state == state.fitted(), "\(file) is within the caps")
            if let raw = aps["attributes"] {
                let attributes = try JSONDecoder().decode(HomeActivityAttributes.self, from: JSONSerialization.data(withJSONObject: raw))
                #expect(attributes.tag.hasPrefix("job.") || attributes.tag == "fenton-home", Comment(rawValue: file))
                let card = ActivityCard(attributes: attributes, state: state, now: Date(timeIntervalSince1970: 1_792_249_200))
                #expect(!card.title.isEmpty, Comment(rawValue: file))
                #expect(card.glyph != .generic || attributes.symbol.isEmpty, "\(file) names a glyph this build draws")
            }
            let compact = try JSONSerialization.data(withJSONObject: object.filter { $0.key != "Simulator Target Bundle" })
            #expect(compact.count < HomeActivityState.maxPayloadBytes, Comment(rawValue: file))
        }
    }

    @Test func theRelaysProblemWithDoneKeepsItsNumericTask() throws {
        let aps = try #require(try relayObject("live2-problem-with-done.apns")["aps"] as? [String: Any])
        let state = try HomeActivityState.decode(JSONSerialization.data(withJSONObject: try #require(aps["content-state"])))
        #expect(state.problem?.taskId == "4217" && state.controls.last?.id == "done")
        #expect(state.value?.text == "Needs help")
    }
}
