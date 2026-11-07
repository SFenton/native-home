@testable import HassDesign
import Testing

/// Whether an answer still applies to the question that was asked (``TileActionConfirmation/holds(for:in:)``).
struct TileActionConfirmationTests {
    static let question = TileActionConfirmation(title: "Disarm the Security System?", confirmVerb: "Disarm")
    static let disarm = TileActionItem(id: "alarm", verb: "Disarm", symbol: "shield.slash", isOn: true, feedback: .tracked, confirmation: question)

    func ask(_ item: TileActionItem = disarm) -> TileConfirmationRequest {
        TileConfirmationRequest(item: item, confirmation: Self.question)
    }

    @Test func anUnchangedActionStillHolds() {
        #expect(TileActionConfirmation.holds(for: ask(), in: [Self.disarm]))
    }

    @Test func aChangedStateVerbOrPhaseDropsTheAnswer() {
        var flipped = Self.disarm
        flipped.isOn = false
        flipped.verb = "Arm Home"
        #expect(!TileActionConfirmation.holds(for: ask(), in: [flipped]), "disarmed elsewhere")
        var sameVerb = Self.disarm
        sameVerb.isOn = false
        #expect(!TileActionConfirmation.holds(for: ask(), in: [sameVerb]), "state alone")
        var waiting = Self.disarm
        waiting.phase = .inFlight
        #expect(!TileActionConfirmation.holds(for: ask(), in: [waiting]), "cannot run now")
    }

    @Test func aMissingActionOrADifferentQuestionDropsTheAnswer() {
        #expect(!TileActionConfirmation.holds(for: ask(), in: []))
        var unasked = Self.disarm
        unasked.confirmation = nil
        #expect(!TileActionConfirmation.holds(for: ask(), in: [unasked]))
        var other = Self.disarm
        other.confirmation = TileActionConfirmation(title: "Something Else?", confirmVerb: "Go")
        #expect(!TileActionConfirmation.holds(for: ask(), in: [other]))
    }
}
