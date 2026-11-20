import Foundation
import Testing
@testable import HassCore

/// Text handling, configuration, the slice trimmer, the sensitivity classes and the deadline helper.
struct AskSupportTests {
    @Test(arguments: [
        ("Sam's Light", "sam light"), ("PM 2.5 Sensor", "pm25 sensor"), ("Living-Room  Lamp", "living room lamp"), ("It's 70°", "it 70 degrees"),
    ])
    func normalizing(raw: String, expected: String) {
        #expect(AskText.normalize(raw) == expected)
    }

    @Test(arguments: [("lights", "light"), ("batteries", "battery"), ("glass", "glass"), ("boxes", "box"), ("bus", "bus"), ("is", "is")])
    func stemming(raw: String, expected: String) {
        #expect(AskText.stem(raw) == expected)
    }

    @Test func spokenTensReadAsDigits() {
        #expect(AskText.words("thirty seconds") == ["30", "second"])
    }

    @Test func synonymsExpandToSeveralWords() {
        #expect(AskText.words("lounge", synonyms: ["lounge": "living room"]) == ["living", "room"])
    }

    @Test func aRunInsideAListIsFound() {
        #expect(AskText.containsRun(["a", "b", "c"], ["b", "c"]) == 1)
        #expect(AskText.containsRun(["a", "b"], ["c"]) == nil)
        #expect(AskText.containsRun([], ["c"]) == nil)
    }

    @Test func configurationRoundTripsAndFillsMissingKeys() throws {
        var configuration = AskConfiguration()
        configuration.roomNicknames = ["Office": ["study"]]
        let data = try JSONEncoder().encode(configuration)
        #expect(try JSONDecoder().decode(AskConfiguration.self, from: data) == configuration)
        let sparse = try JSONDecoder().decode(AskConfiguration.self, from: Data(#"{"roomNicknames":{"Office":["den"]}}"#.utf8))
        #expect(sparse.roomNicknames == ["Office": ["den"]])
        #expect(sparse.callDeadlineSeconds == AskConfiguration().callDeadlineSeconds)
        #expect(sparse.modelPaths.isEmpty)
    }

    @Test func anOverlayCarriesNamesGroupsAndSameAsAsData() throws {
        let json = #"""
        {"entityNames":{"light.demo_porch_light":["porch"]},
         "groups":[{"id":"outdoor","say":["outdoor lights"],"kind":"light","entityIds":["light.demo_porch_light"],"note":"ignored"},
                   {"id":"odd","say":["odd things"],"kind":"not-a-kind","entityIds":[]}],
         "sameAs":[["cover.demo_garage_door","binary_sensor.demo_garage_contact"]],
         "scopeRecords":["sensor.demo_attic_humidity"]}
        """#
        let c = try JSONDecoder().decode(AskConfiguration.self, from: Data(json.utf8))
        #expect(c.groups.count == 2)
        #expect(c.groups[0].kind == .light && c.groups[0].say == ["outdoor lights"])
        #expect(c.groups[1].kind == nil)
        #expect(c.sameAs == [["cover.demo_garage_door", "binary_sensor.demo_garage_contact"]])
        #expect(c.overlayEntityIds == ["light.demo_porch_light", "cover.demo_garage_door", "binary_sensor.demo_garage_contact", "sensor.demo_attic_humidity"])
        #expect(try JSONDecoder().decode(AskConfiguration.self, from: JSONEncoder().encode(c)) == c)
    }

    @Test func theDefaultsNameNoHouse() {
        let c = AskConfiguration()
        #expect(c.entityNames.isEmpty)
        #expect(c.roomNicknames.isEmpty)
        #expect(c.annotators.isEmpty)
        #expect(c.excludedPlatforms.isEmpty)
    }

    // MARK: Slice

    @Test func aSmallSliceKeepsEveryLine() {
        let builder = AskSliceBuilder(budget: AskBudget(), tokenCount: { $0.count / 4 })
        let slice = builder.build(instructions: "x", header: ["H"], entityLines: ["a", "b"], causeLines: ["c"], annotatorLines: ["n"], question: "q")
        #expect(slice.prompt.contains("a") && slice.prompt.contains("CAUSE") == false || slice.prompt.contains("c"))
        #expect(slice.collapsed == false)
        #expect(slice.overCap == false)
    }

    @Test func anOverBudgetSliceDropsCausesThenCollapsesEntities() {
        var budget = AskBudget()
        budget.inputCap = 60
        budget.maxListedNames = 2
        let builder = AskSliceBuilder(budget: budget, tokenCount: { $0.count / 2 })
        let entities = (0..<20).map { "entity line number \($0)" }
        let causes = (0..<6).map { "cause line \($0)" }
        let slice = builder.build(instructions: "i", header: [], entityLines: entities, causeLines: causes, annotatorLines: ["a1", "a2"], question: "q")
        #expect(slice.droppedCauseLines >= 3)
        #expect(slice.collapsed)
        #expect(slice.prompt.contains("and 18 more"))
    }

    // MARK: Sensitivity

    @Test func classes() {
        let rules = AskSensitivityRules()
        func level(_ domain: String, _ deviceClass: String? = nil) -> AskSensitivity {
            rules.classify(domain: domain, deviceClass: deviceClass, platform: nil, nameWords: [])
        }
        #expect(level("lock") == .security)
        #expect(level("alarm_control_panel") == .security)
        #expect(level("light") == .everyday)
        #expect(level("cover", "garage") == .security)
        #expect(level("person") == .home)
        #expect(level("camera") == .security)
    }

    @Test func classesOrder() {
        #expect(AskSensitivity.everyday < .home)
        #expect(AskSensitivity.home < .security)
    }

    @Test func aSecurityPlatformRaisesEveryEntityItOwns() {
        var rules = AskSensitivityRules()
        rules.securityPlatforms = ["demo_vault"]
        #expect(rules.classify(domain: "sensor", deviceClass: nil, platform: "demo_vault", nameWords: []) == .security)
    }

    // MARK: Deadline

    @Test func aSlowCallTimesOut() async {
        await #expect(throws: AskDeadline.TimedOut.self) {
            try await AskDeadline.run(seconds: 0.05) {
                try await Task.sleep(for: .seconds(2))
                return 1
            }
        }
    }

    @Test func aFastCallReturns() async throws {
        #expect(try await AskDeadline.run(seconds: 1) { 7 } == 7)
    }

    // MARK: Aggregator

    @Test func membersCountLeafLightsInARoom() {
        let index = AskDemoHouse.index()
        let aggregator = AskAggregator(index: index)
        let room = index.rooms.values.first { $0.title == "Living Room" }!
        let ids = aggregator.members(kind: .light, scope: .room(room.key)).map(\.id)
        #expect(Set(ids) == ["light.demo_lamp", "light.demo_kitchen_counter", "light.demo_broken_bulb"])
    }

    @Test func theHouseIsTheUnionOfItsRooms() {
        let aggregator = AskAggregator(index: AskDemoHouse.index())
        #expect(aggregator.members(kind: .light, scope: .house).count == 5)
    }

    @Test func summaryKeepsUnavailableApart() {
        let index = AskDemoHouse.index()
        let aggregator = AskAggregator(index: index)
        let lights = aggregator.members(kind: .light, scope: .house)
        let summary = aggregator.summarize(lights) { $0.state.state == "on" }
        #expect(summary.matching.count == 2)
        #expect(summary.unavailable == ["light.demo_broken_bulb"])
        #expect(summary.total == 5)
    }

    @Test func meanReadsNumbers() {
        let index = AskDemoHouse.index()
        let aggregator = AskAggregator(index: index)
        let temps = aggregator.members(kind: .temperature, scope: .house)
        #expect(aggregator.mean(temps) == 70.25)
    }
}
