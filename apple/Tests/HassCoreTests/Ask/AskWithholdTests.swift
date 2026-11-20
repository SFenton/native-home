import Foundation
import Testing
@testable import HassCore

/// The highest sensitivity class is withheld by default: no lock, alarm, garage or camera state is spoken until the
/// configuration says so. Demo names only.
struct AskWithholdTests {
    private static let alarm = AskDemoHouse.state("alarm_control_panel.demo_hall", "armed_away", name: "Demo Hall Alarm")
    private static let unavailableLock = AskDemoHouse.state("lock.demo_cellar", "unavailable", name: "Demo Cellar Lock")

    private func answerer(withhold: Bool? = nil) -> AskAnswerer {
        var configuration = AskConfiguration()
        if let withhold { configuration.withholdSecurityState = withhold }
        return AskAnswerer(index: AskDemoHouse.index(configuration: configuration, states: AskDemoHouse.states + [Self.alarm, Self.unavailableLock]))
    }

    struct Row: Sendable, CustomTestStringConvertible {
        let question: String
        /// What an unwithheld answer says.
        let open: String
        var testDescription: String { question }
    }

    static let rows: [Row] = [
        Row(question: "Is the front door lock locked?", open: "Yes"),
        Row(question: "Is the garage door closed?", open: "Yes"),
        Row(question: "Is the hall alarm armed?", open: "armed away"),
        Row(question: "Is the driveway camera recording?", open: "Yes"),
        Row(question: "Is the office window open?", open: "Yes"),
        Row(question: "Are all the locks locked?", open: "No"),
        Row(question: "How long has the front door lock been locked?", open: "24 hours"),
    ]

    @Test func itIsOnByDefault() {
        #expect(AskConfiguration().withholdSecurityState)
        #expect(AskConfiguration().sensitivity == AskSensitivityRules())
    }

    @Test func aMissingKeyDecodesAsOnAndAnExplicitOffIsKept() throws {
        let missing = try JSONDecoder().decode(AskConfiguration.self, from: Data("{}".utf8))
        #expect(missing.withholdSecurityState)
        var off = AskConfiguration()
        off.withholdSecurityState = false
        let back = try JSONDecoder().decode(AskConfiguration.self, from: JSONEncoder().encode(off))
        #expect(back.withholdSecurityState == false)
    }

    @Test(arguments: rows) func securityStateIsWithheldEvenOnAnUnlockedPhone(row: Row) async {
        let result = await answerer().answer(row.question, allowing: .security)
        #expect(result.path == .fixedWithheld, "\(result.answer)")
        #expect(result.answer == "Open the app to check that.")
        #expect(result.usedModel == false)
    }

    @Test(arguments: rows) func turnedOffTheAnswerIsSpokenOnAnUnlockedPhone(row: Row) async {
        let result = await answerer(withhold: false).answer(row.question, allowing: .security)
        #expect(result.path == .code, "\(result.answer)")
        #expect(result.answer.contains(row.open), "\(result.answer)")
    }

    @Test func anEverydayAnswerIsNeverWithheld() async {
        let result = await answerer().answer("Is the kitchen light on?")
        #expect(result.path == .code)
        #expect(result.answer.contains("Yes"))
    }

    @Test func anUnavailableSecurityEntityGoesThroughTheSameGate() async {
        let locked = await answerer(withhold: false).answer("Is the cellar lock locked?", allowing: .home)
        #expect(locked.path == .fixedLocked)
        #expect(!locked.answer.contains("unavailable"), "\(locked.answer)")
        let withheld = await answerer().answer("Is the cellar lock locked?", allowing: .security)
        #expect(withheld.path == .fixedWithheld)
        let open = await answerer(withhold: false).answer("Is the cellar lock locked?", allowing: .security)
        #expect(open.path == .fixedUnavailable)
        #expect(open.answer.contains("unavailable"), "\(open.answer)")
    }

    @Test func anUnavailableEverydayEntityStillSaysSo() async {
        let result = await answerer().answer("Is the spare bulb on?", allowing: .everyday)
        #expect(result.path == .fixedUnavailable)
    }

    @Test func aWhichOneQuestionNamesNoState() async {
        let result = await answerer().answer("Is the door lock locked?")
        #expect(result.path == .fixedSeveral)
        #expect(!result.answer.contains("unlocked") && !result.answer.contains("is locked"), "\(result.answer)")
    }
}
