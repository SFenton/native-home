@testable import HassDesign
import SwiftUI
import Testing

/// ``TapFeedback``, ``TapCounter``, ``TransientFailure`` and the caption that shows it (owner, 2026-10-24).
@MainActor
struct TapFeedbackTests {
    @Test func theVocabularyIsOneSetOfFourPatterns() {
        #expect(TapFeedback.tap == .impact(weight: .light))
        #expect(TapFeedback.step == .selection)
        #expect(TapFeedback.failure == .error)
        #expect(TapFeedback.confirmation == .success)
    }

    @Test func aCounterCountsEveryTap() {
        var counter = TapCounter()
        #expect(counter.count == 0)
        counter.tap()
        counter.tap()
        #expect(counter.count == 2)
        #expect(counter != TapCounter())
    }

    @Test func switchesCommandsAndChoicesPlayATapButPagesDoNot() {
        #expect(GlassTileKind.toggle.playsTapFeedback)
        #expect(GlassTileKind.command.playsTapFeedback)
        #expect(GlassTileKind.selection(isSelected: false).playsTapFeedback)
        #expect(!GlassTileKind.navigate.playsTapFeedback)
        #expect(!GlassTileKind.state.playsTapFeedback)
    }

    @Test func aFailureShowsThenClears() async {
        let failure = TransientFailure(duration: .milliseconds(30))
        #expect(failure.message == nil)
        failure.show("Couldn't set 68°.")
        #expect(failure.message == "Couldn't set 68°.")
        #expect(failure.count == 1)
        failure.show("Again")
        #expect(failure.count == 2)
        for _ in 0..<200 where failure.message != nil { try? await Task.sleep(for: .milliseconds(10)) }
        #expect(failure.message == nil)
        failure.show("Once more")
        failure.clear()
        #expect(failure.message == nil)
        #expect(TransientFailure.duration == .seconds(4))
    }

}
