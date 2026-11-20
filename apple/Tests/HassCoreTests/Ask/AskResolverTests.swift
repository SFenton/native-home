import Foundation
import Testing
@testable import HassCore

/// The resolver is deterministic: the same words give the same route and the same ids.
struct AskResolverTests {
    private let resolver = AskResolver(index: AskDemoHouse.index())

    struct Row: Sendable, CustomTestStringConvertible {
        let question: String
        let route: AskRoute
        let ids: [String]
        var testDescription: String { question }
    }

    static let rows: [Row] = [
        Row(question: "Is the kitchen light on?", route: .found, ids: ["light.demo_kitchen_light"]),
        Row(question: "hey siri, is the front door locked?", route: .found, ids: ["lock.demo_front_door"]),
        Row(question: "Is the back door lock locked", route: .found, ids: ["lock.demo_back_door"]),
        Row(question: "is the garage door closed", route: .found, ids: ["cover.demo_garage_door"]),
        Row(question: "What is the office temperature?", route: .group, ids: ["sensor.demo_office_temperature"]),
        Row(question: "Is Alex home?", route: .found, ids: ["person.demo_alex"]),
        Row(question: "Is Sam home", route: .found, ids: ["person.demo_sam"]),
        Row(question: "Is the driveway camera recording?", route: .found, ids: ["camera.demo_driveway"]),
        Row(question: "Did the porch schedule automation run today?", route: .found, ids: ["automation.demo_porch_schedule"]),
        Row(question: "is the living room tv playing", route: .found, ids: ["media_player.demo_tv"]),
        Row(question: "is the spare bulb on", route: .unavailable, ids: ["light.demo_broken_bulb"]),
        Row(question: "Are the living room lights on?", route: .group, ids: ["light.demo_lamp", "light.demo_kitchen_counter", "light.demo_broken_bulb"]),
        Row(question: "Are any windows open?", route: .group, ids: ["binary_sensor.demo_kitchen_window", "binary_sensor.demo_office_window"]),
        Row(question: "Are all the locks locked?", route: .group, ids: ["lock.demo_back_door", "lock.demo_front_door"]),
        Row(question: "Is the elevator on?", route: .none, ids: []),
        Row(question: "Turn on the kitchen light", route: .declineAction, ids: []),
        Row(question: "lock the front door", route: .declineAction, ids: []),
        Row(question: "What is the capital of France?", route: .declineOfftopic, ids: []),
        Row(question: "Tell me a joke", route: .declineOfftopic, ids: []),
    ]

    @Test(arguments: rows) func routesAndIds(row: Row) {
        let result = resolver.resolve(row.question)
        #expect(result.route == row.route)
        let got = result.route == .several ? result.candidateIds : result.entityIds
        #expect(Set(got) == Set(row.ids))
    }

    @Test func resolutionIsDeterministic() {
        let first = resolver.resolve("is the kitchen light on")
        for _ in 0..<5 { #expect(resolver.resolve("is the kitchen light on") == first) }
    }

    @Test func questionTypesFollowTheWords() {
        let table: [(String, AskQuestionType)] = [
            ("why is the kitchen light on", .why),
            ("how long has the kitchen light been on", .howLong),
            ("when did the back door lock last lock", .lastTime),
            ("what is the office temperature", .room),
            ("is Alex home", .people),
            ("is the kitchen light on and is the office light on", .compound),
        ]
        for (question, type) in table { #expect(resolver.resolve(question).type == type, "\(question)") }
    }

    @Test func pluralsAndSynonymsReachTheSameEntities() {
        #expect(resolver.resolve("is the lamp on in the lounge").entityIds == resolver.resolve("is the lamp on in the living room").entityIds)
    }

    @Test func aNearMissNameStillFindsTheEntity() {
        #expect(resolver.resolve("is the drivway camera recording").entityIds == ["camera.demo_driveway"])
    }

    @Test func aVerbLikeRecordingDoesNotMeanNone() {
        #expect(resolver.resolve("are any cameras recording").route == .found || resolver.resolve("are any cameras recording").route == .group)
    }

    @Test func twoEntitiesWithTheSameNameAsk() {
        let result = resolver.resolve("is the fan on")
        #expect(result.route == .several)
        #expect(Set(result.candidateIds) == ["fan.demo_kitchen_fan", "fan.demo_office_fan"])
        #expect(resolver.resolve("is the office fan on").entityIds == ["fan.demo_office_fan"])
    }

    @Test func explainNamesTheWords() {
        #expect(resolver.explain("is the kitchen light on").contains("kitchen"))
    }
}
