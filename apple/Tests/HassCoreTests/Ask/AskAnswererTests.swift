import Foundation
import Testing
@testable import HassCore

/// Answers come from code where the facts decide them; the model only phrases a cause.
struct AskAnswererTests {
    private func answerer(source: AskDataSource = AskNoDataSource(), phrase: AskAnswerer.Phrase? = nil, configuration: AskConfiguration = AskConfiguration()) -> AskAnswerer {
        AskAnswerer(index: AskDemoHouse.index(configuration: configuration), dataSource: source, phrase: phrase)
    }

    /// The one setting that lets the model phrase anything: a path listed in `modelPaths`. Empty is the default.
    private var causeViaModel: AskConfiguration {
        var configuration = AskConfiguration()
        configuration.modelPaths = [.cause]
        return configuration
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let question: String
        let contains: [String]
        let lacks: [String]
        var testDescription: String { question }
    }

    static let rows: [Row] = [
        Row(question: "Is the kitchen light on?", contains: ["Yes", "Kitchen"], lacks: ["No,"]),
        Row(question: "Is the office light off?", contains: ["No"], lacks: ["Yes"]),
        Row(question: "Is the front door locked?", contains: ["Yes"], lacks: []),
        Row(question: "Is the back door lock locked?", contains: ["No"], lacks: ["Yes"]),
        Row(question: "What is the office temperature?", contains: ["72"], lacks: []),
        Row(question: "What is the office humidity?", contains: ["41"], lacks: []),
        Row(question: "Is Sam home?", contains: ["away"], lacks: ["is home"]),
        Row(question: "Is Alex home?", contains: ["home"], lacks: ["away"]),
        Row(question: "Is the office window open?", contains: ["Yes"], lacks: []),
        Row(question: "Are any windows open?", contains: ["Office"], lacks: []),
        Row(question: "How many lights are on?", contains: ["2"], lacks: []),
        Row(question: "Is the elevator on?", contains: ["couldn't find"], lacks: []),
        Row(question: "Turn on the kitchen light", contains: ["can't"], lacks: []),
        Row(question: "What is the capital of France?", contains: ["home"], lacks: []),
    ]

    @Test(arguments: rows) func codeWritesTheAnswer(row: Row) async {
        let result = await answerer().answer(row.question)
        for word in row.contains { #expect(result.answer.contains(word), "\(result.answer)") }
        for word in row.lacks { #expect(!result.answer.contains(word), "\(result.answer)") }
        #expect(result.usedModel == false)
    }

    @Test func aDeclinedActionNeverCallsTheModelOrTheSource() async {
        let phrased = Counter()
        let result = await answerer(phrase: { _, _ in await phrased.bump(); return "x" }).answer("lock the front door")
        #expect(result.resolution.route == .declineAction)
        #expect(result.path == .fixedDecline)
        #expect(await phrased.count == 0)
    }

    @Test func howLongSaysAnOrdinaryDuration() async {
        let result = await answerer().answer("How long has the kitchen light been on?")
        #expect(result.answer.contains("10 minutes"))
    }

    @Test func lastTimeForAnAutomationUsesLastTriggered() async {
        let result = await answerer().answer("When did the porch schedule automation last run?")
        #expect(result.answer.contains("2 hours"))
    }

    @Test func aCauseGoesThroughTheModelWhenOneIsGiven() async {
        let source = AskStubSource(logbookRows: [
            "light.demo_kitchen_light": [
                AskLogbookRow(when: AskDemoHouse.ago(600), state: "on", contextEventType: "automation_triggered", contextName: "Demo Dusk", contextMessage: "triggered by time"),
            ],
        ])
        let prompts = Collector()
        let result = await answerer(source: source, phrase: { instructions, prompt in
            await prompts.add(prompt)
            return "Demo Dusk turned it on ten minutes ago."
        }, configuration: causeViaModel).answer("Why is the kitchen light on?")
        #expect(result.usedModel)
        #expect(result.answer == "Demo Dusk turned it on ten minutes ago.")
        #expect(await prompts.items.first?.contains("Demo Dusk") == true)
    }

    @Test func aFailingModelFallsBackToTheDraft() async {
        struct Boom: Error {}
        let source = AskStubSource(logbookRows: [
            "light.demo_kitchen_light": [AskLogbookRow(when: AskDemoHouse.ago(600), state: "on", contextEventType: "automation_triggered", contextName: "Demo Dusk")],
        ])
        let result = await answerer(source: source, phrase: { _, _ in throw Boom() }, configuration: causeViaModel).answer("Why is the kitchen light on?")
        #expect(result.usedModel == false)
        #expect(result.answer == result.draft)
        #expect(result.error != nil)
    }

    @Test func withoutAModelTheDraftStandsIn() async {
        let source = AskStubSource(logbookRows: [
            "light.demo_kitchen_light": [AskLogbookRow(when: AskDemoHouse.ago(600), state: "on", contextEventType: "automation_triggered", contextName: "Demo Dusk")],
        ])
        let result = await answerer(source: source, configuration: causeViaModel).answer("Why is the kitchen light on?")
        #expect(result.answer.contains("Demo Dusk"))
        #expect(result.modelSkipped)
    }

    @Test func byDefaultNoAnswerGoesThroughTheModel() async {
        #expect(AskConfiguration().modelPaths.isEmpty)
        let source = AskStubSource(logbookRows: [
            "light.demo_kitchen_light": [AskLogbookRow(when: AskDemoHouse.ago(600), state: "on", contextEventType: "automation_triggered", contextName: "Demo Dusk")],
        ])
        let phrased = Counter()
        let result = await answerer(source: source, phrase: { _, _ in await phrased.bump(); return "x" }).answer("Why is the kitchen light on?")
        #expect(result.usedModel == false)
        #expect(result.answer.contains("Demo Dusk"))
        #expect(await phrased.count == 0)
    }

    @Test func aLockedPhoneDoesNotRevealSecurityState() async {
        let result = await answerer().answer("Is the front door locked?", allowing: .home)
        #expect(result.path == .fixedLocked)
        #expect(!result.answer.contains("Yes"))
    }

    @Test func resultsCarryTimingsAndFacts() async {
        let result = await answerer().answer("Is the kitchen light on?")
        #expect(result.timings.totalMs >= result.timings.resolveMs)
        #expect(!result.facts.isEmpty)
        #expect(result.sensitivity == .everyday)
    }
}

private actor Counter {
    var count = 0
    func bump() { count += 1 }
}

private actor Collector {
    var items: [String] = []
    func add(_ s: String) { items.append(s) }
}
