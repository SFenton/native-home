@testable import HassDesign
import Testing

/// The rules for a diffable list that adds or removes rows (owner, 2026-11-05): person and live changes on screen animate, Reduce Motion
/// fades, and a first apply, a reapply, a cold launch and an off-window list never move. Pure: no view is built.
struct ListUpdateTransitionTests {
    private func decide(
        window: Bool = true, first: Bool = false, reapply: Bool = false, structural: Bool = true,
        cause: ListUpdateCause = .person, reduceMotion: Bool = false
    ) -> ListUpdateTransition {
        ListUpdateTransition.decide(hasWindow: window, isFirstApply: first, isReapply: reapply, isStructural: structural,
                                    cause: cause, reduceMotion: reduceMotion)
    }

    @Test func aPersonCausedRemovalAnimates() {
        #expect(decide(cause: .person) == .animate)
    }

    @Test func aLiveRemovalOnScreenAnimatesToo() {
        #expect(decide(cause: .live) == .animate)
    }

    @Test func reduceMotionFadesInsteadOfSliding() {
        #expect(decide(cause: .person, reduceMotion: true) == .fade)
        #expect(decide(cause: .live, reduceMotion: true) == .fade)
    }

    @Test func aResetNeverAnimates() {
        #expect(decide(cause: .reset) == .none)
        #expect(decide(cause: .reset, reduceMotion: true) == .none)
    }

    @Test func aRedrawInPlaceNeverAnimates() {
        for cause in [ListUpdateCause.reset, .live, .person] {
            #expect(decide(structural: false, cause: cause) == .none)
        }
    }

    @Test func theFirstApplyNeverAnimates() {
        #expect(decide(first: true, cause: .person) == .none)
        #expect(decide(first: true, cause: .live, reduceMotion: true) == .none)
    }

    @Test func aReapplyNeverAnimates() {
        #expect(decide(reapply: true, cause: .person) == .none)
        #expect(decide(reapply: true, cause: .live) == .none)
    }

    @Test func aListOffScreenNeverAnimates() {
        #expect(decide(window: false, cause: .person) == .none)
    }

    @Test func theReapplyWindowIsTwoSeconds() {
        #expect(ListUpdateTransition.isReapply(elapsedSinceReapply: nil) == false)
        #expect(ListUpdateTransition.isReapply(elapsedSinceReapply: .milliseconds(1_999)))
        #expect(ListUpdateTransition.isReapply(elapsedSinceReapply: .seconds(2)) == false)
    }
}
